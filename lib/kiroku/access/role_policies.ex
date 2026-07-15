defmodule Kiroku.Access.RolePolicies do
  @moduledoc "Context for managing role-scoped RBAC policies."

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Access.RolePolicy

  @cache_key __MODULE__

  @doc """
  Loads all role policies from the DB and caches them in :persistent_term
  keyed by user_type. Call on application start and after any policy change.
  """
  def refresh_cache do
    all = list_role_policies()

    grouped =
      Enum.group_by(all, & &1.user_type, & &1)

    :persistent_term.put(@cache_key, grouped)
    :ok
  end

  @doc """
  Returns cached role policies for the given user_type.
  Returns [] when the cache has not been initialised (e.g. in unit tests
  that don't touch the database).
  """
  def cached_policies_for_type(user_type) when is_atom(user_type) do
    case :persistent_term.get(@cache_key, %{}) do
      %{^user_type => policies} -> policies
      _ -> []
    end
  end

  def list_role_policies do
    Repo.all(
      from p in RolePolicy,
        order_by: [asc: p.user_type, asc: p.resource_type, asc: p.action]
    )
  end

  def list_policies_for_user_type(user_type) do
    Repo.all(
      from p in RolePolicy,
        where: p.user_type == ^user_type,
        order_by: [asc: p.resource_type, asc: p.action]
    )
  end

  def get_role_policy!(id), do: Repo.get!(RolePolicy, id)

  def create_role_policy(attrs) do
    with {:ok, policy} <- %RolePolicy{} |> RolePolicy.changeset(attrs) |> Repo.insert() do
      refresh_cache()
      {:ok, policy}
    end
  end

  def update_role_policy(%RolePolicy{} = policy, attrs) do
    with {:ok, policy} <- policy |> RolePolicy.changeset(attrs) |> Repo.update() do
      refresh_cache()
      {:ok, policy}
    end
  end

  def delete_role_policy(%RolePolicy{} = policy) do
    with {:ok, policy} <- Repo.delete(policy) do
      refresh_cache()
      {:ok, policy}
    end
  end

  def change_role_policy(%RolePolicy{} = policy, attrs \\ %{}) do
    RolePolicy.changeset(policy, attrs)
  end

  @doc """
  Loads all role policies that apply to a given `user_type` atom from the DB.
  """
  def policies_for_type(user_type) when is_atom(user_type) do
    Repo.all(from p in RolePolicy, where: p.user_type == ^user_type)
  end
end
