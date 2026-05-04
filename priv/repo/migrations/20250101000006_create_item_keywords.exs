defmodule Kiroku.Repo.Migrations.CreateItemKeywords do
  use Ecto.Migration

  def change do
    create table(:item_keywords, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :keyword, :string, null: false
      add :language, :string, default: "id"
      add :position, :integer, default: 0
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_keywords, [:item_id])
    create index(:item_keywords, [:keyword])
  end
end
