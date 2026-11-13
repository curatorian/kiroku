defmodule Kiroku.ContentPurgeTest do
  # Not async: the orphan scan/execute walks the SHARED priv/uploads tree and
  # deletes files it sees as unreferenced — running that concurrently with
  # other async tests (whose sandboxed DB rows are invisible here) would
  # delete their fixture files mid-request. ExUnit guarantees non-async tests
  # never run concurrently with any other test.
  use Kiroku.DataCase, async: false

  alias Kiroku.{ContentPurge, Repository, Repo, Storage.Uploader}
  alias Kiroku.Content.Bitstream
  alias Kiroku.Repository.Item

  setup do
    {:ok, community} =
      Repository.create_community(%{
        "name" => "C",
        "handle" => "purge-#{System.unique_integer([:positive])}"
      })

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "purge-coll-#{System.unique_integer([:positive])}"
      })

    %{collection_id: collection.id}
  end

  defp create_item_with_file(collection_id, title) do
    {:ok, item} =
      Repository.create_item(%{
        "title" => title,
        "collection_id" => collection_id,
        "status" => "published"
      })

    storage_path = "items/#{item.id}/original/#{System.unique_integer([:positive])}.pdf"
    full_path = Path.join(Uploader.local_upload_dir(), storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.4 purge-test")

    {:ok, bitstream} =
      %Bitstream{}
      |> Bitstream.changeset(%{
        "item_id" => item.id,
        "filename" => "file.pdf",
        "bundle_name" => "ORIGINAL",
        "mime_type" => "application/pdf",
        "storage_type" => "local",
        "storage_path" => storage_path
      })
      |> Repo.insert()

    on_exit(fn -> File.rm_rf(Path.dirname(full_path)) end)

    {item, bitstream}
  end

  describe "dry run" do
    test "reports matched items without deleting anything", %{collection_id: cid} do
      {item, bitstream} = create_item_with_file(cid, "arx_t_probe")

      summary = ContentPurge.run(["--title-prefix", "arx_"])

      assert [%Item{}] = summary.items
      assert item.id in Enum.map(summary.items, & &1.id)
      assert bitstream.id in Enum.map(summary.bitstreams, & &1.id)

      assert Repo.reload!(item)
      assert File.exists?(Path.join(Uploader.local_upload_dir(), bitstream.storage_path))
    end

    test "raises when no matching criteria are given" do
      assert_raise ArgumentError, ~r/refusing to match everything/, fn ->
        ContentPurge.run(["--title-prefix", ""])
      end
    end
  end

  describe "execute" do
    test "deletes matched items, their bitstream rows and the storage objects", %{
      collection_id: cid
    } do
      {item, bitstream} = create_item_with_file(cid, "arx_t_dollar")
      full_path = Path.join(Uploader.local_upload_dir(), bitstream.storage_path)
      item_id = item.id

      summary = ContentPurge.run(["--title-prefix", "arx_", "--execute"])
      assert [%{id: ^item_id}] = summary.items

      refute Repo.get(Item, item.id)
      refute Repo.get(Bitstream, bitstream.id)
      refute File.exists?(full_path)
    end

    test "matches explicit --item-ids with an empty title prefix", %{collection_id: cid} do
      {item, bitstream} = create_item_with_file(cid, "Completely Normal Title")

      ContentPurge.run(["--item-ids", item.id, "--title-prefix", "", "--execute"])

      refute Repo.get(Item, item.id)
      refute Repo.get(Bitstream, bitstream.id)
    end

    test "leaves non-matching items and their files alone", %{collection_id: cid} do
      {_other, _other_bs} = create_item_with_file(cid, "arx_t_semi")
      {legit, legit_bitstream} = create_item_with_file(cid, "A Real Student Thesis")

      since = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)

      opts = ["--title-prefix", "arx_", "--since", NaiveDateTime.to_iso8601(since), "--execute"]

      summary = ContentPurge.run(opts)

      assert Repo.reload!(legit)
      assert Repo.reload!(legit_bitstream)
      assert File.exists?(Path.join(Uploader.local_upload_dir(), legit_bitstream.storage_path))
      assert [{%Bitstream{}, "A Real Student Thesis"}] = summary.outside_bitstreams
    end
  end

  describe "delete_object/1" do
    test "skips :url bitstreams" do
      assert {:skipped, :url_redirect} =
               ContentPurge.delete_object(%Bitstream{
                 storage_type: :url,
                 storage_url: "https://example.com/f.pdf"
               })
    end

    test "skips missing local files" do
      assert {:skipped, :not_found} =
               ContentPurge.delete_object(%Bitstream{
                 storage_type: :local,
                 storage_path: "items/does-not-exist/#{System.unique_integer([:positive])}.pdf"
               })
    end
  end

  describe "orphan scan (local adapter)" do
    test "reports storage objects that have no DB row" do
      stray = "items/orphan-#{System.unique_integer([:positive])}.pdf"
      stray_path = Path.join(Uploader.local_upload_dir(), stray)
      File.mkdir_p!(Path.dirname(stray_path))
      File.write!(stray_path, "orphaned")

      on_exit(fn -> File.rm(stray_path) end)

      summary = ContentPurge.run(["--title-prefix", "arx_", "--orphans"])

      assert stray in summary.orphans
      # List-only by default.
      assert File.exists?(stray_path)
    end

    test "--orphan-execute deletes the reported objects" do
      stray = "items/orphan-#{System.unique_integer([:positive])}.pdf"
      stray_path = Path.join(Uploader.local_upload_dir(), stray)
      File.mkdir_p!(Path.dirname(stray_path))
      File.write!(stray_path, "orphaned")

      on_exit(fn -> File.rm(stray_path) end)

      summary = ContentPurge.run(["--title-prefix", "arx_", "--orphans", "--orphan-execute"])

      assert stray in summary.orphans
      refute File.exists?(stray_path)
    end
  end
end
