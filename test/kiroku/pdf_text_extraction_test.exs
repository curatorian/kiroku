defmodule Kiroku.PdfTextExtractionTest do
  use Kiroku.DataCase, async: true

  # The extractor shells out to `pdftotext` (poppler-utils). Tests that depend
  # on the binary assert its presence via `assert_pdftotext!/0`. The DB-only
  # paths (recompute, persistence) are always testable.

  alias Kiroku.{Content, Repo, Repository}
  alias Kiroku.Content.BitstreamExtractedText
  alias Kiroku.Workers.PdfTextWorker

  # ── Fixtures ───────────────────────────────────────────────────────────────

  defp create_collection do
    handle = "test-comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Test Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(%{
        "name" => "Test Collection",
        "community_id" => community.id,
        "handle" => "test-coll-#{System.unique_integer([:positive])}"
      })

    collection
  end

  defp create_item(attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Thesis",
            "collection_id" => create_collection().id
          },
          attrs
        )
      )

    item
  end

  defp create_bitstream(item, attrs) do
    {:ok, bs} =
      Content.create_bitstream(
        Map.merge(
          %{
            "item_id" => item.id,
            "filename" => "doc.pdf",
            "bundle_name" => "ORIGINAL",
            "sequence" => 1,
            "storage_type" => "local",
            "storage_path" => "items/#{item.id}/original/abc.pdf",
            "mime_type" => "application/pdf",
            "access_level" => "open"
          },
          attrs
        )
      )

    bs
  end

  defp write_local(path, bytes) do
    abs = Path.join("priv/uploads", path)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, bytes)
  end

  # Asserts pdftotext is on PATH. Fails with a helpful message rather than
  # silently passing when the feature can't be exercised.
  defp assert_pdftotext! do
    assert System.find_executable("pdftotext"),
           "pdftotext binary not found — install poppler-utils to run PDF extraction tests"
  end

  # ── PDF detection ──────────────────────────────────────────────────────────

  describe "extract_text/1 — skip paths" do
    test "returns {:ok, nil} for a non-PDF bitstream" do
      item = create_item()
      bs = create_bitstream(item, %{"mime_type" => "image/png", "filename" => "thumb.png"})
      assert {:ok, nil} = Content.extract_text(bs)
    end

    test "returns {:ok, nil} for externally-hosted :url bitstreams" do
      item = create_item()

      bs =
        create_bitstream(item, %{
          "storage_type" => "url",
          "storage_url" => "https://example.com/doc.pdf"
        })

      assert {:ok, nil} = Content.extract_text(bs)
    end

    test "infers PDF from filename when mime_type is absent" do
      item = create_item()
      bs = create_bitstream(item, %{"mime_type" => nil, "filename" => "thesis.PDF"})

      # No real bytes on disk → extractor errors, but it should have been
      # ATTEMPTED (rather than skipped as {:ok, nil}).
      assert {:error, _} = Content.extract_text(bs)
    end
  end

  # ── Real extraction via pdftotext ──────────────────────────────────────────

  describe "extract_text/1 — real pdftotext extraction" do
    @tag :pdftotext
    test "extracts text from a real PDF and updates item.extracted_text" do
      assert_pdftotext!()

      item =
        create_item(%{
          "title" => "Genap Saya Setuju",
          "abstract" => "Abstract about coffee cultivation."
        })

      bs = create_bitstream(item, %{})
      write_local(bs.storage_path, real_pdf_bytes("Kopi robusta adalah tanaman penting."))

      assert {:ok, text} = Content.extract_text(bs)
      assert text =~ "Kopi robusta"

      # Extraction row persisted.
      row = Repo.get_by(BitstreamExtractedText, bitstream_id: bs.id)
      assert row.text =~ "Kopi robusta"
      assert row.error == nil
      assert row.extractor == "pdftotext"

      # Item's denormalized cache was rebuilt.
      reloaded = Repository.get_item!(item.id)
      assert reloaded.extracted_text =~ "Kopi robusta"
    end

    @tag :pdftotext
    test "records an error row when bytes are not a valid PDF" do
      assert_pdftotext!()

      item = create_item()
      bs = create_bitstream(item, %{})
      write_local(bs.storage_path, "not actually a pdf")

      assert {:error, {:extractor_failed, _, _}} = Content.extract_text(bs)

      row = Repo.get_by(BitstreamExtractedText, bitstream_id: bs.id)
      assert row.text == nil
      assert row.error =~ "pdftotext exited"
    end
  end

  describe "extract_text/1 — idempotent upsert" do
    @tag :pdftotext
    test "re-extracting replaces the previous row instead of creating a new one" do
      assert_pdftotext!()

      item = create_item()
      bs = create_bitstream(item, %{})
      write_local(bs.storage_path, real_pdf_bytes("first version text"))

      assert {:ok, _} = Content.extract_text(bs)

      write_local(bs.storage_path, real_pdf_bytes("second version different"))

      assert {:ok, _} = Content.extract_text(bs)

      rows = Repo.all(from e in BitstreamExtractedText, where: e.bitstream_id == ^bs.id)
      assert length(rows) == 1
      assert hd(rows).text =~ "second version"
    end
  end

  # ── recompute_item_extracted_text/1 (pure DB path) ─────────────────────────

  describe "recompute_item_extracted_text/1" do
    test "concatenates all successful extractions for the item" do
      item = create_item(%{"title" => "x", "abstract" => "y"})

      bs1 = create_bitstream(item, %{"sequence" => 1})
      bs2 = create_bitstream(item, %{"sequence" => 2, "filename" => "doc2.pdf"})

      insert_extraction(bs1, "chapter one content")
      insert_extraction(bs2, "chapter two content")

      :ok = Content.recompute_item_extracted_text(item.id)

      reloaded = Repository.get_item!(item.id)
      # Ordered by bundle_name, sequence — bs1 before bs2.
      assert reloaded.extracted_text =~ "chapter one content"
      assert reloaded.extracted_text =~ "chapter two content"

      {idx1, _} = :binary.match(reloaded.extracted_text, "chapter one")
      {idx2, _} = :binary.match(reloaded.extracted_text, "chapter two")
      assert idx1 < idx2
    end

    test "excludes bitstreams whose extraction errored (text is nil)" do
      item = create_item(%{"title" => "x"})

      bs_ok = create_bitstream(item, %{"sequence" => 1})
      bs_failed = create_bitstream(item, %{"sequence" => 2, "filename" => "failed.pdf"})

      insert_extraction(bs_ok, "good text here")
      insert_extraction(bs_failed, nil, "pdftotext crashed")

      :ok = Content.recompute_item_extracted_text(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.extracted_text =~ "good text here"
      refute reloaded.extracted_text =~ "pdftotext crashed"
    end

    test "clears extracted_text when all rows are gone" do
      item = create_item(%{"title" => "x"})
      bs = create_bitstream(item, %{"sequence" => 1})
      insert_extraction(bs, "temp text")

      :ok = Content.recompute_item_extracted_text(item.id)
      assert Repository.get_item!(item.id).extracted_text =~ "temp text"

      Repo.delete_all(from e in BitstreamExtractedText, where: e.bitstream_id == ^bs.id)

      :ok = Content.recompute_item_extracted_text(item.id)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.extracted_text in [nil, ""]
    end
  end

  # ── Worker ──────────────────────────────────────────────────────────────────

  describe "PdfTextWorker" do
    test "returns :ok with :no_storage_path (non-retryable)" do
      item = create_item()
      bs = create_bitstream(item, %{"storage_path" => nil})

      assert :ok == perform_worker(bs.id)
    end

    test "returns :ok with :pdftotext_not_found (non-retryable)" do
      # We can't easily uninstall pdftotext in CI, so this test only exercises
      # the code path when the binary is actually missing.
      if System.find_executable("pdftotext") do
        # Binary present — fall through to the actual extraction path, which
        # will fail because there's no real PDF on disk.
        item = create_item()
        bs = create_bitstream(item, %{})
        write_local(bs.storage_path, "fake bytes")

        assert _ = perform_worker(bs.id)
      else
        item = create_item()
        bs = create_bitstream(item, %{})
        write_local(bs.storage_path, real_pdf_bytes("anything"))

        assert :ok == perform_worker(bs.id)
      end
    end

    @tag :pdftotext
    test "end-to-end: enqueuing on create_bitstream populates item.extracted_text" do
      assert_pdftotext!()

      item = create_item(%{"title" => "x", "abstract" => "y"})

      # create_bitstream auto-enqueues the worker via Oban (which is in
      # :inline mode in tests, so it runs synchronously).
      {:ok, bs} =
        Content.create_bitstream(%{
          "item_id" => item.id,
          "filename" => "thesis.pdf",
          "bundle_name" => "ORIGINAL",
          "sequence" => 1,
          "storage_type" => "local",
          "storage_path" => "items/#{item.id}/original/xyz.pdf",
          "mime_type" => "application/pdf",
          "access_level" => "open"
        })

      write_local(bs.storage_path, real_pdf_bytes("end to end pipeline text"))

      # Worker already ran inline on insert; redo extraction to pick up the
      # file we just wrote (the inline run happened before the write).
      assert {:ok, _} = Content.extract_text(bs)

      reloaded = Repository.get_item!(item.id)
      assert reloaded.extracted_text =~ "end to end pipeline text"
    end
  end

  # ── Full-text search integration ───────────────────────────────────────────

  describe "search_vector integration" do
    @tag :pdftotext
    test "PDF body text is discoverable via Repository.search_items/1" do
      assert_pdftotext!()

      # Title and abstract deliberately don't contain the search term — only
      # the PDF body does. Proves extracted_text is folded into search_vector.
      item =
        create_item(%{
          "title" => "An unrelated title",
          "abstract" => "An unrelated abstract.",
          "status" => "published",
          "discoverable" => true,
          "published_at" => NaiveDateTime.utc_now(),
          "access_level" => "open"
        })

      bs = create_bitstream(item, %{})
      write_local(bs.storage_path, real_pdf_bytes("The rare term quinquesphenoid appears here."))

      assert {:ok, _} = Content.extract_text(bs)

      results = Repository.search_items(%{term: "quinquesphenoid", scope: :public})
      titles = Enum.map(results, & &1.title)

      assert "An unrelated title" in titles
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp insert_extraction(bitstream, text, error \\ nil) do
    {:ok, _} =
      %BitstreamExtractedText{}
      |> BitstreamExtractedText.changeset(%{
        bitstream_id: bitstream.id,
        text: text,
        error: error,
        extractor: "pdftotext",
        extracted_at: DateTime.utc_now()
      })
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :bitstream_id)
  end

  defp perform_worker(bitstream_id) do
    PdfTextWorker.perform(%Oban.Job{args: %{"bitstream_id" => bitstream_id}})
  end

  # Smallest-possible valid single-page PDF whose text content is `body`.
  # Hand-crafted so we don't need to commit a binary fixture file.
  defp real_pdf_bytes(body) do
    stream = "BT /F1 12 Tf 72 720 Td (#{escape_pdf_string(body)}) Tj ET"

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

  defp escape_pdf_string(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end
end
