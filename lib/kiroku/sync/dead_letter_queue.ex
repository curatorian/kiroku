defmodule Kiroku.Sync.DeadLetterQueue do
  @moduledoc """
  Schema for storing sync records that failed repeatedly and require manual intervention.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dead_letter_queue" do
    field :legacy_id, :string
    field :error_message, :string
    field :error_category, :string
    field :retry_count, :integer, default: 0
    field :first_failed_at, :utc_datetime
    field :last_attempted_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :resolution_notes, :string
    field :original_data, :map

    belongs_to :sync_run, Kiroku.Sync.SyncRun

    timestamps()
  end

  @doc false
  def changeset(dead_letter, attrs) do
    dead_letter
    |> cast(attrs, [
      :sync_run_id,
      :legacy_id,
      :error_message,
      :error_category,
      :retry_count,
      :first_failed_at,
      :last_attempted_at,
      :resolved_at,
      :resolution_notes,
      :original_data
    ])
    |> validate_required([:legacy_id, :error_message, :error_category])
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:error_category, ["transient", "data", "system", "critical", "unknown"])
    |> foreign_key_constraint(:sync_run_id)
  end
end
