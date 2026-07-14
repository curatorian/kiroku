defmodule Kiroku.Repo.Migrations.AddDoiMintingToItems do
  use Ecto.Migration

  # Tracks the lifecycle of DOI minting for items that do not already carry a
  # DOI (e.g. assigned manually via the journal-article form or imported via
  # SAF). Items minted through a provider eventually land in doi_status =
  # :minted with doi_minted_at set; failures end up in :failed so they can be
  # retried or surfaced in the admin UI.

  def up do
    alter table(:items) do
      # :pending      → not yet attempted (default for new items)
      # :minting      → DoiMintWorker is in flight
      # :minted       → provider returned a DOI and it was persisted to :doi
      # :failed       → last attempt errored; Oban will retry up to max_attempts
      # :not_required → item already carried a DOI at publish time, skip minting
      add :doi_status, :string, default: "pending", null: false
      add :doi_minted_at, :utc_datetime_usec
    end

    execute("""
    UPDATE items SET doi_status = 'minted'
    WHERE doi IS NOT NULL AND doi != ''
    """)

    create index(:items, [:doi_status])
  end

  def down do
    drop index(:items, [:doi_status])

    alter table(:items) do
      remove :doi_status
      remove :doi_minted_at
    end
  end
end
