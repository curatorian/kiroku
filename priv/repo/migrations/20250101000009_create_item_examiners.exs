defmodule Kiroku.Repo.Migrations.CreateItemExaminers do
  use Ecto.Migration

  def change do
    create table(:item_examiners, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :examiner_name, :string, null: false
      add :examiner_name_alt, :string
      add :affiliation, :string
      add :nidn, :string
      add :sequence, :integer, default: 1
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_examiners, [:item_id])
  end
end
