defmodule Kiroku.Repo.Migrations.CreateDeadLetterQueue do
  use Ecto.Migration

  def change do
    create table(:dead_letter_queue, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :legacy_id, :string, null: false
      add :error_message, :text, null: false
      add :error_category, :string, null: false
      add :retry_count, :integer, default: 0, null: false
      add :first_failed_at, :utc_datetime
      add :last_attempted_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :resolution_notes, :text
      add :original_data, :map, default: %{}
      add :sync_run_id, references(:sync_runs, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:dead_letter_queue, [:legacy_id])
    create index(:dead_letter_queue, [:error_category])
    create index(:dead_letter_queue, [:resolved_at])
    create index(:dead_letter_queue, [:sync_run_id])
  end
end
