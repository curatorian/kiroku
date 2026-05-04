defmodule Kiroku.Repository.ItemExaminer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_examiners" do
    field :examiner_name, :string
    field :examiner_name_alt, :string
    field :affiliation, :string
    field :nidn, :string
    field :sequence, :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(examiner, attrs) do
    examiner
    |> cast(attrs, [:examiner_name, :examiner_name_alt, :affiliation, :nidn, :sequence, :item_id])
    |> validate_required([:examiner_name, :item_id])
    |> validate_length(:examiner_name, min: 1, max: 255)
    |> foreign_key_constraint(:item_id)
  end
end
