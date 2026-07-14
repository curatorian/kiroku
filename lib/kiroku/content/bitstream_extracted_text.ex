defmodule Kiroku.Content.BitstreamExtractedText do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @moduledoc """
  Persisted result of extracting text from a bitstream (usually a PDF in
  the ORIGINAL bundle). One row per bitstream — extraction is idempotent.

  Either `text` (success) or `error` (failure) is set, never both. The
  parent item's denormalized `extracted_text` cache is rebuilt from the
  successful rows by `Content.recompute_item_extracted_text/1`.
  """

  schema "bitstream_extracted_text" do
    belongs_to :bitstream, Kiroku.Content.Bitstream

    field :text, :string
    field :page_count, :integer
    field :extractor, :string, default: "pdftotext"
    field :error, :string
    field :extracted_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:bitstream_id, :text, :page_count, :extractor, :error, :extracted_at])
    |> validate_required([:bitstream_id, :extractor, :extracted_at])
    |> unique_constraint(:bitstream_id)
  end
end
