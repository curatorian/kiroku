defmodule Kiroku.Repo.Migrations.CreateSyncRuns do
  use Ecto.Migration

  def change do
    create table(:sync_runs) do
      add :source_view, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :records_processed, :integer, default: 0
      add :records_inserted, :integer, default: 0
      add :records_updated, :integer, default: 0
      add :records_failed, :integer, default: 0
      add :last_synced_at, :utc_datetime
      add :last_synced_legacy_id, :string
      add :error_message, :text
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:sync_runs, [:source_view])
    create index(:sync_runs, [:status])
    create index(:sync_runs, [:started_at])

    # Create a table to track individual record sync status
    create table(:sync_record_tracking) do
      add :sync_run_id, references(:sync_runs, on_delete: :delete_all), null: false
      add :legacy_id, :string, null: false
      add :item_id, :binary_id
      # "inserted", "updated", "failed", "skipped"
      add :action, :string
      add :synced_at, :utc_datetime
      add :error_message, :text
      add :checksum, :string

      timestamps()
    end

    create index(:sync_record_tracking, [:sync_run_id])
    create index(:sync_record_tracking, [:legacy_id])
    create unique_index(:sync_record_tracking, [:legacy_id, :sync_run_id])
  end
end
