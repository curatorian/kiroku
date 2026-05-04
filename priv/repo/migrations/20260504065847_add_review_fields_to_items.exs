defmodule Kiroku.Repo.Migrations.AddReviewFieldsToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :review_note, :text, null: true
      add :reviewed_by_id, :binary_id, null: true
      add :reviewed_at, :utc_datetime_usec, null: true
      add :submitted_at, :utc_datetime_usec, null: true
    end

    create index(:items, [:reviewed_by_id])
  end
end
