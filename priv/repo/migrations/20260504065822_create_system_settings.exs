defmodule Kiroku.Repo.Migrations.CreateSystemSettings do
  use Ecto.Migration

  def change do
    create table(:system_settings) do
      add :key, :string, null: false
      add :value, :text, null: true
      add :description, :string, null: true

      timestamps()
    end

    create unique_index(:system_settings, [:key])
  end
end
