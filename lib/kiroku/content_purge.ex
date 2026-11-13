defmodule Kiroku.ContentPurge do
  @moduledoc """
  Deletes repository content together with its storage objects.

  Deleting items or bitstreams through the application does NOT remove the
  underlying files from storage — `Uploader.delete/2` is not wired into the
  app's delete paths, so objects survive in MinIO/local disk after the rows
  are gone. This tool deletes in the correct order:

    1. the storage object for every bitstream of the matched items,
    2. the item rows (all children — bitstreams, versions, relations, download
       events — cascade via foreign keys).

  It is deliberately conservative:

    * Without `--execute` it is a dry run and only reports.
    * Bitstreams matching the time window but attached to *non-matching* items
      are reported for manual review, never auto-deleted.
    * Orphaned storage objects (files with no DB row — e.g. left behind by
      earlier app-level deletes) are listed with `--orphans`, never deleted
      unless you explicitly pass `--orphan-execute` after reviewing the list.

  Usage (dev):

      mix kiroku.purge_content
      mix kiroku.purge_content --title-prefix tmp_ --since 2026-11-10T00:00:00
      mix kiroku.purge_content --item-ids <uuid1>,<uuid2> --title-prefix "" --execute
      mix kiroku.purge_content --orphans
      mix kiroku.purge_content --orphans --orphan-execute

  Usage in a prod release (dry run first!):

      bin/kiroku eval 'Kiroku.Release.purge_content(["--title-prefix", "tmp_"])'
      bin/kiroku eval 'Kiroku.Release.purge_content(["--title-prefix", "tmp_", "--execute"])'
  """

  import Ecto.Query

  alias Kiroku.Content.Bitstream
  alias Kiroku.{Repo, Settings, Storage.Uploader}
  alias Kiroku.Repository.Item

  @upload_root Uploader.local_upload_dir()

  # ── Entry point ─────────────────────────────────────────────────────────────

  def run(argv) do
    opts = parse_args!(argv)
    ensure_criteria!(opts)

    summary = report(opts)

    if opts[:execute] do
      IO.puts([
        "\n",
        IO.ANSI.red(),
        "EXECUTE MODE — deleting matched items, their bitstream rows and storage objects.",
        IO.ANSI.reset(),
        "\n"
      ])

      purge(opts)
    else
      IO.puts(
        "\nDry run. Re-run with --execute to delete the matched items, their bitstreams and the storage objects."
      )
    end

    summary
  end

  # ── Options ─────────────────────────────────────────────────────────────────

  def parse_args!(argv) do
    defaults = [title_prefix: "arx_", execute: false, orphans: false, orphan_execute: false]

    {parsed, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          title_prefix: :string,
          since: :string,
          until: :string,
          item_ids: :string,
          execute: :boolean,
          orphans: :boolean,
          orphan_execute: :boolean
        ]
      )

    defaults
    |> Keyword.merge(parsed)
    |> Keyword.put(:title_prefix, prefix_or_nil(parsed[:title_prefix]))
    |> Keyword.put(:since, parse_time(parsed[:since]))
    |> Keyword.put(:until, parse_time(parsed[:until]))
    |> Keyword.put(:item_ids, parse_ids(parsed[:item_ids]))
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp prefix_or_nil(nil), do: nil
  defp prefix_or_nil(""), do: nil
  defp prefix_or_nil(prefix), do: String.replace_suffix(prefix, "*", "")

  defp parse_time(nil), do: nil

  defp parse_time(raw) do
    case NaiveDateTime.from_iso8601(raw) do
      {:ok, dt} ->
        dt

      {:error, _} ->
        case DateTime.from_iso8601(raw) do
          {:ok, dt, _offset} ->
            DateTime.to_naive(dt)

          {:error, reason} ->
            raise ArgumentError,
                  "invalid --since/--until value #{inspect(raw)}: #{inspect(reason)}"
        end
    end
  end

  defp parse_ids(nil), do: nil

  defp parse_ids(raw) do
    raw
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp ensure_criteria!(opts) do
    if is_nil(opts[:title_prefix]) and is_nil(opts[:since]) and is_nil(opts[:item_ids]) do
      raise ArgumentError,
        message:
          "refusing to match everything: pass at least one of --title-prefix, --since or --item-ids"
    end
  end

  # ── Reporting ───────────────────────────────────────────────────────────────

  def report(opts) do
    items = suspect_items(opts)
    ids = Enum.map(items, & &1.id)

    print_items(items)
    bitstreams = print_bitstreams(ids)
    outside = print_outside_bitstreams(opts, ids)

    orphans =
      if opts[:orphans] do
        print_orphans(opts)
      else
        []
      end

    %{items: items, bitstreams: bitstreams, outside_bitstreams: outside, orphans: orphans}
  end

  defp print_items(items) do
    IO.puts("\n── Matched items (#{length(items)}) " <> String.duplicate("─", 34))

    Enum.each(items, fn item ->
      IO.puts(
        "  #{item.id}  #{inspect(item.title)}  status=#{item.status}  created=#{item.inserted_at}"
      )
    end)
  end

  defp print_bitstreams(item_ids) do
    bitstreams =
      if item_ids == [] do
        []
      else
        Repo.all(
          from b in Bitstream,
            where: b.item_id in ^item_ids,
            order_by: b.inserted_at
        )
      end

    IO.puts(
      "\n── Bitstreams on matched items (#{length(bitstreams)}) " <> String.duplicate("─", 25)
    )

    Enum.each(bitstreams, fn bs ->
      IO.puts("  #{format_bitstream(bs)}")
    end)

    bitstreams
  end

  defp print_outside_bitstreams(opts, matched_ids) do
    since = opts[:since]

    outside =
      if since do
        Repo.all(
          from b in Bitstream,
            join: i in Item,
            on: i.id == b.item_id,
            where: b.inserted_at >= ^since,
            where: b.item_id not in ^matched_ids,
            order_by: b.inserted_at,
            select: {b, i.title}
        )
      else
        []
      end

    IO.puts(
      "\n── Bitstreams in the window attached to OTHER items (#{length(outside)}) — review manually " <>
        String.duplicate("─", 10)
    )

    Enum.each(outside, fn {bs, title} ->
      IO.puts("  #{format_bitstream(bs)}  item=#{inspect(title)}")
    end)

    outside
  end

  defp format_bitstream(bs) do
    loc =
      cond do
        bs.storage_type == :url -> "url=#{bs.storage_url}"
        is_binary(bs.storage_bucket) -> "s3://#{bs.storage_bucket}/#{bs.storage_path}"
        true -> bs.storage_path
      end

    "#{bs.id}  #{bs.bundle_name}  #{bs.filename}  #{loc}"
  end

  # ── Storage objects ─────────────────────────────────────────────────────────

  @doc "Deletes the stored file for a bitstream based on the bitstream's own storage_type."
  def delete_object(%Bitstream{storage_type: :url}), do: {:skipped, :url_redirect}
  def delete_object(%Bitstream{storage_path: nil}), do: {:skipped, :no_storage_path}

  def delete_object(%Bitstream{storage_type: :local, storage_path: path}) do
    full = Path.join(@upload_root, path)

    cond do
      not File.exists?(full) ->
        {:skipped, :not_found}

      String.contains?(path, "..") ->
        {:skipped, :unsafe_path}

      true ->
        File.rm!(full)
        {:deleted, path}
    end
  end

  def delete_object(%Bitstream{storage_type: :s3, storage_path: path} = bs) do
    bucket = bs.storage_bucket || Settings.storage_bucket()

    bucket
    |> ExAws.S3.delete_object(path)
    |> ExAws.request(Uploader.s3_config())
    |> case do
      {:ok, _} -> {:deleted, "s3://#{bucket}/#{path}"}
      {:error, reason} -> {:error, "s3://#{bucket}/#{path}", reason}
    end
  end

  # ── Purge ───────────────────────────────────────────────────────────────────

  @doc """
  Deletes the matched items: storage objects first, then the rows (children
  cascade). Bitstreams on non-matching items are never touched.
  """
  def purge(opts) do
    items = suspect_items(opts)

    results =
      Enum.map(items, fn item ->
        bitstreams = Repo.all(from b in Bitstream, where: b.item_id == ^item.id)

        object_results =
          Enum.map(bitstreams, fn bs ->
            result = delete_object(bs)
            IO.puts("  object  #{result_label(result)}")
            result
          end)

        case Repo.delete(item) do
          {:ok, _} ->
            IO.puts("  item    #{item.id}  #{inspect(item.title)}  deleted")
            {:ok, item.id, object_results}

          {:error, changeset} ->
            IO.puts("  item    #{item.id}  FAILED: #{inspect(changeset.errors)}")
            {:error, item.id, object_results}
        end
      end)

    ok = Enum.count(results, &match?({:ok, _, _}, &1))
    errors = Enum.filter(results, &match?({:error, _, _}, &1))
    IO.puts("\nPurged #{ok}/#{length(items)} items.")
    errors
  end

  defp result_label({:deleted, loc}), do: "deleted  #{loc}"
  defp result_label({:skipped, reason}), do: "skipped (#{reason})"
  defp result_label({:error, loc, reason}), do: "ERROR    #{loc}: #{inspect(reason)}"

  # ── Orphan scan ─────────────────────────────────────────────────────────────

  defp print_orphans(opts) do
    known = MapSet.new(Repo.all(from b in Bitstream, select: b.storage_path))

    orphans =
      case Settings.storage_adapter() do
        :s3 -> s3_orphans(Settings.storage_bucket(), known)
        _ -> local_orphans(known)
      end

    IO.puts(
      "\n── Orphaned storage objects with no DB row (#{length(orphans)}) " <>
        String.duplicate("─", 18)
    )

    Enum.each(orphans, fn key -> IO.puts("  #{key}") end)

    cond do
      orphans == [] ->
        :ok

      opts[:orphan_execute] ->
        IO.puts("\nORPHAN EXECUTE MODE — deleting every orphaned object listed above.")
        Enum.each(orphans, &delete_orphan/1)

      true ->
        IO.puts(
          "  (not deleted automatically — review first, then re-run with --orphan-execute,\n" <>
            "   or remove with mc rm / File.rm)"
        )
    end

    orphans
  end

  defp delete_orphan("items/" <> _rest = key) do
    result =
      case Settings.storage_adapter() do
        :s3 -> delete_s3_object(Settings.storage_bucket(), key)
        _ -> delete_local_object(key)
      end

    IO.puts("  orphan  #{result_label(result)}")
    result
  end

  defp delete_orphan(key) do
    IO.puts("  orphan  skipped (unexpected key: #{key})")
    {:skipped, :unexpected_key}
  end

  defp delete_s3_object(bucket, key) do
    bucket
    |> ExAws.S3.delete_object(key)
    |> ExAws.request(Uploader.s3_config())
    |> case do
      {:ok, _} -> {:deleted, "s3://#{bucket}/#{key}"}
      {:error, reason} -> {:error, "s3://#{bucket}/#{key}", reason}
    end
  end

  defp delete_local_object(key) do
    full = Path.join(@upload_root, key)

    cond do
      String.contains?(key, "..") ->
        {:skipped, :unsafe_path}

      not File.exists?(full) ->
        {:skipped, :not_found}

      true ->
        File.rm!(full)
        {:deleted, key}
    end
  end

  defp s3_orphans(nil, _known), do: []

  defp s3_orphans(bucket, known) do
    bucket
    |> ExAws.S3.list_objects_v2(prefix: "items/")
    # Explicit config — otherwise ExAws falls back through its default chain
    # (AWS_* env vars, then the EC2 instance metadata endpoint) and crashes
    # on non-EC2 hosts like a podman server.
    |> ExAws.stream!(Uploader.s3_config())
    |> Enum.reject(&(&1.key in known))
    |> Enum.map(& &1.key)
  rescue
    e ->
      IO.puts("  (S3 listing failed: #{Exception.message(e)})")
      []
  end

  defp local_orphans(known) do
    @upload_root
    |> Path.join("items/**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, @upload_root))
    |> Enum.reject(&(&1 in known))
  end

  # ── Matching ────────────────────────────────────────────────────────────────

  def suspect_items(opts) do
    Item
    |> apply_criteria(opts)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  defp apply_criteria(query, opts) do
    query
    |> apply_prefix(opts[:title_prefix])
    |> apply_since(opts[:since])
    |> apply_until(opts[:until])
    |> apply_ids(opts[:item_ids])
  end

  defp apply_prefix(query, nil), do: query
  defp apply_prefix(query, prefix), do: where(query, [i], like(i.title, ^"#{prefix}%"))

  defp apply_since(query, nil), do: query
  defp apply_since(query, since), do: where(query, [i], i.inserted_at >= ^since)

  defp apply_until(query, nil), do: query
  defp apply_until(query, until), do: where(query, [i], i.inserted_at <= ^until)

  defp apply_ids(query, nil), do: query
  defp apply_ids(query, ids), do: where(query, [i], i.id in ^ids)
end
