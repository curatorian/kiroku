defmodule Kiroku.AnalyticsTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.{Analytics, Repo}
  alias Kiroku.Analytics.{ViewEvent, DownloadEvent}

  defp item_fixture do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Kiroku.Repository.create_community(%{"name" => "C", "handle" => handle})

    {:ok, collection} =
      Kiroku.Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    {:ok, item} =
      Kiroku.Repository.create_item(%{
        "title" => "Analytics Item",
        "collection_id" => collection.id,
        "status" => "published"
      })

    item
  end

  defp bitstream_fixture(item) do
    {:ok, bs} =
      Kiroku.Content.create_bitstream(%{
        item_id: item.id,
        filename: "test.pdf",
        bundle_name: :ORIGINAL,
        sequence: 1,
        storage_type: :local,
        storage_path: "does-not-matter.bin"
      })

    bs
  end

  describe "bot?/1" do
    test "detects common crawlers" do
      assert Analytics.bot?(
               "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
             )

      assert Analytics.bot?("Mozilla/5.0 (compatible; bingbot/2.0)")
      assert Analytics.bot?("python-requests/2.31.0")
      assert Analytics.bot?("curl/8.0")
    end

    test "passes real browsers through" do
      refute Analytics.bot?("Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/120 Safari/537.36")
      refute Analytics.bot?(nil)
    end
  end

  describe "record_view/3" do
    test "records a human view" do
      item = item_fixture()
      :ok = Analytics.record_view(item.id, nil, user_agent: "Mozilla/5.0 Firefox")

      assert Analytics.count_views(item.id) == 1
    end

    test "skips crawler user-agents" do
      item = item_fixture()
      :ignored_bot = Analytics.record_view(item.id, nil, user_agent: "Googlebot/2.1")

      assert Analytics.count_views(item.id) == 0
      assert Repo.aggregate(ViewEvent, :count, :id) == 0
    end
  end

  describe "record_download/4" do
    test "records a human download and counts it" do
      item = item_fixture()
      bs = bitstream_fixture(item)

      :ok =
        Analytics.record_download(bs.id, item.id, nil, user_agent: "Mozilla/5.0 Safari")

      assert Analytics.count_downloads_for_item(item.id) == 1
      assert Analytics.count_downloads_for_bitstream(bs.id) == 1
    end

    test "skips crawler user-agents" do
      item = item_fixture()
      bs = bitstream_fixture(item)

      :ignored_bot =
        Analytics.record_download(bs.id, item.id, nil, user_agent: "curl/8.0")

      assert Repo.aggregate(DownloadEvent, :count, :id) == 0
    end

    test "aggregates counts across bitstreams for an item" do
      item = item_fixture()
      bs1 = bitstream_fixture(item)

      {:ok, bs2} =
        Kiroku.Content.create_bitstream(%{
          item_id: item.id,
          filename: "second.pdf",
          bundle_name: :ORIGINAL,
          sequence: 2,
          storage_type: :local,
          storage_path: "second.bin"
        })

      Analytics.record_download(bs1.id, item.id, nil, user_agent: "Mozilla")
      Analytics.record_download(bs1.id, item.id, nil, user_agent: "Mozilla")
      Analytics.record_download(bs2.id, item.id, nil, user_agent: "Mozilla")

      assert Analytics.count_downloads_for_item(item.id) == 3
    end
  end

  describe "top_*_with_items/1" do
    test "returns published items joined with counts" do
      item = item_fixture()
      bs = bitstream_fixture(item)

      for _ <- 1..3, do: Analytics.record_view(item.id, nil, user_agent: "Mozilla")
      for _ <- 1..2, do: Analytics.record_download(bs.id, item.id, nil, user_agent: "Mozilla")

      viewed = Analytics.top_viewed_with_items(5)
      downloaded = Analytics.top_downloaded_with_items(5)

      item_id = item.id
      assert [%{id: ^item_id, views: 3}] = viewed
      assert [%{id: ^item_id, downloads: 2}] = downloaded
    end
  end

  describe "ip_hash/1" do
    test "produces a stable hex digest" do
      assert Analytics.ip_hash({127, 0, 0, 1}) == Analytics.ip_hash("127.0.0.1")
      assert String.length(Analytics.ip_hash("10.0.0.1")) == 16
    end
  end
end
