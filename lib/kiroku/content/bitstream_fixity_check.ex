defmodule Kiroku.Content.BitstreamFixityCheck do
  @moduledoc """
  Append-only audit trail of fixity (checksum) checks for a bitstream.
  Each row records one verification: expected vs actual checksum, outcome, and
  any error. The latest result is also denormalised onto the bitstream row
  (`last_fixity_at` / `last_fixity_ok`) for cheap dashboard queries.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bitstream_fixity_checks" do
    field :expected_checksum, :string
    field :actual_checksum, :string
    field :ok, :boolean
    field :error, :string

    belongs_to :bitstream, Kiroku.Content.Bitstream

    timestamps(updated_at: false)
  end

  def changeset(check, attrs) do
    check
    |> cast(attrs, [:expected_checksum, :actual_checksum, :ok, :error, :bitstream_id])
    |> validate_required([:expected_checksum, :bitstream_id])
    |> foreign_key_constraint(:bitstream_id)
  end
end
