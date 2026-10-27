defmodule KirokuWeb.Api.V1.BitstreamController do
  @moduledoc """
  REST API v1 — bitstream and thumbnail bytes.

    GET /api/v1/items/:item_id/bitstreams/:bitstream_id — download a bitstream
      (supports `Range` requests → 206 + Content-Range; item id or handle)
    GET /api/v1/items/:item_id/thumbnails/:size — cover image bytes
      (`size` reserved for future variants; the stored THUMBNAIL is served)

  Access is enforced per file via `Content.accessible?/3` — denied files get
  a 403 in the uniform error envelope, never a silent omission.
  """

  use KirokuWeb, :controller

  import KirokuWeb.Api.ErrorHelpers

  alias Kiroku.{Analytics, Content, Repository}
  alias Kiroku.Content.Bitstream
  alias Kiroku.Storage.Uploader

  def show(conn, %{"item_id" => item_id, "bitstream_id" => bitstream_id}) do
    user = conn.assigns[:current_user]
    item = Repository.get_item!(item_id)
    bitstream = Content.get_bitstream!(bitstream_id)

    unauthorized_item? =
      not (item.status == :published and item.discoverable) and not staff?(user)

    cond do
      unauthorized_item? ->
        not_found(conn, "Item not found")

      bitstream.item_id != item.id ->
        not_found(conn, "Bitstream not found")

      Content.accessible?(bitstream, user, item) ->
        record_download(conn, bitstream, item)
        serve_bytes(conn, bitstream)

      true ->
        forbidden(conn, "You do not have access to this file")
    end
  rescue
    Ecto.NoResultsError ->
      not_found(conn, "Bitstream not found")
  end

  def thumbnail(conn, %{"item_id" => item_id, "size" => _size}) do
    item = Repository.get_item!(item_id)

    case Content.get_thumbnail_for_item(item.id) do
      nil -> not_found(conn, "Thumbnail not found")
      bitstream -> serve_bytes(conn, bitstream)
    end
  rescue
    Ecto.NoResultsError ->
      not_found(conn, "Item not found")
  end

  # ── Byte delivery ─────────────────────────────────────────────────────────

  defp serve_bytes(conn, %Bitstream{storage_type: :local} = bitstream) do
    path = Path.join("priv/uploads", bitstream.storage_path)

    case File.stat(path) do
      {:ok, %{size: size}} -> serve_local(conn, bitstream, path, size)
      _ -> not_found(conn, "File data is missing")
    end
  end

  defp serve_bytes(conn, %Bitstream{storage_type: :s3} = bitstream) do
    if bitstream.storage_bucket && bitstream.storage_path do
      serve_s3(conn, bitstream)
    else
      not_found(conn, "File data is missing")
    end
  end

  defp serve_bytes(conn, %Bitstream{storage_type: :url, storage_url: url}) when is_binary(url) do
    redirect(conn, external: url)
  end

  defp serve_bytes(conn, _bitstream), do: not_found(conn, "File data is missing")

  # ── Local storage ─────────────────────────────────────────────────────────

  defp serve_local(conn, bitstream, path, size) do
    case range_bounds(conn, size) do
      {:ok, {offset, length}} ->
        conn
        |> base_headers(bitstream, size)
        |> range_headers(offset, offset + length - 1, size)
        |> send_file(206, path, offset, length)

      {:error, :range_not_satisfiable} ->
        conn
        |> base_headers(bitstream, size)
        |> put_resp_header("content-range", "bytes */#{size}")
        |> error(416, "range_not_satisfiable", "Requested range not satisfiable")

      # No Range header — serve the full file (200).
      nil ->
        conn
        |> base_headers(bitstream, size)
        |> send_file(200, path)
    end
  end

  # ── S3 storage ─────────────────────────────────────────────────────────────

  defp serve_s3(conn, bitstream) do
    case Uploader.s3_object_size(bitstream.storage_bucket, bitstream.storage_path) do
      {:ok, size} ->
        case range_bounds(conn, size) do
          {:ok, {offset, length}} ->
            with {:ok, bytes} <-
                   Uploader.s3_get_range(
                     bitstream.storage_bucket,
                     bitstream.storage_path,
                     "bytes=#{offset}-#{offset + length - 1}"
                   ) do
              conn
              |> base_headers(bitstream, size)
              |> range_headers(offset, offset + length - 1, size)
              |> send_resp(206, bytes)
            else
              _ -> not_found(conn, "File data is missing")
            end

          {:error, :range_not_satisfiable} ->
            conn
            |> base_headers(bitstream, size)
            |> put_resp_header("content-range", "bytes */#{size}")
            |> error(416, "range_not_satisfiable", "Requested range not satisfiable")

          nil ->
            serve_full_s3(conn, bitstream)
        end

      _ ->
        not_found(conn, "File data is missing")
    end
  end

  defp serve_full_s3(conn, bitstream) do
    case Uploader.read_bytes(bitstream) do
      {:ok, bytes} ->
        conn
        |> base_headers(bitstream, byte_size(bytes))
        |> send_resp(200, bytes)

      _ ->
        redirect(conn,
          external: Uploader.presign_url(bitstream.storage_bucket, bitstream.storage_path)
        )
    end
  end

  # ── Range header parsing ──────────────────────────────────────────────────

  # Returns {:ok, {offset, length}} clamped to `total`, nil when no Range
  # header is present, or {:error, :range_not_satisfiable}.
  defp range_bounds(conn, total) do
    case parse_range(get_req_header(conn, "range") |> List.first()) do
      {:ok, {:suffix, n}} when n > 0 ->
        offset = max(0, total - min(n, total))
        {:ok, {offset, total - offset}}

      {:ok, {start, nil}} when start < total ->
        {:ok, {start, total - start}}

      {:ok, {start, stop}} when start < total and stop >= start ->
        stop = min(stop, total - 1)
        {:ok, {start, stop - start + 1}}

      {:ok, _} ->
        {:error, :range_not_satisfiable}

      {:error, :invalid_range} ->
        {:error, :range_not_satisfiable}

      nil ->
        nil
    end
  end

  # Handles "bytes=a-b", "bytes=a-", "bytes=-n". Single ranges only, per RFC 9110.
  defp parse_range(nil), do: nil

  defp parse_range(header) do
    case Regex.run(~r/^bytes=(\d*)-(\d*)$/, String.trim(to_string(header))) do
      [_, "", suffix] when suffix != "" -> {:ok, {:suffix, String.to_integer(suffix)}}
      [_, start, ""] -> {:ok, {String.to_integer(start), nil}}
      [_, start, stop] -> {:ok, {String.to_integer(start), String.to_integer(stop)}}
      _ -> {:error, :invalid_range}
    end
  end

  # ── Response headers ──────────────────────────────────────────────────────

  defp base_headers(conn, %Bitstream{} = bitstream, total) do
    conn
    |> put_resp_content_type(bitstream.mime_type || "application/octet-stream", nil)
    |> put_resp_header("accept-ranges", "bytes")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{bitstream.filename}"))
    |> put_resp_header("etag", etag_for(bitstream))
    |> put_resp_header("content-length", Integer.to_string(total))
  end

  defp range_headers(conn, start, stop, total) do
    put_resp_header(conn, "content-range", "bytes #{start}-#{stop}/#{total}")
  end

  defp etag_for(%Bitstream{checksum: checksum}) when is_binary(checksum) and checksum != "",
    do: ~s("md5-#{checksum}")

  defp etag_for(%Bitstream{updated_at: updated_at}) when not is_nil(updated_at) do
    unix =
      updated_at
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix()

    ~s(W/"u-#{unix}")
  end

  defp etag_for(_), do: ~s(W/"unknown")

  # ── Shared helpers ────────────────────────────────────────────────────────

  defp staff?(%{user_type: type}), do: type in [:reviewer, :admin, :superadmin]
  defp staff?(_), do: false

  defp record_download(conn, bitstream, item) do
    meta = [
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      ip_hash: Analytics.ip_hash(conn.remote_ip),
      referer: get_req_header(conn, "referer") |> List.first()
    ]

    Analytics.record_download(bitstream.id, item.id, conn.assigns[:current_user], meta)
  end
end
