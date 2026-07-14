defmodule Kiroku.Repo.Migrations.AddPdfTextExtraction do
  use Ecto.Migration

  # Adds full-text PDF extraction infrastructure:
  #
  # 1. `bitstream_extracted_text` table — one row per bitstream that has had
  #    its text extracted (mostly ORIGINAL PDFs). Stores the extracted text,
  #    the extractor used (so we can re-run if we change tools), page count,
  #    and whether the last run errored.
  #
  # 2. `items.extracted_text` — denormalized cache that holds the
  #    concatenation of all extracted text for the item's bitstreams. Updated
  #    by `Content.recompute_item_extracted_text/1` whenever extraction
  #    completes or a bitstream is removed.
  #
  # 3. `items.search_vector` is regenerated to fold `extracted_text` into the
  #    PostgreSQL tsvector. Postgres generated columns cannot reference other
  #    tables, which is why we keep a denormalized text column on items
  #    instead of joining at query time.

  def up do
    alter table(:items) do
      add :extracted_text, :text
    end

    create table(:bitstream_extracted_text, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bitstream_id,
          references(:bitstreams, type: :binary_id, on_delete: :delete_all),
          null: false

      # Nullable: present when extraction succeeded, nil when it errored.
      add :text, :text
      add :page_count, :integer
      # "pdftotext", "tika", etc. — so we can selectively re-extract if a
      # better extractor is added later.
      add :extractor, :string, null: false, default: "pdftotext"
      add :error, :string
      add :extracted_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    # One row per bitstream — extraction is idempotent.
    create unique_index(:bitstream_extracted_text, [:bitstream_id])

    # Regenerate the search_vector so it includes extracted_text in addition
    # to title and abstract. Drop the GIN index and column first, then
    # re-add them with the expanded expression.
    execute("DROP INDEX IF EXISTS items_search_vector_index")

    execute("ALTER TABLE items DROP COLUMN IF EXISTS search_vector")

    execute("""
    ALTER TABLE items
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      to_tsvector(
        'indonesian',
        coalesce(title, '') || ' ' ||
        coalesce(abstract, '') || ' ' ||
        coalesce(extracted_text, '')
      )
    ) STORED
    """)

    create index(:items, [:search_vector], using: :gin)
  end

  def down do
    execute("DROP INDEX IF EXISTS items_search_vector_index")

    execute("ALTER TABLE items DROP COLUMN IF EXISTS search_vector")

    execute("""
    ALTER TABLE items
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      to_tsvector('indonesian', coalesce(title, '') || ' ' || coalesce(abstract, ''))
    ) STORED
    """)

    create index(:items, [:search_vector], using: :gin)

    drop unique_index(:bitstream_extracted_text, [:bitstream_id])
    drop table(:bitstream_extracted_text)

    alter table(:items) do
      remove :extracted_text
    end
  end
end
