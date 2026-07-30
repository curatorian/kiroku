defmodule Kiroku.Repo.Migrations.ExpandSearchVectorMetadata do
  use Ecto.Migration

  # Broadens the generated `items.search_vector` so the public search box
  # matches any item-level metadata, not just title/abstract/full-text.
  #
  # Added to the tsvector: alternate title/abstract, the student's name
  # (the primary author for thesis types), subject classification, and the
  # organisational metadata (department / faculty / program study).
  #
  # Author names and keywords live in separate tables and cannot be folded
  # into a single-table GENERATED column; those are matched at query time in
  # `Repository.maybe_full_text_filter/2` instead.

  @vector """
  ALTER TABLE items
  ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    to_tsvector(
      'indonesian',
      coalesce(title, '') || ' ' ||
      coalesce(title_alt, '') || ' ' ||
      coalesce(abstract, '') || ' ' ||
      coalesce(abstract_alt, '') || ' ' ||
      coalesce(student_name, '') || ' ' ||
      coalesce(subject_classification, '') || ' ' ||
      coalesce(department, '') || ' ' ||
      coalesce(faculty, '') || ' ' ||
      coalesce(program_study, '') || ' ' ||
      coalesce(extracted_text, '')
    )
  ) STORED
  """

  def up do
    execute("DROP INDEX IF EXISTS items_search_vector_index")
    execute("ALTER TABLE items DROP COLUMN IF EXISTS search_vector")
    execute(@vector)
    create index(:items, [:search_vector], using: :gin)
  end

  def down do
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
end
