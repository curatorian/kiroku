defmodule Kiroku.Repo.Migrations.CreateRolePolicies do
  use Ecto.Migration

  def change do
    create table(:role_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_type, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :action, :string, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:role_policies, [:user_type])
    create index(:role_policies, [:resource_type, :resource_id])

    create unique_index(:role_policies, [:user_type, :resource_type, :resource_id, :action],
             name: :role_policies_unique_idx
           )
  end
end
