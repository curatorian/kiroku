defmodule Kiroku.Repository.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "collections" do
    field :name, :string
    field :handle, :string
    field :short_description, :string
    field :description, :string
    field :logo_bitstream_id, :binary_id
    field :license_text, :string
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :community, Kiroku.Repository.Community
    has_many :items, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [
      :name,
      :handle,
      :short_description,
      :description,
      :logo_bitstream_id,
      :license_text,
      :position,
      :community_id,
      :is_active
    ])
    |> validate_required([:name, :community_id])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:community_id)
  end
end
