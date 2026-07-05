defmodule Kiroku.Sync.SyncRun do
  @moduledoc """
  Schema for tracking synchronization runs from MSSQL views.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_runs" do
    field :source_view, :string
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :records_processed, :integer, default: 0
    field :records_inserted, :integer, default: 0
    field :records_updated, :integer, default: 0
    field :records_failed, :integer, default: 0
    field :last_synced_at, :utc_datetime
    field :last_synced_legacy_id, :string
    field :error_message, :string
    field :metadata, :map, default: %{}

    has_many :sync_record_tracking, Kiroku.Sync.SyncRecordTracking, foreign_key: :sync_run_id

    timestamps()
  end

  @doc false
  def changeset(sync_run, attrs) do
    sync_run
    |> cast(attrs, [
      :source_view,
      :status,
      :started_at,
      :completed_at,
      :records_processed,
      :records_inserted,
      :records_updated,
      :records_failed,
      :last_synced_at,
      :last_synced_legacy_id,
      :error_message,
      :metadata
    ])
    |> validate_required([:source_view, :status])
    |> validate_inclusion(:status, ["pending", "running", "completed", "failed"])
    |> validate_number(:records_processed, greater_than_or_equal_to: 0)
    |> validate_number(:records_inserted, greater_than_or_equal_to: 0)
    |> validate_number(:records_updated, greater_than_or_equal_to: 0)
    |> validate_number(:records_failed, greater_than_or_equal_to: 0)
  end
end
