defmodule Kiroku.Analytics.ViewEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "view_events" do
    field :item_id, :binary_id
    field :user_id, :binary_id
    field :ip_hash, :string
    field :user_agent, :string
    field :referer, :string

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:item_id, :user_id, :ip_hash, :user_agent, :referer])
    |> validate_required([:item_id])
  end
end
