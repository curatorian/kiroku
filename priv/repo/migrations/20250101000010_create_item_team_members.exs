defmodule Kiroku.Repo.Migrations.CreateItemTeamMembers do
  use Ecto.Migration

  def change do
    create table(:item_team_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :member_name, :string, null: false
      add :member_name_alt, :string
      add :role, :string, default: "developer"
      add :student_id, :string
      add :affiliation, :string
      add :sequence, :integer, default: 1
      add :item_id, references(:items, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:item_team_members, [:item_id])
  end
end
