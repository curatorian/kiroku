defmodule Kiroku.Repo.Migrations.CreateViewEvents do
  use Ecto.Migration

  def change do
    create table(:view_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_id, :binary_id, null: false
      add :user_id, :binary_id
      add :ip_hash, :string
      add :user_agent, :string
      add :referer, :string

      timestamps(updated_at: false)
    end

    create index(:view_events, [:item_id])
    create index(:view_events, [:user_id])
    create index(:view_events, [:inserted_at])
  end
end
