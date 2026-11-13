defmodule KirokuWeb.UploadsController do
  use KirokuWeb, :controller

  alias Kiroku.{Content, Repository}
  alias Kiroku.Access.Authorization
  alias KirokuWeb.ContentDisposition

  @local_upload_dir "priv/uploads"

  @doc """
  Serves locally stored uploads (STORAGE_ADAPTER=local), replacing the
  unconditional Plug.Static mount with access control:

    * `brand/*` files (site logo) are public.
    * `items/{item_id}/{bundle}/...` files are served only when the requesting
      user may read the owning item and the bitstream is accessible
      (embargo, bundle rules, access level).
  """
  def show(conn, %{"key" => key}) do
    key = normalize_key(key)

    cond do
      not safe_key?(key) ->
        not_found(conn)

      String.starts_with?(key, "brand/") ->
        serve_public_file(conn, key)

      String.starts_with?(key, "items/") ->
        serve_bitstream(conn, key)

      true ->
        not_found(conn)
    end
  end

  # Phoenix glob routes deliver the segments as a list (already URL-decoded).
  defp normalize_key(segments) when is_list(segments), do: Enum.join(segments, "/")
  defp normalize_key(key) when is_binary(key), do: key

  # Reject traversal attempts ("..", encoded or not) before touching the FS.
  defp safe_key?(key) do
    segments = String.split(key, "/")
    ".." not in segments and not String.contains?(key, "\0") and key != ""
  end

  defp local_path(key) do
    base = Path.absname(@local_upload_dir)
    full = Path.absname(Path.join(base, key))

    if String.starts_with?(full, base <> "/"), do: full
  end

  defp serve_public_file(conn, key) do
    path = local_path(key)

    if path && File.exists?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> put_resp_header("content-disposition", "inline")
      |> send_file(200, path)
    else
      not_found(conn)
    end
  end

  defp serve_bitstream(conn, key) do
    case Content.get_bitstream_by_storage_path(key) do
      nil ->
        not_found(conn)

      bitstream ->
        item = Repository.get_item!(bitstream.item_id)
        user = conn.assigns[:current_user]

        if bitstream.storage_path == key and Authorization.can?(user, :read, item) and
             Content.accessible?(bitstream, user, item) do
          serve_local(conn, bitstream)
        else
          forbidden(conn)
        end
    end
  end

  defp serve_local(conn, bitstream) do
    path = local_path(bitstream.storage_path)

    if path && File.exists?(path) do
      # Thumbnails render inline in <img> tags and social scrapers (og:image)
      # require inline serving; everything else downloads as a file.
      disposition = if bitstream.bundle_name == :THUMBNAIL, do: "inline", else: "attachment"

      conn
      |> put_resp_content_type(bitstream.mime_type || "application/octet-stream")
      |> put_resp_header(
        "content-disposition",
        ContentDisposition.header(disposition, bitstream.filename)
      )
      |> send_file(200, path)
    else
      not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(KirokuWeb.ErrorHTML)
    |> render(:"404")
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(KirokuWeb.ErrorHTML)
    |> render(:"403")
  end
end
