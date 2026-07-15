defmodule Kiroku.Access.RolePolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @user_types ~w(submitter internal reviewer admin)a
  @policy_actions ~w(read submit review publish manage)a
  @resource_types ~w(community collection item global)a

  schema "role_policies" do
    field :user_type, Ecto.Enum, values: @user_types
    field :resource_type, Ecto.Enum, values: @resource_types
    field :resource_id, :binary_id
    field :action, Ecto.Enum, values: @policy_actions
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:user_type, :resource_type, :resource_id, :action, :notes])
    |> validate_required([:user_type, :resource_type, :action])
    |> unique_constraint([:user_type, :resource_type, :resource_id, :action],
      name: :role_policies_unique_idx
    )
  end

  def user_types, do: @user_types
  def policy_actions, do: @policy_actions
  def resource_types, do: @resource_types
end
