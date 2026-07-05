defmodule Kiroku.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :handle, :string, null: false
      add :short_description, :string
      add :description, :text
      add :logo_bitstream_id, :binary_id
      add :license_text, :text
      add :position, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false

      add :community_id,
          references(:communities, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps()
    end

    create unique_index(:collections, [:handle])
    create index(:collections, [:community_id])
    create index(:collections, [:is_active])
  end
end
