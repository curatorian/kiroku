defmodule Kiroku.Repo.Migrations.AddRecordsSkippedToSyncRuns do
  use Ecto.Migration

  def change do
    alter table(:sync_runs) do
      add :records_skipped, :integer, default: 0, null: false
    end
  end
end
