defmodule Kiroku.Access.RbacPolicies do
  @moduledoc "Context for managing RBAC policies."

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Access.RbacPolicy

  def list_policies_for_user(user_id) do
    Repo.all(
      from p in RbacPolicy,
        where: p.user_id == ^user_id,
        order_by: [asc: p.resource_type, asc: p.action]
    )
  end

  def get_policy!(id), do: Repo.get!(RbacPolicy, id)

  def create_policy(attrs) do
    %RbacPolicy{}
    |> RbacPolicy.changeset(attrs)
    |> Repo.insert()
  end

  def update_policy(%RbacPolicy{} = policy, attrs) do
    policy
    |> RbacPolicy.changeset(attrs)
    |> Repo.update()
  end

  def delete_policy(%RbacPolicy{} = policy) do
    Repo.delete(policy)
  end

  def change_policy(%RbacPolicy{} = policy, attrs \\ %{}) do
    RbacPolicy.changeset(policy, attrs)
  end
end
