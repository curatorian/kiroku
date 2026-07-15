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

  def list_policies_for_user_by_resource(user_id, resource_type) do
    Repo.all(
      from p in RbacPolicy,
        where: p.user_id == ^user_id and p.resource_type == ^resource_type,
        order_by: [asc: p.action]
    )
  end

  def get_policy!(id), do: Repo.get!(RbacPolicy, id)

  def get_user_policy_for_resource(user_id, resource_type, resource_id) do
    resource_type_atom =
      if is_binary(resource_type), do: String.to_existing_atom(resource_type), else: resource_type

    Repo.one(
      from p in RbacPolicy,
        where:
          p.user_id == ^user_id and p.resource_type == ^resource_type_atom and
            p.resource_id == ^resource_id
    )
  rescue
    ArgumentError -> nil
  end

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

  def bulk_delete_user_policies(user_id) do
    from(p in RbacPolicy, where: p.user_id == ^user_id)
    |> Repo.delete_all()
  end

  def grant_area_access(user_id, resource_type, resource_id, action) do
    action_atom = if is_binary(action), do: String.to_existing_atom(action), else: action

    case get_user_policy_for_resource(user_id, resource_type, resource_id) do
      nil ->
        create_policy(%{
          "user_id" => user_id,
          "resource_type" => resource_type,
          "resource_id" => resource_id,
          "action" => action,
          "notes" => "Area access granted"
        })

      existing_policy ->
        if existing_policy.action != action_atom do
          update_policy(existing_policy, %{"action" => action})
        else
          {:ok, existing_policy}
        end
    end
  rescue
    ArgumentError -> {:error, "Invalid resource type or action"}
  end

  def revoke_area_access(user_id, resource_type, resource_id) do
    case get_user_policy_for_resource(user_id, resource_type, resource_id) do
      nil -> {:ok, nil}
      policy -> delete_policy(policy)
    end
  end
end
