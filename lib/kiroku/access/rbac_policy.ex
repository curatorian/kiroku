defmodule Kiroku.Access.RbacPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @policy_actions ~w(read submit review publish manage)a
  @resource_types ~w(community collection item global)a

  schema "rbac_policies" do
    field :resource_type, Ecto.Enum, values: @resource_types
    field :resource_id, :binary_id
    field :action, Ecto.Enum, values: @policy_actions
    field :notes, :string

    belongs_to :user, Kiroku.Accounts.User

    timestamps()
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:resource_type, :resource_id, :action, :notes, :user_id])
    |> validate_required([:resource_type, :action])
    |> foreign_key_constraint(:user_id)
  end
end
