defmodule Kiroku.Repo.Migrations.CreateItemMetadataExtras do
  use Ecto.Migration

  def change do
    create table(:item_metadata_extras, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :field_schema, :string, null: false
      add :field_element, :string, null: false
      add :field_qualifier, :string
      add :field_value, :text, null: false
      add :language, :string
      add :position, :integer, default: 0
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_metadata_extras, [:item_id])
    create index(:item_metadata_extras, [:field_schema, :field_element])
  end
end
