defmodule KirokuWeb.BitstreamController do
  use KirokuWeb, :controller

  alias Kiroku.{Analytics, Content, Repository}
  alias Kiroku.Access.Authorization
  alias Kiroku.Content.Bitstream
  alias Kiroku.Storage.Uploader
  alias KirokuWeb.ContentDisposition

  require Logger

  @doc """
  Serves a bitstream file. Enforces access control based on the item's
  visibility, the bitstream's bundle, embargo status, and the requesting
  user's role. Records a download event (non-bot) for analytics.
  """
  def show(conn, %{"item_id" => item_id, "id" => bitstream_id} = params) do
    item = Repository.get_item!(item_id)
    bitstream = Content.get_bitstream!(bitstream_id)

    user = conn.assigns[:current_user]

    if bitstream.item_id == item.id and Authorization.can?(user, :read, item) and
         Content.accessible?(bitstream, user, item) do
      record_download(conn, bitstream, item)

      if params["reader"] do
        serve_reader_bytes(conn, bitstream)
      else
        serve_bitstream(conn, bitstream)
      end
    else
      conn
      |> put_status(:forbidden)
      |> put_view(KirokuWeb.ErrorHTML)
      |> render(:"403")
    end
  end

  defp record_download(conn, bitstream, item) do
    meta = [
      user_agent: user_agent(conn),
      ip_hash: Analytics.ip_hash(conn.remote_ip),
      referer: get_req_header(conn, "referer") |> List.first()
    ]

    Analytics.record_download(bitstream.id, item.id, conn.assigns[:current_user], meta)
  end

  defp user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      _ -> nil
    end
  end

  defp serve_bitstream(conn, %Bitstream{storage_type: :s3} = bitstream) do
    url =
      Uploader.presign_url(
        bitstream.storage_bucket,
        bitstream.storage_path,
        expires_in: 3600
      )

    redirect(conn, external: url)
  end

  defp serve_bitstream(conn, %Bitstream{storage_type: :local} = bitstream) do
    path = Path.join("priv/uploads", bitstream.storage_path)

    # A DB row can outlive its file (restored DB, pruned volume, cross-env
    # data) — answer 404 instead of crashing Bandit in send_file.
    if File.exists?(path) do
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
      Logger.error("Local file missing bitstream=#{bitstream.id} path=#{path}")
      not_found(conn)
    end
  end

  defp serve_bitstream(conn, %Bitstream{storage_type: :url, storage_url: url}) do
    redirect(conn, external: url)
  end

  # ?reader=1 — the in-page modal fetches the bytes through the app. Needed
  # for :s3 and :url bitstreams: their direct serving redirects to a
  # cross-origin host, which a same-origin fetch cannot follow (CORS). The
  # relay serves the same bytes same-origin so they can be embedded. Only the
  # reader param triggers it — direct visits keep the old behavior.
  defp serve_reader_bytes(conn, bitstream) do
    if pdf_bitstream?(bitstream) do
      case reader_bytes(bitstream) do
        {:ok, body, _mime} ->
          conn
          |> put_resp_content_type(reader_mime(bitstream))
          |> put_resp_header(
            "content-disposition",
            ContentDisposition.header("inline", bitstream.filename)
          )
          |> send_resp(200, body)

        {:error, reason} ->
          Logger.error("Reader fetch failed bitstream=#{bitstream.id}: #{inspect(reason)}")
          not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  # Reader is strictly for PDFs, same rule as the sidebar button.
  defp pdf_bitstream?(%Bitstream{mime_type: "application/pdf"}), do: true

  defp pdf_bitstream?(%Bitstream{filename: filename}) when is_binary(filename),
    do: String.ends_with?(String.downcase(filename), ".pdf")

  defp pdf_bitstream?(_), do: false

  # The reader only serves reader-eligible (PDF) files, so the type is always
  # application/pdf. NOTE: don't use MIME.type/1 here — this app overrides
  # config :mime, :types, which replaces the whole default type database.
  defp reader_mime(_bitstream), do: "application/pdf"

  defp reader_bytes(%Bitstream{storage_type: :url, storage_url: url} = bitstream)
       when is_binary(url) do
    # decode_body: false — PDF bytes must not run through any content decoder.
    case Req.get(url, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body, bitstream.mime_type}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:upstream_status, status}}

      {:error, reason} ->
        {:error, {:url_fetch_failed, reason}}
    end
  end

  defp reader_bytes(bitstream) do
    with {:ok, body} <- Uploader.read_bytes(bitstream) do
      {:ok, body, bitstream.mime_type}
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(KirokuWeb.ErrorHTML)
    |> render(:"404")
  end
end
