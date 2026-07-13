defmodule Kiroku.Repo.Migrations.AddSearchVectorToItems do
  use Ecto.Migration

  # Replaces the per-query `to_tsvector('indonesian', title || abstract)`
  # recomputation with a PostgreSQL GENERATED ALWAYS AS (...) STORED column.
  # The column auto-maintains itself whenever `title` or `abstract` change, so
  # there is no trigger to keep in sync. Backfills existing rows automatically.
  #
  # A GIN index makes the `search_vector @@ plainto_tsquery(...)` predicate
  # index-backed instead of a sequential scan, and `ts_rank(search_vector, q)`
  # can order results by relevance without recomputing the vector.

  def up do
    execute("""
    ALTER TABLE items
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      to_tsvector('indonesian', coalesce(title, '') || ' ' || coalesce(abstract, ''))
    ) STORED
    """)

    create index(:items, [:search_vector], using: :gin)
  end

  def down do
    drop index(:items, [:search_vector])

    execute("ALTER TABLE items DROP COLUMN IF EXISTS search_vector")
  end
end
