defmodule Kiroku.Repo.Migrations.CreateKioskEvents do
  use Ecto.Migration

  def change do
    create table(:kiosk_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :type, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :payload, :map, null: false, default: %{}
      add :device_token_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    # Idempotent replay: a re-posted batch cannot duplicate events.
    create unique_index(:kiosk_events, [:session_id, :type, :occurred_at],
             name: :kiosk_events_session_type_time_index
           )

    create index(:kiosk_events, [:session_id])
    create index(:kiosk_events, [:type, :occurred_at])
  end
end
