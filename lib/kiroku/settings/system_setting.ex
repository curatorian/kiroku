defmodule Kiroku.Settings.SystemSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "system_settings" do
    field :key, :string
    field :value, :string
    field :description, :string

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :description])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
