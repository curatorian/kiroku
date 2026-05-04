defmodule Kiroku.Repo.Migrations.CreateCommunities do
  use Ecto.Migration

  def change do
    create table(:communities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :handle, :string, null: false
      add :short_description, :string
      add :description, :text
      add :logo_bitstream_id, :binary_id
      add :position, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false

      add :parent_community_id,
          references(:communities, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:communities, [:handle])
    create index(:communities, [:parent_community_id])
    create index(:communities, [:is_active])
    create index(:communities, [:position])
  end
end
