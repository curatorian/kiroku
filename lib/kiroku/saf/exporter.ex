defmodule Kiroku.Saf.Exporter do
  @moduledoc """
  Exports Kiroku items into the DSpace Simple Archive Format.

  Produces a directory tree:

      dest/
        item_000/
          dublin_core.xml
          metadata_local.xml
          handle
          contents
          collections
          <bitstream files…>
        item_001/…

  …and can package it into a ZIP via `to_zip/2`.

  Bitstream files are materialized into each item directory:
    - `:local` storage → copied from the local uploads dir
    - `:s3` storage    → fetched via the configured ExAws config
    - `:url` storage   → downloaded with Req (legacy-imported files)

  Failed downloads are skipped with a warning rather than aborting the export,
  so a single unreachable URL doesn't poison the whole archive.
  """

  require Logger

  alias Kiroku.Content.Bitstream
  alias Kiroku.Repository
  alias Kiroku.Saf.{DublinCore, Mapping}

  @local_upload_dir "priv/uploads"

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Exports a single item to `dest/item_000/`.
  Returns `{:ok, item_dir}` or `{:error, reason}`.
  """
  def export_item(item, dest, opts \\ []) do
    seq_start = Keyword.get(opts, :seq_start, 0)
    item_dir = Path.join(dest, "item_#{pad(seq_start)}")

    with :ok <- File.mkdir_p(item_dir),
         :ok <- write_item(item, item_dir) do
      {:ok, item_dir}
    end
  end

  @doc """
  Exports every item in a collection to numbered `item_NNN/` directories.
  Returns `{:ok, count, dest}` or `{:error, reason}`.

  Pass `only: :published` (default) to restrict to published, discoverable items,
  or `only: :all` to include every status.
  """
  def export_collection(collection_id, dest, opts \\ []) do
    filter = Keyword.get(opts, :only, :published)

    items = list_items(collection_id, filter)

    File.mkdir_p!(dest)

    Enum.reduce_while(items, {0, 0}, fn item_id, {idx, count} ->
      item = Repository.get_item_with_preloads!(item_id)

      case export_item(item, dest, seq_start: idx) do
        {:ok, _dir} ->
          {:cont, {idx + 1, count + 1}}

        {:error, reason} ->
          Logger.error("[SafExporter] item #{item_id} failed: #{inspect(reason)}")
          {:cont, {idx + 1, count}}
      end
    end)
    |> case do
      {count, _} -> {:ok, count, dest}
    end
  end

  @doc """
  Exports an arbitrary list of item ids to numbered directories.
  """
  def export_items(item_ids, dest, _opts \\ []) do
    File.mkdir_p!(dest)

    {count, _} =
      Enum.reduce(item_ids, {0, 0}, fn item_id, {idx, count} ->
        item = Repository.get_item_with_preloads!(item_id)

        case export_item(item, dest, seq_start: idx) do
          {:ok, _dir} ->
            {idx + 1, count + 1}

          {:error, reason} ->
            Logger.error("[SafExporter] item #{item_id} failed: #{inspect(reason)}")
            {idx + 1, count}
        end
      end)

    {:ok, count, dest}
  end

  @doc """
  Packages a SAF directory tree into a zip archive.
  Returns `{:ok, zip_path}`.
  """
  def to_zip(saf_dir, zip_path) do
    files =
      saf_dir
      |> Path.join("**")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    # Store paths relative to saf_dir so the zip root contains item_NNN/…
    relative = Enum.map(files, &{Path.relative_to(&1, saf_dir), &1})

    :ok =
      :zip.create(
        to_charlist(zip_path),
        relative |> Enum.map(fn {rel, _} -> to_charlist(rel) end),
        cwd: to_charlist(saf_dir)
      )

    {:ok, zip_path}
  end

  # ── Per-item writing ─────────────────────────────────────────────────────────

  defp write_item(item, item_dir) do
    %{dc: dc_values, local: local_values} = Mapping.from_item(item)

    File.write!(Path.join(item_dir, "dublin_core.xml"), DublinCore.build_xml("dc", dc_values))

    if local_values != [] do
      File.write!(
        Path.join(item_dir, "metadata_local.xml"),
        DublinCore.build_xml("local", local_values)
      )
    end

    write_handle_file(item, item_dir)
    write_collections_file(item, item_dir)
    write_contents_and_bitstreams(item, item_dir)

    :ok
  end

  defp write_handle_file(%{handle: nil}, _dir), do: :ok

  defp write_handle_file(%{handle: handle}, dir) do
    File.write!(Path.join(dir, "handle"), handle)
  end

  defp write_collections_file(%{collection: nil}, _dir), do: :ok

  defp write_collections_file(%{collection: collection}, dir) do
    # First line is the owning collection (DSpace convention).
    File.write!(Path.join(dir, "collections"), "#{collection.handle}\n")
  end

  # Writes the `contents` file and copies/downloads each bitstream into the dir.
  defp write_contents_and_bitstreams(item, item_dir) do
    bitstreams = item.bitstreams || []

    {contents_lines, _final_taken} =
      Enum.map_reduce(bitstreams, MapSet.new(), fn bs, taken ->
        {filename, taken} = unique_filename(bs.filename, taken)
        line = contents_line(bs, filename)
        {{filename, bs, line}, MapSet.put(taken, filename)}
      end)

    contents =
      contents_lines
      |> Enum.map(fn {_filename, _bs, line} -> line end)
      |> Enum.join("\n")

    File.write!(
      Path.join(item_dir, "contents"),
      if(contents == "", do: "", else: contents <> "\n")
    )

    Enum.each(contents_lines, fn {filename, bs, _line} ->
      materialize_bitstream(bs, Path.join(item_dir, filename))
    end)
  end

  # `filename<TAB>bundle:X<TAB>description:Y<TAB>primary:true`
  defp contents_line(%Bitstream{} = bs, filename) do
    parts = [filename]

    parts =
      case bs.bundle_name do
        :ORIGINAL -> parts
        bundle -> parts ++ ["bundle:#{bundle}"]
      end

    parts =
      if bs.description && bs.description != "",
        do: parts ++ ["description:#{String.replace(bs.description, "\t", " ")}"],
        else: parts

    # ORIGINAL sequence 1 is the primary bitstream (abstract / main document).
    parts =
      if bs.bundle_name == :ORIGINAL and bs.sequence == 1,
        do: parts ++ ["primary:true"],
        else: parts

    Enum.join(parts, "\t")
  end

  # Disambiguate duplicate filenames within one item directory.
  defp unique_filename(name, taken) do
    if MapSet.member?(taken, name) do
      {ext, base} = split_ext(name)
      candidate = "#{base}_2#{ext}"

      find_free(candidate, taken, ext, base, 3)
    else
      {name, taken}
    end
  end

  defp find_free(candidate, taken, ext, base, n) do
    if MapSet.member?(taken, candidate) do
      find_free("#{base}_#{n}#{ext}", taken, ext, base, n + 1)
    else
      {candidate, taken}
    end
  end

  defp split_ext(name) do
    ext = Path.extname(name)
    base = Path.basename(name, ext)
    {ext, base}
  end

  # ── Bitstream materialization ───────────────────────────────────────────────

  defp materialize_bitstream(%Bitstream{storage_type: :local, storage_path: path}, dest) do
    src = Path.join(@local_upload_dir, path || "")

    if File.exists?(src) do
      File.cp!(src, dest)
    else
      Logger.warning("[SafExporter] local bitstream missing on disk: #{src}")
      write_placeholder(dest)
    end
  end

  defp materialize_bitstream(%Bitstream{storage_type: :s3, storage_path: key}, dest) do
    bucket = Kiroku.Settings.storage_bucket()
    config = private_ex_aws_config()

    case ExAws.S3.get_object(bucket, key) |> ExAws.request(config) do
      {:ok, %{body: body}} ->
        File.write!(dest, body)

      {:error, reason} ->
        Logger.warning("[SafExporter] S3 fetch failed #{bucket}/#{key}: #{inspect(reason)}")
        write_placeholder(dest)
    end
  end

  defp materialize_bitstream(%Bitstream{storage_type: :url, storage_url: url}, dest)
       when is_binary(url) and url != "" do
    case Req.get(req_impl(), url: url) do
      {:ok, %{status: 200, body: body}} ->
        File.write!(dest, body)

      other ->
        Logger.warning("[SafExporter] url fetch failed #{url}: #{inspect(other)}")
        write_placeholder(dest)
    end
  end

  defp materialize_bitstream(_bs, dest) do
    write_placeholder(dest)
  end

  defp write_placeholder(dest) do
    # Leave a small marker so the contents file's referenced file exists; the
    # importer treats a missing/empty file as "no bitstream".
    File.write!(dest, "")
  end

  defp req_impl, do: Application.get_env(:kiroku, :req_impl, Req)

  # Re-implements the Uploader's config to avoid making private functions public.
  defp private_ex_aws_config do
    opts = [
      access_key_id: Kiroku.Settings.storage_access_key_id() || "",
      secret_access_key: Kiroku.Settings.storage_secret_access_key() || "",
      region: Kiroku.Settings.storage_region()
    ]

    opts =
      case Kiroku.Settings.storage_endpoint() do
        nil ->
          opts

        endpoint ->
          uri = URI.parse(endpoint)
          scheme = if uri.scheme, do: uri.scheme <> "://", else: "https://"
          port = uri.port || if(uri.scheme == "https", do: 443, else: 80)

          opts
          |> Keyword.put(:host, uri.host)
          |> Keyword.put(:scheme, scheme)
          |> Keyword.put(:port, port)
      end

    ExAws.Config.new(:s3, opts)
  end

  # ── Item listing ────────────────────────────────────────────────────────────

  defp list_items(collection_id, :published) do
    import Ecto.Query
    alias Kiroku.Repository.Item

    Kiroku.Repo.all(
      from i in Item,
        where:
          i.collection_id == ^collection_id and
            i.status == :published and
            i.discoverable == true,
        order_by: [asc: i.inserted_at],
        select: i.id
    )
  end

  defp list_items(collection_id, :all) do
    import Ecto.Query
    alias Kiroku.Repository.Item

    Kiroku.Repo.all(
      from i in Item,
        where: i.collection_id == ^collection_id,
        order_by: [asc: i.inserted_at],
        select: i.id
    )
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 3, "0")
end
