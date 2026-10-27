defmodule Kiroku.ApiToken do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :last_used_at, :utc_datetime
    field :token_type, Ecto.Enum, values: [:user, :device], default: :user
    field :approved_at, :utc_datetime_usec

    belongs_to :user, Kiroku.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :token_hash, :last_used_at, :user_id, :token_type, :approved_at])
    |> validate_required([:name, :token_hash, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:token_type, [:user, :device])
  end
end
