defmodule KirokuWeb.BitstreamDownloadTrackingTest do
  use KirokuWeb.ConnCase, async: true

  alias Kiroku.{Analytics, Repository, Repo}
  alias Kiroku.Analytics.DownloadEvent

  @upload_dir "priv/uploads"

  defp fixture do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "C", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Repository.create_item(%{
        "title" => "Download Item",
        "handle" => "dl-#{System.unique_integer([:positive])}",
        "collection_id" => collection.id,
        "status" => "published",
        "discoverable" => true,
        "access_level" => "open"
      })

    {community, collection, item}
  end

  defp local_bitstream(item, content) do
    path = "analytics-test/#{Ecto.UUID.generate()}.pdf"
    full = Path.join(@upload_dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)

    {:ok, bs} =
      Kiroku.Content.create_bitstream(%{
        item_id: item.id,
        filename: "thesis.pdf",
        bundle_name: :ORIGINAL,
        sequence: 1,
        storage_type: :local,
        storage_path: path,
        mime_type: "application/pdf",
        access_level: :open
      })

    bs
  end

  test "serving a bitstream records a (non-bot) download event", %{conn: conn} do
    {_, _, item} = fixture()
    bs = local_bitstream(item, "%PDF-1.4 fake bytes")

    conn =
      conn
      |> put_req_header("user-agent", "Mozilla/5.0 (X11) AppleWebKit/537.36 Chrome/120")
      |> get(~p"/items/#{item.handle}/bitstreams/#{bs.id}")

    assert response(conn, 200) =~ "fake bytes"
    assert Analytics.count_downloads_for_bitstream(bs.id) == 1
    assert Repo.aggregate(DownloadEvent, :count, :id) == 1
  end

  test "crawler user-agents are served but not counted", %{conn: conn} do
    {_, _, item} = fixture()
    bs = local_bitstream(item, "%PDF-1.4 bot bytes")

    conn
    |> put_req_header("user-agent", "Googlebot/2.1 (+http://www.google.com/bot.html)")
    |> get(~p"/items/#{item.handle}/bitstreams/#{bs.id}")

    assert Analytics.count_downloads_for_bitstream(bs.id) == 0
  end
end
