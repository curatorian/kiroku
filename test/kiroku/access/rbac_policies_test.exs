defmodule Kiroku.Access.RbacPoliciesIntegrationTest do
  @moduledoc """
  Integration tests confirming a policy created in the DB round-trips through
  the context and into Authorization.can?/3 — i.e. the preload wiring at the
  auth boundary produces a user struct that can? actually consults.
  """
  use Kiroku.DataCase, async: true

  alias Kiroku.Access.{Authorization, RbacPolicies}
  alias Kiroku.Accounts.User
  alias Kiroku.Repository

  defp create_user do
    {:ok, user} =
      Kiroku.Accounts.register_user(%{
        "email" => "liaison-#{System.unique_integer([:positive])}@example.test",
        "password" => "password123456"
      })

    user
  end

  defp create_collection(attrs \\ %{}) do
    handle = "comm-#{System.unique_integer([:positive])}"

    {:ok, community} =
      Repository.create_community(%{"name" => "Community", "handle" => handle})

    {:ok, collection} =
      Repository.create_collection(
        Map.merge(
          %{
            "name" => "Collection",
            "community_id" => community.id,
            "handle" => "coll-#{System.unique_integer([:positive])}",
            "access_level" => "open"
          },
          attrs
        )
      )

    {community, collection}
  end

  defp create_item(collection_id, attrs \\ %{}) do
    {:ok, item} =
      Repository.create_item(
        Map.merge(
          %{
            "title" => "Test Item",
            "collection_id" => collection_id,
            "status" => "submitted",
            "access_level" => "restricted"
          },
          attrs
        )
      )

    item
  end

  # Rebuilds a user struct with policies loaded exactly as the auth plug does
  # (Accounts.get_user_by_session_token / ApiTokens.verify_token preload
  # :rbac_policies onto the fetched user).
  defp user_with_loaded_policies(%User{} = user) do
    policies = RbacPolicies.list_policies_for_user(user.id)
    %{user | rbac_policies: policies}
  end

  describe "policy round-trip through the DB" do
    test "a :review policy created in the DB empowers a submitter to review" do
      user = create_user()
      {_community, collection} = create_collection()
      item = create_item(collection.id)

      # Before the policy: a plain submitter cannot review.
      refute Authorization.can?(
               %User{id: user.id, user_type: :submitter},
               :review,
               item
             )

      {:ok, _policy} =
        RbacPolicies.create_policy(%{
          user_id: user.id,
          resource_type: :collection,
          resource_id: collection.id,
          action: :review
        })

      # Simulate the auth plug: load policies onto the user, then authorize.
      loaded = user_with_loaded_policies(user)

      assert Authorization.can?(loaded, :review, item)
    end

    test "a :read policy grants read on a restricted collection's items" do
      user = create_user()
      {_community, collection} = create_collection(%{"access_level" => "open"})

      item =
        create_item(collection.id, %{"status" => "published", "access_level" => "restricted"})

      {:ok, _policy} =
        RbacPolicies.create_policy(%{
          user_id: user.id,
          resource_type: :collection,
          resource_id: collection.id,
          action: :read
        })

      loaded = user_with_loaded_policies(user)

      assert Authorization.can?(loaded, :read, item)
    end

    test "deleting a policy removes the grant" do
      user = create_user()
      {_community, collection} = create_collection()
      item = create_item(collection.id)

      {:ok, policy} =
        RbacPolicies.create_policy(%{
          user_id: user.id,
          resource_type: :collection,
          resource_id: collection.id,
          action: :review
        })

      loaded = user_with_loaded_policies(user)
      assert Authorization.can?(loaded, :review, item)

      {:ok, _} = RbacPolicies.delete_policy(policy)

      reloaded = user_with_loaded_policies(user)
      refute Authorization.can?(reloaded, :review, item)
    end
  end
end
