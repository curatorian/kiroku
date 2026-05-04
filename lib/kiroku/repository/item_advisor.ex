defmodule Kiroku.Repository.ItemAdvisor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(main_advisor co_advisor external industry law_clinic curator)a

  schema "item_advisors" do
    field :advisor_name, :string
    field :advisor_name_alt, :string
    field :advisor_role, Ecto.Enum, values: @roles, default: :main_advisor
    field :affiliation, :string
    field :nidn, :string
    field :sequence, :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(advisor, attrs) do
    advisor
    |> cast(attrs, [
      :advisor_name,
      :advisor_name_alt,
      :advisor_role,
      :affiliation,
      :nidn,
      :sequence,
      :item_id
    ])
    |> validate_required([:advisor_name, :advisor_role, :item_id])
    |> validate_length(:advisor_name, min: 1, max: 255)
    |> foreign_key_constraint(:item_id)
  end
end
