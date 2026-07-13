defmodule Kiroku.Repository.Community do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @access_values ~w(open internal restricted closed)a

  schema "communities" do
    field :name, :string
    field :handle, :string
    field :short_description, :string
    field :description, :string
    field :logo_bitstream_id, :binary_id
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    # Visibility of this community in public browse/search. A community set to
    # :internal/:restricted/:closed is hidden from anonymous viewers.
    field :access_level, Ecto.Enum, values: @access_values, default: :open

    # Virtual field used only for hierarchical tree display in the admin UI.
    field :depth, :integer, virtual: true, default: 0

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
      :is_active,
      :access_level
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:handle)
    |> validate_not_self_parent()
  end

  # A community cannot be its own parent.
  defp validate_not_self_parent(%Ecto.Changeset{} = changeset) do
    id = get_field(changeset, :id)
    parent_id = get_field(changeset, :parent_community_id)

    if id && parent_id && id == parent_id do
      add_error(changeset, :parent_community_id, "cannot be its own parent")
    else
      changeset
    end
  end
end
