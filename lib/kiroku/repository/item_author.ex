defmodule Kiroku.Repository.ItemAuthor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_authors" do
    field :author_name, :string
    field :author_name_alt, :string
    field :affiliation, :string
    field :email, :string
    field :orcid, :string
    field :scopus_author_id, :string
    field :sequence, :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(author, attrs) do
    author
    |> cast(attrs, [
      :author_name,
      :author_name_alt,
      :affiliation,
      :email,
      :orcid,
      :scopus_author_id,
      :sequence,
      :item_id
    ])
    |> validate_required([:author_name, :item_id])
    |> validate_length(:author_name, min: 1, max: 255)
    |> foreign_key_constraint(:item_id)
  end
end
