defmodule Kiroku.Repo.Migrations.BackfillPublicationYearFromDates do
  use Ecto.Migration

  @moduledoc """
  Fills `publication_year` for items where it is nil — primarily records
  imported from the legacy MSSQL system, which only carry `Tgl_Upload`
  (mapped to `date_submitted` / `published_at`) and never set a publication
  year. Without this the /search year facet and year filter see nothing.

  Prefers `published_at`, falling back to `date_submitted`. `publication_year`
  is an `:integer` column; `EXTRACT(YEAR FROM ...)` already returns a numeric,
  cast explicitly for clarity.
  """

  def up do
    execute """
    UPDATE items
    SET publication_year = EXTRACT(YEAR FROM COALESCE(published_at, date_submitted))::int
    WHERE publication_year IS NULL
      AND (published_at IS NOT NULL OR date_submitted IS NOT NULL)
    """
  end

  def down do
    # Irreversible data backfill — years derived from dates are left in place.
    :ok
  end
end
