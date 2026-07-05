defmodule Kiroku.Sync.SyncRecordTracking do
  @moduledoc """
  Schema for tracking individual record synchronization status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_record_tracking" do
    field :legacy_id, :string
    field :item_id, :binary_id
    field :action, :string
    field :synced_at, :utc_datetime
    field :error_message, :string
    field :checksum, :string

    belongs_to :sync_run, Kiroku.Sync.SyncRun

    timestamps()
  end

  @doc false
  def changeset(sync_record_tracking, attrs) do
    sync_record_tracking
    |> cast(attrs, [
      :sync_run_id,
      :legacy_id,
      :item_id,
      :action,
      :synced_at,
      :error_message,
      :checksum
    ])
    |> validate_required([:sync_run_id, :legacy_id, :action])
    |> validate_inclusion(:action, ["inserted", "updated", "failed", "skipped"])
    |> foreign_key_constraint(:sync_run_id)
    |> unique_constraint([:legacy_id, :sync_run_id])
  end
end
