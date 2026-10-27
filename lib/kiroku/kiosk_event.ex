defmodule Kiroku.KioskEvent do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kiosk_events" do
    field :session_id, :string
    field :type, :string
    field :occurred_at, :utc_datetime_usec
    field :payload, :map, default: %{}

    belongs_to :device_token, Kiroku.ApiToken

    timestamps(type: :utc_datetime)
  end
end
