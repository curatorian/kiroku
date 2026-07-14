defmodule Kiroku.ThumbnailGenerationTest do
  use Kiroku.DataCase, async: true

  # Exercises the thumbnail generation pipeline end-to-end: PDF bytes →
  # pdftoppm → JPEG → stored as a THUMBNAIL bitstream. DB-only paths
  # (skip-if-exists, get_thumbnail_for_item) are always testable; the
  # actual pdftoppm call requires poppler-utils on PATH.

  alias Kiroku.{Content, Repository}
  alias Kiroku.Workers.ThumbnailWorker

  defp create_collection do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Collection",
        "community_id" => community.id,
        "handle" => "coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp create_item(attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(%{"title" => "Test", "collection_id" => create_collection().id}, attrs)
      )

    item
  end

  defp create_original_pdf_bitstream(item, opts \\ []) do
    storage_path = Keyword.get(opts, :storage_path, "items/#{item.id}/original/test.pdf")

    # Write real PDF bytes to local storage so pdftoppm can read them.
    unless opts[:skip_write] do
      abs = Path.join("priv/uploads", storage_path)
      File.mkdir_p!(Path.dirname(abs))
      File.write!(abs, real_pdf_bytes())
    end

    {:ok, bs} =
      Content.create_bitstream(%{
        "item_id" => item.id,
        "filename" => "test.pdf",
        "bundle_name" => "ORIGINAL",
        "sequence" => 1,
        "storage_type" => "local",
        "storage_path" => storage_path,
        "mime_type" => "application/pdf",
        "access_level" => "open"
      })

    bs
  end

  defp assert_pdftoppm! do
    assert System.find_executable("pdftoppm"),
           "pdftoppm not found — install poppler-utils to run thumbnail tests"
  end

  # ── Skip paths ──────────────────────────────────────────────────────────────

  describe "generate_thumbnail/1 — skip paths" do
    test "returns {:ok, :skipped} for a non-PDF bitstream" do
      item = create_item()

      {:ok, bs} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "image.png",
          "bundle_name" => "ORIGINAL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/original/image.png",
          "mime_type" => "image/png",
          "access_level" => "open"
        })

      assert {:ok, :skipped} = Content.generate_thumbnail(bs)
    end

    test "returns {:ok, :skipped} for :url storage" do
      item = create_item()

      {:ok, bs} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "remote.pdf",
          "bundle_name" => "ORIGINAL",
          "sequence" => 1,
          "storage_type" => "url",
          "storage_url" => "https://example.com/doc.pdf",
          "mime_type" => "application/pdf",
          "access_level" => "open"
        })

      assert {:ok, :skipped} = Content.generate_thumbnail(bs)
    end

    test "returns {:ok, :skipped} when item already has a THUMBNAIL bitstream" do
      item = create_item()

      # Create an existing THUMBNAIL (simulating a user-uploaded cover).
      {:ok, _existing} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "cover.jpg",
          "bundle_name" => "THUMBNAIL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/thumb/cover.jpg",
          "mime_type" => "image/jpeg",
          "access_level" => "open"
        })

      bs = create_original_pdf_bitstream(item)

      assert {:ok, :skipped} = Content.generate_thumbnail(bs)
      # Verify no DUPLICATE thumbnail was created.
      thumbnails =
        Content.list_bitstreams_for_item(item.id) |> Enum.filter(&(&1.bundle_name == :THUMBNAIL))

      assert length(thumbnails) == 1
    end
  end

  # ── Real generation ─────────────────────────────────────────────────────────

  describe "generate_thumbnail/1 — real pdftoppm generation" do
    @tag :pdftoppm
    test "generates a JPEG thumbnail from a PDF and stores it as THUMBNAIL" do
      assert_pdftoppm!()

      item = create_item()
      # create_bitstream auto-enqueues ThumbnailWorker (inline in tests),
      # so the thumbnail is generated during the create call itself.
      _bs = create_original_pdf_bitstream(item)

      thumb = Content.get_thumbnail_for_item(item.id)
      assert thumb != nil
      assert thumb.bundle_name == :THUMBNAIL
      assert thumb.mime_type == "image/jpeg"
      assert thumb.access_level == :open
      assert thumb.item_id == item.id
      assert thumb.file_size > 0
      assert thumb.checksum != nil

      # The JPEG bytes are actually on disk.
      thumb_path = Path.join("priv/uploads", thumb.storage_path)
      assert File.exists?(thumb_path)

      # The bytes start with the JPEG magic number (FF D8 FF).
      {:ok, bytes} = File.read(thumb_path)
      assert binary_part(bytes, 0, 3) == <<255, 216, 255>>
    end

    @tag :pdftoppm
    test "does not overwrite an existing user-uploaded cover" do
      assert_pdftoppm!()

      item = create_item()

      # Pre-create a user-uploaded THUMBNAIL (simulating a manual cover).
      {:ok, user_cover} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "my-cover.jpg",
          "bundle_name" => "THUMBNAIL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/thumb/my-cover.jpg",
          "mime_type" => "image/jpeg",
          "access_level" => "open"
        })

      # Now create an ORIGINAL PDF — the auto-enqueue fires, but the worker
      # should skip because a THUMBNAIL already exists.
      _bs = create_original_pdf_bitstream(item)

      # Re-fetch the ORIGINAL bitstream to call generate_thumbnail explicitly.
      [original | _] =
        Content.list_bitstreams_for_item(item.id)
        |> Enum.filter(&(&1.bundle_name == :ORIGINAL))

      assert {:ok, :skipped} = Content.generate_thumbnail(original)

      # Only the user's cover remains — no auto-generated duplicate.
      thumb = Content.get_thumbnail_for_item(item.id)
      assert thumb.id == user_cover.id
      assert thumb.filename == "my-cover.jpg"
    end
  end

  # ── item_has_thumbnail?/1 ──────────────────────────────────────────────────

  describe "item_has_thumbnail?/1" do
    test "false when no THUMBNAIL bitstream exists" do
      item = create_item()
      refute Content.item_has_thumbnail?(item.id)
    end

    test "true after a THUMBNAIL bitstream is created" do
      item = create_item()

      {:ok, _} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "cover.jpg",
          "bundle_name" => "THUMBNAIL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/thumb/cover.jpg",
          "mime_type" => "image/jpeg",
          "access_level" => "open"
        })

      assert Content.item_has_thumbnail?(item.id)
    end
  end

  # ── get_thumbnail_for_item/1 ───────────────────────────────────────────────

  describe "get_thumbnail_for_item/1" do
    test "returns nil when no thumbnail exists" do
      item = create_item()
      assert Content.get_thumbnail_for_item(item.id) == nil
    end

    test "returns the THUMBNAIL bitstream when it exists" do
      item = create_item()

      {:ok, thumb} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "cover.jpg",
          "bundle_name" => "THUMBNAIL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/thumb/cover.jpg",
          "mime_type" => "image/jpeg",
          "access_level" => "open"
        })

      found = Content.get_thumbnail_for_item(item.id)
      assert found.id == thumb.id
    end
  end

  # ── Worker ──────────────────────────────────────────────────────────────────

  describe "ThumbnailWorker" do
    test "returns :ok for non-PDF (skip)" do
      item = create_item()

      {:ok, bs} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "not-a-pdf.txt",
          "bundle_name" => "ORIGINAL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/original/file.txt",
          "mime_type" => "text/plain",
          "access_level" => "open"
        })

      assert :ok == ThumbnailWorker.perform(%Oban.Job{args: %{"bitstream_id" => bs.id}})
    end

    @tag :pdftoppm
    test "end-to-end: generating a thumbnail for a real PDF via the worker" do
      assert_pdftoppm!()

      item = create_item()
      bs = create_original_pdf_bitstream(item)

      assert :ok == ThumbnailWorker.perform(%Oban.Job{args: %{"bitstream_id" => bs.id}})

      thumb = Content.get_thumbnail_for_item(item.id)
      assert thumb != nil
      assert thumb.bundle_name == :THUMBNAIL
      assert thumb.mime_type == "image/jpeg"
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Minimal valid single-page PDF. The text "Thumbnail Test" is on the page.
  defp real_pdf_bytes do
    stream = "BT /F1 12 Tf 72 720 Td (Thumbnail Test) Tj ET"

    """
    %PDF-1.4
    1 0 obj
    << /Type /Catalog /Pages 2 0 R >>
    endobj
    2 0 obj
    << /Type /Pages /Kids [3 0 R] /Count 1 >>
    endobj
    3 0 obj
    << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
    endobj
    4 0 obj
    << /Length #{byte_size(stream)} >>
    stream
    #{stream}
    endstream
    endobj
    5 0 obj
    << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
    endobj
    xref
    0 6
    0000000000 65535 f \r
    0000000010 00000 n \r
    0000000060 00000 n \r
    0000000110 00000 n \r
    0000000250 00000 n \r
    0000000350 00000 n \r
    trailer
    << /Size 6 /Root 1 0 R >>
    startxref
    430
    %%EOF
    """
  end
end
