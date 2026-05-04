defmodule Kiroku.Repository.ItemTeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(lead_developer developer designer researcher tester
            performer collaborator other)a

  schema "item_team_members" do
    field :member_name, :string
    field :member_name_alt, :string
    field :role, Ecto.Enum, values: @roles, default: :developer
    field :student_id, :string
    field :affiliation, :string
    field :sequence, :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [
      :member_name,
      :member_name_alt,
      :role,
      :student_id,
      :affiliation,
      :sequence,
      :item_id
    ])
    |> validate_required([:member_name, :item_id])
    |> validate_length(:member_name, min: 1, max: 255)
    |> foreign_key_constraint(:item_id)
  end
end
