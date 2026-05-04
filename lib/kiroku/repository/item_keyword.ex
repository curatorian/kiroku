defmodule Kiroku.Repository.ItemKeyword do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_keywords" do
    field :keyword, :string
    field :language, Ecto.Enum, values: [:id, :en], default: :id
    field :position, :integer, default: 0

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(keyword, attrs) do
    keyword
    |> cast(attrs, [:keyword, :language, :position, :item_id])
    |> validate_required([:keyword, :item_id])
    |> validate_length(:keyword, min: 1, max: 255)
    |> foreign_key_constraint(:item_id)
  end
end
