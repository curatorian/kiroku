defmodule Kiroku.Repo.Migrations.CreateDownloadEvents do
  use Ecto.Migration

  def change do
    create table(:download_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_id, :binary_id, null: false

      add :bitstream_id,
          references(:bitstreams, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, :binary_id
      add :ip_hash, :string
      add :user_agent, :string
      add :referer, :string

      timestamps(updated_at: false)
    end

    create index(:download_events, [:item_id])
    create index(:download_events, [:bitstream_id])
    create index(:download_events, [:user_id])
    create index(:download_events, [:inserted_at])
  end
end
