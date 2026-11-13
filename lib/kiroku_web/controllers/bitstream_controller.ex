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
  def show(conn, %{"item_id" => item_id, "id" => bitstream_id}) do
    item = Repository.get_item!(item_id)
    bitstream = Content.get_bitstream!(bitstream_id)

    user = conn.assigns[:current_user]

    if bitstream.item_id == item.id and Authorization.can?(user, :read, item) and
         Content.accessible?(bitstream, user, item) do
      record_download(conn, bitstream, item)
      serve_bitstream(conn, bitstream)
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

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(KirokuWeb.ErrorHTML)
    |> render(:"404")
  end
end
