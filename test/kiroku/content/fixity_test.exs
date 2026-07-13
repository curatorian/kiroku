defmodule Kiroku.Content.FixityTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.{Content, Repo}
  alias Kiroku.Content.BitstreamFixityCheck
  alias Kiroku.Storage.Uploader

  # Fixtures write real files into the local upload dir; clean them up so async
  # tests don't accumulate bytes.
  @upload_dir "priv/uploads"

  defp collection_fixture do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Kiroku.Repository.create_community(%{"name" => "C", "handle" => handle})

    {:ok, collection} =
      Kiroku.Repository.create_collection(%{
        "name" => "Coll",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp item_fixture do
    {:ok, item} =
      Kiroku.Repository.create_item(%{
        "title" => "Fixity Item",
        "collection_id" => collection_fixture().id,
        "status" => "published"
      })

    item
  end

  # Writes `content` to a unique local path and returns the path + checksum.
  defp write_local_file(content) do
    path = "fixity-test/#{Ecto.UUID.generate()}.bin"
    full = Path.join(@upload_dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
    {path, Uploader.checksum(content)}
  end

  defp create_local_bitstream(opts) do
    content = Keyword.get(opts, :content, "default-bytes")
    {path, checksum} = write_local_file(content)

    {:ok, bs} =
      Content.create_bitstream(%{
        item_id: item_fixture().id,
        filename: Keyword.get(opts, :filename, "test.bin"),
        bundle_name: :ORIGINAL,
        sequence: 1,
        storage_type: :local,
        storage_path: path,
        checksum: Keyword.get(opts, :checksum, checksum),
        checksum_algorithm: "MD5"
      })

    bs
  end

  describe "Uploader.upload/3" do
    test "computes and returns checksum + size" do
      key = "fixity-test/upload-#{Ecto.UUID.generate()}.bin"

      {:ok, %{path: ^key, checksum: checksum, size: size}} =
        Uploader.upload(key, "hello world", mime_type: "text/plain")

      assert checksum == Uploader.checksum("hello world")
      assert size == 11
    end
  end

  describe "check_bitstream/1" do
    test "verifies a matching checksum as ok" do
      bs = create_local_bitstream(content: "matching bytes")

      assert {:ok, true} = Content.check_bitstream(bs)

      reloaded = Content.get_bitstream!(bs.id)
      assert reloaded.last_fixity_ok == true
      assert reloaded.last_fixity_at

      [check] = Repo.all(BitstreamFixityCheck)
      assert check.ok == true
      assert check.actual_checksum == bs.checksum
    end

    test "flags a checksum mismatch" do
      bs = create_local_bitstream(content: "real bytes", checksum: "deadbeef")

      assert {:ok, false} = Content.check_bitstream(bs)

      reloaded = Content.get_bitstream!(bs.id)
      assert reloaded.last_fixity_ok == false

      [check] = Repo.all(BitstreamFixityCheck)
      assert check.ok == false
      assert check.expected_checksum == "deadbeef"
      assert check.actual_checksum == Uploader.checksum("real bytes")
    end

    test "establishes a baseline for legacy bitstreams with no checksum" do
      {path, expected} = write_local_file("legacy bytes")

      {:ok, bs} =
        Content.create_bitstream(%{
          item_id: item_fixture().id,
          filename: "legacy.bin",
          bundle_name: :ORIGINAL,
          sequence: 1,
          storage_type: :local,
          storage_path: path,
          checksum: nil
        })

      assert {:ok, true} = Content.check_bitstream(bs)

      reloaded = Content.get_bitstream!(bs.id)
      assert reloaded.checksum == expected
      assert reloaded.last_fixity_ok == true
    end

    test "records an error when the stored file is missing" do
      {:ok, bs} =
        Content.create_bitstream(%{
          item_id: item_fixture().id,
          filename: "ghost.bin",
          bundle_name: :ORIGINAL,
          sequence: 1,
          storage_type: :local,
          storage_path: "fixity-test/does-not-exist.bin",
          checksum: "anything"
        })

      assert {:error, {:local_read_failed, :enoent}} = Content.check_bitstream(bs)

      reloaded = Content.get_bitstream!(bs.id)
      assert reloaded.last_fixity_ok == nil
      assert reloaded.last_fixity_at

      [check] = Repo.all(BitstreamFixityCheck)
      assert check.ok == nil
      assert check.error =~ "read_failed"
    end

    test "skips externally-hosted :url bitstreams" do
      {:ok, bs} =
        Content.create_bitstream(%{
          item_id: item_fixture().id,
          filename: "external.pdf",
          bundle_name: :ORIGINAL,
          sequence: 1,
          storage_type: :url,
          storage_url: "https://example.com/file.pdf",
          checksum: "abc"
        })

      assert {:error, :url_not_verifiable} = Content.check_bitstream(bs)
    end
  end

  describe "run_fixity_batch/1" do
    test "checks due bitstreams and returns counts" do
      _ok = create_local_bitstream(content: "aaa")
      _ok2 = create_local_bitstream(content: "bbb")
      _bad = create_local_bitstream(content: "ccc", checksum: "wrong")

      summary = Content.run_fixity_batch(limit: 10)

      assert summary.checked == 3
      assert summary.ok == 2
      assert summary.failed == 1
    end
  end

  describe "fixity_summary/0" do
    test "counts verified, failed, unchecked, and unverifiable" do
      ok_bs = create_local_bitstream(content: "ok")
      Content.check_bitstream(ok_bs)

      summary = Content.fixity_summary()

      assert summary.ok >= 1
      assert summary.unchecked >= 0
      assert is_integer(summary.unverifiable)
    end
  end
end
