defmodule Kiroku.Access.PolicyManager do
  @moduledoc """
  Manages RBAC default policies based on access_level.
  Call `apply_access_level/2` after creating or updating an item's access_level.
  """

  require Ash.Query

  alias Kiroku.Access.RbacPolicy
  alias Kiroku.Accounts.Group

  @doc """
  Apply default read policies based on access_level.
  Removes existing default read policies and creates new ones matching the level.
  """
  def apply_access_level(resource, access_level) do
    resource_type = resource_type_atom(resource)
    resource_id = resource.id

    anon_group = get_system_group!("ANONYMOUS")
    authed_group = get_system_group!("AUTHENTICATED")

    # Remove existing default read policies
    RbacPolicy
    |> Ash.Query.filter(
      resource_type == ^resource_type and
        resource_id == ^resource_id and
        action == :read and
        policy_type == :default
    )
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    case access_level do
      :open ->
        Ash.create!(
          RbacPolicy,
          %{
            resource_type: resource_type,
            resource_id: resource_id,
            group_id: anon_group.id,
            action: :read,
            policy_type: :default
          },
          authorize?: false
        )

      :restricted ->
        Ash.create!(
          RbacPolicy,
          %{
            resource_type: resource_type,
            resource_id: resource_id,
            group_id: authed_group.id,
            action: :read,
            policy_type: :default
          },
          authorize?: false
        )

      :closed ->
        :noop
    end
  end

  defp get_system_group!(name) do
    Group
    |> Ash.Query.filter(name == ^name)
    |> Ash.read_one!(authorize?: false)
  end

  defp resource_type_atom(%Kiroku.Repository.Community{}), do: :Community
  defp resource_type_atom(%Kiroku.Repository.Collection{}), do: :Collection
  defp resource_type_atom(%Kiroku.Repository.Item{}), do: :Item
  defp resource_type_atom(%Kiroku.Content.Bitstream{}), do: :Bitstream
end
