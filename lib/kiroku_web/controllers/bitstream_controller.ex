defmodule KirokuWeb.BitstreamController do
  use KirokuWeb, :controller

  alias Kiroku.{Content, Repository}
  alias Kiroku.Content.Bitstream
  alias Kiroku.Storage.Uploader

  @doc """
  Serves a bitstream file. Enforces access control based on the bitstream's
  bundle, item embargo status, and the requesting user's role.
  """
  def show(conn, %{"item_id" => item_id, "id" => bitstream_id}) do
    item = Repository.get_item!(item_id)
    bitstream = Content.get_bitstream!(bitstream_id)

    user = conn.assigns[:current_user]

    if bitstream.item_id == item.id and Content.accessible?(bitstream, user, item) do
      serve_bitstream(conn, bitstream)
    else
      conn
      |> put_status(:forbidden)
      |> put_view(KirokuWeb.ErrorHTML)
      |> render(:"403")
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

    conn
    |> put_resp_content_type(bitstream.mime_type || "application/octet-stream")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{bitstream.filename}")
    )
    |> send_file(200, path)
  end

  defp serve_bitstream(conn, %Bitstream{storage_type: :url, storage_url: url}) do
    redirect(conn, external: url)
  end
end
