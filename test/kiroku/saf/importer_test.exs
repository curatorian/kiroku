defmodule Kiroku.Saf.ImporterTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.{Content, Repository, Saf.Importer}

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_collection do
    n = System.unique_integer([:positive])

    {:ok, community} =
      Repository.create_community(%{name: "Comm #{n}", handle: "comm-#{n}"})

    {:ok, collection} =
      Repository.create_collection(%{
        name: "Coll #{n}",
        community_id: community.id,
        handle: "coll-#{n}"
      })

    collection
  end

  defp build_saf_dir(collection, opts) do
    dir = Path.join(System.tmp_dir!(), "kiroku_saf_test_#{System.unique_integer([:positive])}")
    item_dir = Path.join(dir, "item_000")
    File.mkdir_p!(item_dir)

    File.write!(
      Path.join(item_dir, "dublin_core.xml"),
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <dublin_core>
        <dcvalue element="title" qualifier="none">Imported Thesis</dcvalue>
        <dcvalue element="description" qualifier="abstract">An abstract.</dcvalue>
        <dcvalue element="contributor" qualifier="author">Budi Santoso</dcvalue>
        <dcvalue element="subject" qualifier="none">hukum</dcvalue>
      </dublin_core>
      """
    )

    File.write!(Path.join(item_dir, "handle"), "test-saf/#{System.unique_integer([:positive])}")
    File.write!(Path.join(item_dir, "collections"), "#{collection.handle}\n")

    body = Keyword.get(opts, :file_body, "PDF-1.4 test content")
    File.write!(Path.join(item_dir, "document.pdf"), body)

    File.write!(Path.join(item_dir, "contents"), "document.pdf\tbundle:ORIGINAL\tprimary:true\n")

    dir
  end

  # ── Tests ──────────────────────────────────────────────────────────────────

  describe "import_archive/2 with the local adapter" do
    test "creates a bitstream whose storage_type matches the live adapter" do
      collection = create_collection()
      dir = build_saf_dir(collection, file_body: "hello-bytes")

      # Sanity: tests run against the local adapter by default.
      assert Kiroku.Settings.storage_adapter() == :local

      {:ok, stats} = Importer.import_archive(dir)
      assert stats.processed == 1
      assert stats.inserted == 1
      assert stats.failed == 0

      handle = Path.join([dir, "item_000", "handle"]) |> File.read!() |> String.trim()
      item = Repository.get_item_by_handle!(handle)
      [bitstream | _] = Content.list_bitstreams_for_item(item.id)

      # The fix: the record must describe where the bytes actually went.
      assert bitstream.storage_type == :local
      assert bitstream.storage_path != nil
      refute bitstream.storage_bucket

      # …and the bytes are actually on local disk at that path.
      on_disk = Path.join("priv/uploads", bitstream.storage_path)
      assert File.exists?(on_disk)
      assert File.read!(on_disk) == "hello-bytes"

      File.rm(on_disk)
    end

    test "is idempotent on handle — re-import updates rather than duplicating" do
      collection = create_collection()
      dir = build_saf_dir(collection, file_body: "v1")

      {:ok, first} = Importer.import_archive(dir)
      assert first.inserted == 1

      {:ok, second} = Importer.import_archive(dir)
      assert second.processed == 1
      assert second.updated == 1
      assert second.inserted == 0

      # One item with that handle, not two.
      handle = File.read!(Path.join([dir, "item_000", "handle"])) |> String.trim()
      assert Repository.get_item_by_handle(handle) != nil

      all_handles =
        Repository.list_items(%{}) |> Enum.map(& &1.handle) |> Enum.filter(&(&1 == handle))

      assert length(all_handles) == 1
    end

    test "dry_run validates and writes nothing" do
      collection = create_collection()
      dir = build_saf_dir(collection, file_body: "dry")

      {:ok, stats} = Importer.import_archive(dir, dry_run: true)
      assert stats.processed == 1
      assert stats.inserted == 0

      # No item, no bitstream on disk.
      assert Repository.list_items(%{}) == []
      refute File.exists?(Path.join([dir, "item_000", "ignored.pdf"]))
    end

    test "reports a clear error when no target collection can be resolved" do
      dir = build_saf_dir(create_collection(), file_body: "x")
      # Remove the per-item collections file and pass no override.
      File.rm!(Path.join([dir, "item_000", "collections"]))

      {:ok, stats} = Importer.import_archive(dir)
      assert stats.failed == 1

      [error] = stats.errors
      assert error.reason == :no_collection_file
    end
  end
end
