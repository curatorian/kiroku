defmodule Kiroku.Saf.Importer do
  @moduledoc """
  Imports items from a DSpace Simple Archive Format archive.

  Accepts either a directory tree or a `.zip` (which is unpacked to a temp dir
  first). For each `item_NNN/` subdirectory it:

    1. Parses `dublin_core.xml` and (if present) `metadata_local.xml`.
    2. Reads the optional `handle`, `collections`, and `contents` files.
    3. Resolves the target collection (CLI `-c` flag wins, else the
       `collections` file's first line, else `:error`).
    4. Builds typed attrs via `Kiroku.Saf.Mapping` and upserts the item
       (idempotent on `handle` so re-imports update rather than duplicate).
    5. For each `contents` line, uploads the bitstream file via
       `Kiroku.Storage.Uploader` and creates a `Bitstream` record.

  `dry_run: true` validates and reports without writing anything.

  Returns `{:ok, stats}` where stats is a map of processed/inserted/updated/
  skipped/failed counts plus a list of per-item errors.
  """

  require Logger

  alias Kiroku.{Content, Repo, Repository, Storage.Uploader}
  alias Kiroku.Repository.{Collection, Item, ItemKeyword, ItemMetadata}
  alias Kiroku.Saf.{DublinCore, Mapping}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Imports a SAF archive. `source` is a directory or a `.zip` path.

  Options:
    - `:collection`   — handle or id of the owning collection (overrides file)
    - `:dry_run`      — validate only, write nothing (default false)
    - `:resume_map`   — map of item_dir → handle for resume support (future)
  """
  def import_archive(source, opts \\ []) do
    with {:ok, dir, tmp?} <- materialize_source(source) do
      try do
        item_dirs = list_item_dirs(dir)

        if item_dirs == [] do
          {:error, :no_item_dirs}
        else
          target_collection = resolve_collection_opt(Keyword.get(opts, :collection))
          dry_run? = Keyword.get(opts, :dry_run, false)

          results =
            Enum.map(item_dirs, fn item_dir ->
              import_one(item_dir, target_collection, dry_run?)
            end)

          {:ok, aggregate(results)}
        end
      after
        if tmp?, do: File.rm_rf!(dir)
      end
    end
  end

  # ── Source materialization ──────────────────────────────────────────────────

  # If given a zip, unpack into a temp dir. Returns {dir, tmp?}.
  defp materialize_source(path) do
    cond do
      File.dir?(path) ->
        {:ok, path, false}

      String.ends_with?(path, ".zip") ->
        tmp = Path.join(System.tmp_dir!(), "kiroku_saf_#{:erlang.system_time(:nanosecond)}")
        File.mkdir_p!(tmp)

        case :zip.unzip(to_charlist(path), [{:cwd, to_charlist(tmp)}]) do
          {:ok, _} -> {:ok, flatten_single_root(tmp), true}
          {:error, reason} -> {:error, {:unzip_failed, reason}}
        end

      true ->
        {:error, :unknown_source}
    end
  end

  # Some zips wrap everything in a single top-level directory; unwrap it so the
  # item_NNN dirs are directly under `tmp`.
  defp flatten_single_root(dir) do
    entries = File.ls!(dir)

    case entries do
      [single] ->
        inner = Path.join(dir, single)
        if File.dir?(inner) and list_item_dirs(inner) != [], do: inner, else: dir

      _ ->
        dir
    end
  end

  defp list_item_dirs(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(fn name ->
      String.starts_with?(name, "item_") and File.dir?(Path.join(dir, name))
    end)
    |> Enum.map(fn name -> Path.join(dir, name) end)
    |> Enum.sort()
  end

  # ── Collection resolution ───────────────────────────────────────────────────

  defp resolve_collection_opt(nil), do: :unset

  defp resolve_collection_opt(handle_or_id) when is_binary(handle_or_id) do
    cond do
      Repo.get_by(Collection, handle: handle_or_id) != nil ->
        {:ok, Repo.get_by(Collection, handle: handle_or_id)}

      String.match?(handle_or_id, ~r/^[0-9a-f-]+$/) ->
        case Repo.get(Collection, handle_or_id) do
          nil -> {:error, :collection_not_found}
          c -> {:ok, c}
        end

      true ->
        {:error, :collection_not_found}
    end
  end

  defp resolve_collection_file(item_dir) do
    path = Path.join(item_dir, "collections")

    case File.read(path) do
      {:ok, contents} ->
        case contents |> String.split("\n", trim: true) |> List.first() do
          nil -> {:error, :no_collection_in_file}
          handle -> resolve_collection_opt(handle)
        end

      {:error, _} ->
        {:error, :no_collection_file}
    end
  end

  defp resolve_collection(item_dir, :unset), do: resolve_collection_file(item_dir)
  defp resolve_collection(_item_dir, resolved), do: resolved

  # ── Per-item import ─────────────────────────────────────────────────────────

  defp import_one(item_dir, target_collection, dry_run?) do
    with {:ok, dc_values} <- read_schema_file(item_dir, "dublin_core.xml"),
         {:ok, local_values} <- read_schema_file_optional(item_dir, "metadata_local.xml"),
         {:ok, shape} <- build_item_shape(dc_values, local_values),
         {:ok, collection} <- resolve_collection(item_dir, target_collection),
         handle <- read_handle(item_dir),
         {:ok, contents} <- read_contents(item_dir) do
      attrs = Map.merge(shape.attrs, %{collection_id: collection.id})

      attrs = if handle, do: Map.put(attrs, :handle, handle), else: attrs

      if dry_run? do
        validate_dry_run(attrs, shape, contents, item_dir)
      else
        persist_item(attrs, shape, contents, item_dir)
      end
    else
      {:error, reason} ->
        %{status: :error, item_dir: item_dir, reason: reason}
    end
  end

  defp read_schema_file(item_dir, filename) do
    path = Path.join(item_dir, filename)

    case File.read(path) do
      {:ok, xml} ->
        DublinCore.parse_xml(xml)

      {:error, _} ->
        {:error, {:missing_file, filename}}
    end
  end

  defp read_schema_file_optional(item_dir, filename) do
    path = Path.join(item_dir, filename)

    case File.read(path) do
      {:ok, xml} ->
        case DublinCore.parse_xml(xml) do
          {:ok, values} -> {:ok, values}
          error -> error
        end

      {:error, _} ->
        {:ok, []}
    end
  end

  defp build_item_shape(dc_values, local_values) do
    {:ok, Mapping.to_item_shape(dc_values, local_values)}
  rescue
    error -> {:error, {:mapping_failed, inspect(error)}}
  end

  defp read_handle(item_dir) do
    case File.read(Path.join(item_dir, "handle")) do
      {:ok, contents} -> String.trim(contents)
      {:error, _} -> nil
    end
  end

  # ── Dry-run ─────────────────────────────────────────────────────────────────

  defp validate_dry_run(attrs, shape, contents, item_dir) do
    changeset = %Item{} |> Item.import_changeset(attrs)

    contributor_count =
      length(shape.authors) + length(shape.advisors) + length(shape.examiners) +
        length(shape.team_members)

    if changeset.valid? do
      %{
        status: :ok,
        action: :would_insert,
        item_dir: item_dir,
        title: attrs[:title],
        bitstream_count: length(contents),
        contributor_count: contributor_count,
        keyword_count: length(shape.keywords)
      }
    else
      %{
        status: :error,
        item_dir: item_dir,
        reason: {:validation, format_errors(changeset)}
      }
    end
  end

  # ── Persistence ─────────────────────────────────────────────────────────────

  defp persist_item(attrs, shape, contents, item_dir) do
    # Detect the action BEFORE upserting, otherwise the just-inserted row makes
    # a fresh insert look like an update.
    existed? = attrs[:handle] && Repository.get_item_by_handle(attrs[:handle]) != nil
    action = if existed?, do: :updated, else: :inserted

    Repo.transaction(fn ->
      item = upsert_item!(attrs)

      create_contributors!(item, shape)
      create_keywords!(item, shape)
      create_extras!(item, shape)
      import_bitstreams!(item, contents, item_dir)

      %{
        status: :ok,
        action: action,
        item_dir: item_dir,
        item_id: item.id,
        title: attrs[:title]
      }
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> %{status: :error, item_dir: item_dir, reason: inspect(reason)}
    end
  end

  # Idempotent on handle: re-importing an item with the same handle updates it
  # instead of creating a duplicate (matches DSpace mapfile semantics loosely).
  defp upsert_item!(attrs) do
    case attrs[:handle] && Repository.get_item_by_handle(attrs[:handle]) do
      nil ->
        {:ok, item} =
          %Item{}
          |> Item.import_changeset(attrs)
          |> Repo.insert()

        item

      %Item{} = existing ->
        {:ok, updated} =
          existing
          |> Item.import_changeset(attrs)
          |> Repo.update()

        updated
    end
  end

  defp create_contributors!(item, shape) do
    Enum.each(shape.authors, fn a ->
      {:ok, _} = Repository.create_item_author(Map.put(a, :item_id, item.id))
    end)

    Enum.each(shape.advisors, fn a ->
      {:ok, _} = Repository.create_item_advisor(Map.put(a, :item_id, item.id))
    end)

    Enum.each(shape.examiners, fn e ->
      {:ok, _} = Repository.create_item_examiner(Map.put(e, :item_id, item.id))
    end)

    Enum.each(shape.team_members, fn m ->
      {:ok, _} = Repository.create_item_team_member(Map.put(m, :item_id, item.id))
    end)
  end

  defp create_keywords!(item, shape) do
    Enum.each(shape.keywords, fn kw ->
      attrs = kw |> Map.put_new(:language, :id) |> Map.put(:item_id, item.id)

      {:ok, _} =
        %ItemKeyword{}
        |> ItemKeyword.changeset(attrs)
        |> Repo.insert()
    end)
  end

  defp create_extras!(item, shape) do
    Enum.each(shape.extras, fn extra ->
      {:ok, _} =
        %ItemMetadata{}
        |> ItemMetadata.changeset(Map.put(extra, :item_id, item.id))
        |> Repo.insert()
    end)
  end

  defp import_bitstreams!(item, contents, item_dir) do
    Enum.each(contents, fn entry ->
      file_path = Path.join(item_dir, entry.filename)

      cond do
        not File.exists?(file_path) or File.stat!(file_path).size == 0 ->
          # Placeholder from a failed export fetch, or genuinely missing.
          :ok

        true ->
          {:ok, content} = File.read(file_path)

          key = Uploader.storage_key(item.id, entry.bundle, entry.filename)

          case Uploader.upload(key, content, mime_type: mime_for(entry.filename)) do
            {:ok, %{checksum: checksum}} ->
              {:ok, _} =
                Content.create_bitstream(
                  %{
                    item_id: item.id,
                    filename: entry.filename,
                    bundle_name: entry.bundle,
                    sequence: entry.sequence,
                    description: entry.description,
                    storage_path: key,
                    checksum: checksum,
                    checksum_algorithm: "MD5",
                    access_level: entry.access_level
                  }
                  |> Map.merge(Uploader.record_attrs())
                )

            {:error, reason} ->
              require Logger
              Logger.error("SAF upload failed for #{entry.filename}: #{inspect(reason)}")
          end
      end
    end)
  end

  # ── contents file parsing ───────────────────────────────────────────────────

  defp read_contents(item_dir) do
    path = Path.join(item_dir, "contents")

    case File.read(path) do
      {:ok, contents} ->
        entries =
          contents
          |> String.split("\n", trim: true)
          |> Enum.with_index(1)
          |> Enum.map(fn {line, idx} -> parse_contents_line(line, idx) end)

        {:ok, entries}

      {:error, _} ->
        {:ok, []}
    end
  end

  # `filename[\tbundle:X][\tdescription:Y][\tprimary:true]`
  defp parse_contents_line(line, default_seq) do
    [filename | annotations] = String.split(line, "\t")

    parsed = Enum.into(annotations, %{}, &parse_annotation/1)

    bundle =
      case Map.get(parsed, "bundle") do
        nil -> :ORIGINAL
        bundle_str -> bundle_atom(bundle_str)
      end

    %{
      filename: String.trim(filename),
      bundle: bundle,
      sequence: Map.get(parsed, "seq", default_seq),
      description: Map.get(parsed, "description"),
      primary: Map.get(parsed, "primary") == "true",
      access_level: default_access_for_bundle(bundle)
    }
  end

  defp parse_annotation(annotation) do
    case String.split(annotation, ":", parts: 2) do
      [k, v] -> {k, v}
      [k] -> {k, "true"}
    end
  end

  defp bundle_atom("ORIGINAL"), do: :ORIGINAL
  defp bundle_atom("THUMBNAIL"), do: :THUMBNAIL
  defp bundle_atom("CHAPTER"), do: :CHAPTER
  defp bundle_atom("SUPPLEMENTAL"), do: :SUPPLEMENTAL
  defp bundle_atom("ADMINISTRATIVE"), do: :ADMINISTRATIVE
  defp bundle_atom("LICENSE"), do: :LICENSE
  defp bundle_atom("MEDIA"), do: :MEDIA
  defp bundle_atom("SOURCE"), do: :SOURCE
  defp bundle_atom(_), do: :ORIGINAL

  # Bundle access rules mirror Bitstream.changeset's enforce_bundle_access_rules.
  defp default_access_for_bundle(:THUMBNAIL), do: :open
  defp default_access_for_bundle(b) when b in [:ADMINISTRATIVE, :LICENSE], do: :restricted
  defp default_access_for_bundle(_), do: :inherit

  defp mime_for(filename) do
    MIME.from_path(filename)
  rescue
    _ -> "application/octet-stream"
  end

  # ── Aggregation ─────────────────────────────────────────────────────────────

  defp aggregate(results) do
    {inserted, updated, skipped, failed, errors} =
      Enum.reduce(results, {0, 0, 0, 0, []}, fn r, {ins, upd, skp, fail, errs} ->
        case r do
          # Dry-run validates only; nothing is written, so don't count as inserted.
          %{status: :ok, action: :would_insert} -> {ins, upd, skp, fail, errs}
          %{status: :ok, action: :inserted} -> {ins + 1, upd, skp, fail, errs}
          %{status: :ok, action: :updated} -> {ins, upd + 1, skp, fail, errs}
          %{status: :ok} -> {ins, upd, skp + 1, fail, errs}
          %{status: :error} -> {ins, upd, skp, fail + 1, [r | errs]}
        end
      end)

    %{
      processed: length(results),
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      failed: failed,
      errors: Enum.reverse(errors)
    }
  end

  defp format_errors(changeset) do
    Enum.map(changeset.errors, fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end
end
