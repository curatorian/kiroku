defmodule Kiroku.Repository.Community do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "communities" do
    field :name, :string
    field :handle, :string
    field :short_description, :string
    field :description, :string
    field :logo_bitstream_id, :binary_id
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :parent_community, __MODULE__
    has_many :subcommunities, __MODULE__, foreign_key: :parent_community_id
    has_many :collections, Kiroku.Repository.Collection

    timestamps()
  end

  def changeset(community, attrs) do
    community
    |> cast(attrs, [
      :name,
      :handle,
      :short_description,
      :description,
      :logo_bitstream_id,
      :position,
      :parent_community_id,
      :is_active
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:handle)
  end
end
