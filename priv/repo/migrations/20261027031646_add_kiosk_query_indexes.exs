defmodule Kiroku.Repo.Migrations.AddKioskQueryIndexes do
  use Ecto.Migration

  def change do
    # Faculty browse first paint: filter + newest-first page ordering.
    create index(:items, [:faculty, :published_at])

    # Prefix browsing (`starts_with`) can use text_pattern_ops btree indexes.
    execute(
      "CREATE INDEX items_title_prefix_index ON items (title text_pattern_ops)",
      "DROP INDEX items_title_prefix_index"
    )

    execute(
      "CREATE INDEX items_student_name_prefix_index ON items (student_name text_pattern_ops)",
      "DROP INDEX items_student_name_prefix_index"
    )

    execute(
      "CREATE INDEX items_subject_prefix_index ON items (subject_classification text_pattern_ops)",
      "DROP INDEX items_subject_prefix_index"
    )
  end
end
