defmodule Kiroku.Repo.Migrations.CreateRbacPolicies do
  use Ecto.Migration

  def change do
    create table(:rbac_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :action, :string, null: false
      add :notes, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:rbac_policies, [:user_id])
    create index(:rbac_policies, [:resource_type, :resource_id])
    create unique_index(:rbac_policies, [:user_id, :resource_type, :resource_id, :action])
  end
end
