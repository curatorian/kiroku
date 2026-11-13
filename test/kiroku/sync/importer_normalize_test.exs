defmodule Kiroku.Sync.ImporterNormalizeTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Sync.Importer

  # Regression: legacy MSSQL nvarchar data carries embedded NUL bytes, which
  # Postgres rejects with `ERROR 22021 invalid byte sequence for encoding
  # "UTF8": 0x00` — the whole record used to fail the import.
  test "strips NUL bytes from all string values, including title and abstract" do
    attrs = %{
      title: "Pengaruh\0Storage\0terhadap File Repository",
      abstract: "Abstrak\0with NULs\0",
      student_name: "Budi\0Santoso",
      student_id: "12345678"
    }

    normalized = Importer.normalize_for_storage(attrs)

    assert normalized.title == "PengaruhStorageterhadap File Repository"
    assert normalized.abstract == "Abstrakwith NULs"
    assert normalized.student_name == "BudiSantoso"
    assert normalized.student_id == "12345678"
    refute normalized.title =~ "\0"
    refute normalized.abstract =~ "\0"
  end

  test "still caps non-text varchar fields to 255 characters" do
    attrs = %{student_name: String.duplicate("a", 300)}

    normalized = Importer.normalize_for_storage(attrs)

    assert String.length(normalized.student_name) == 255
  end

  test "leaves long title and abstract intact (text columns)" do
    attrs = %{title: String.duplicate("t", 300), abstract: String.duplicate("a", 300)}

    normalized = Importer.normalize_for_storage(attrs)

    assert String.length(normalized.title) == 300
    assert String.length(normalized.abstract) == 300
  end

  test "passes non-binary values through untouched" do
    attrs = %{collection_id: "uuid", student_id: 12_345, title: nil}

    assert Importer.normalize_for_storage(attrs) == attrs
  end
end
