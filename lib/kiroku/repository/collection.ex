defmodule Kiroku.Repository.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @access_values ~w(open internal restricted closed)a

  schema "collections" do
    field :name, :string
    field :handle, :string
    field :short_description, :string
    field :description, :string
    field :logo_bitstream_id, :binary_id
    field :license_text, :string
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    # Visibility of this collection in public browse/search.
    field :access_level, Ecto.Enum, values: @access_values, default: :open

    # Access level applied to new items created in this collection when the
    # submitter does not specify one. Enables collection-wide default policies
    # (e.g. a "Tugas Akhir" collection defaulting new items to :internal).
    field :default_item_access_level, Ecto.Enum, values: @access_values, default: :open

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
      :is_active,
      :access_level,
      :default_item_access_level
    ])
    |> validate_required([:name, :community_id])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:community_id)
  end
end
