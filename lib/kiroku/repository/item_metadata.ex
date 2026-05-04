defmodule Kiroku.Repository.ItemMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @doc """
  Supplementary key-value metadata rows following Dublin Core / local qualifier
  convention: "{field_schema}.{field_element}.{field_qualifier}".

  Examples:
    - "dc.relation.uri"          → related URL / DOI
    - "local.description.funding" → funding statement
    - "local.identifier.scopus"  → Scopus article ID
    - "local.subject.sdg"        → SDG goal number (multi-value)
  """
  schema "item_metadata_extras" do
    field :field_schema, :string
    field :field_element, :string
    field :field_qualifier, :string
    field :field_value, :string
    field :language, :string
    field :position, :integer, default: 0

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(meta, attrs) do
    meta
    |> cast(attrs, [
      :field_schema,
      :field_element,
      :field_qualifier,
      :field_value,
      :language,
      :position,
      :item_id
    ])
    |> validate_required([:field_schema, :field_element, :field_value, :item_id])
    |> validate_length(:field_value, min: 1, max: 4000)
    |> foreign_key_constraint(:item_id)
  end
end
