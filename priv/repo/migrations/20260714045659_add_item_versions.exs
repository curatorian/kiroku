defmodule Kiroku.Repo.Migrations.AddItemVersions do
  use Ecto.Migration

  # Append-only version + audit history for items.
  #
  # Each lifecycle event (create, submit, review, publish, update, withdraw,
  # import) writes a row with:
  #   * a monotonically increasing version_number (per-item)
  #   * the action atom as a string
  #   * the acting user (nullable for system/import)
  #   * a JSONB snapshot of the key bibliographic fields at that point
  #
  # Serves double duty: version history (DSpace-style numbered snapshots) +
  # audit trail (who changed what when). The previous state had only
  # `reviewed_by_id` + `reviewed_at` capturing the latest reviewer.

  def change do
    create table(:item_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :item_id,
          references(:items, type: :binary_id, on_delete: :delete_all),
          null: false

      # Per-item version counter (1, 2, 3...). Increments on each event.
      add :version_number, :integer, null: false

      # What happened: "created", "updated", "submitted", "review_started",
      # "approved", "revision_requested", "rejected", "published",
      # "withdrawn", "imported", "embargo_lifted".
      add :action, :string, null: false

      # Who did it. Nullable for system events (MSSQL import, cron).
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Denormalised actor name for display when actor_id is nil (imports,
      # system jobs). Avoids N+1 joins when rendering the history table.
      add :actor_name, :string

      # Human-readable summary, e.g. "Published by admin@unpad.ac.id"
      add :summary, :string

      # Snapshot of the item's key fields at this version. JSONB so we can
      # diff versions without retaining full item rows.
      add :snapshot, :map

      timestamps(updated_at: false)
    end

    # (item_id, version_number) must be unique — one row per version per item.
    create unique_index(:item_versions, [:item_id, :version_number])

    # Common query patterns: "history for item X", "all actions by user Y".
    create index(:item_versions, [:item_id])
    create index(:item_versions, [:action])
    create index(:item_versions, [:actor_id])
  end
end
