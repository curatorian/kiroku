defmodule Kiroku.Repo.Migrations.CreateItemAdvisors do
  use Ecto.Migration

  def change do
    create table(:item_advisors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :advisor_name, :string, null: false
      add :advisor_name_alt, :string
      add :advisor_role, :string, default: "main_advisor"
      add :affiliation, :string
      add :nidn, :string
      add :sequence, :integer, default: 1
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_advisors, [:item_id])
  end
end
