defmodule Kiroku.Repo.Migrations.AddFixityChecks do
  use Ecto.Migration

  def change do
    alter table(:bitstreams) do
      # Last fixity-check result, denormalised for cheap dashboard queries.
      # Nullable: null = never checked.
      add :last_fixity_at, :utc_datetime_usec
      add :last_fixity_ok, :boolean
    end

    create index(:bitstreams, [:last_fixity_ok])

    create table(:bitstream_fixity_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bitstream_id,
          references(:bitstreams, type: :binary_id, on_delete: :delete_all),
          null: false

      add :expected_checksum, :string, null: false
      add :actual_checksum, :string
      # true = matched, false = mismatch, null = could not compute (e.g. :url)
      add :ok, :boolean
      add :error, :string

      timestamps(updated_at: false)
    end

    create index(:bitstream_fixity_checks, [:bitstream_id])
    create index(:bitstream_fixity_checks, [:ok])
  end
end
