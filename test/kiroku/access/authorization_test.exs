defmodule Kiroku.Access.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Kiroku.Access.Authorization
  alias Kiroku.Access.RbacPolicy
  alias Kiroku.Accounts.User
  alias Kiroku.Repository.{Community, Collection, Item}

  defp user(type, id \\ Ecto.UUID.generate()) do
    %User{id: id, user_type: type}
  end

  # A user carrying a list of in-memory policy grants (mirrors the preloaded
  # `:rbac_policies` association on a real authenticated request).
  defp user_with_policies(type, policies) do
    %User{id: Ecto.UUID.generate(), user_type: type, rbac_policies: policies}
  end

  defp policy(overrides) do
    struct!(
      RbacPolicy,
      Map.merge(%{action: :read, resource_type: :global, resource_id: nil}, overrides)
    )
  end

  defp community, do: %Community{}
  defp collection, do: %Collection{}

  defp item(attrs \\ %{}) do
    struct(Item, Map.merge(%{status: :published, access_level: :open, discoverable: true}, attrs))
  end

  # ── Superadmin ─────────────────────────────────────────────────────────────

  describe "superadmin" do
    test "can do anything" do
      superadmin = user(:superadmin)
      assert Authorization.can?(superadmin, :read, item())
      assert Authorization.can?(superadmin, :create, community())
      assert Authorization.can?(superadmin, :delete, item())
      assert Authorization.can?(superadmin, :manage_users, :global)
    end
  end

  # ── Community ──────────────────────────────────────────────────────────────

  describe "community permissions" do
    test "superadmin can CRUD" do
      superadmin = user(:superadmin)
      assert Authorization.can?(superadmin, :read, community())
      assert Authorization.can?(superadmin, :create, community())
      assert Authorization.can?(superadmin, :update, community())
      assert Authorization.can?(superadmin, :delete, community())
    end

    test "admin can only read (management is superadmin-only)" do
      admin = user(:admin)
      assert Authorization.can?(admin, :read, community())
      refute Authorization.can?(admin, :create, community())
      refute Authorization.can?(admin, :update, community())
      refute Authorization.can?(admin, :delete, community())
    end

    test "submitter can only read" do
      submitter = user(:submitter)
      assert Authorization.can?(submitter, :read, community())
      refute Authorization.can?(submitter, :create, community())
      refute Authorization.can?(submitter, :update, community())
    end
  end

  # ── Collection ─────────────────────────────────────────────────────────────

  describe "collection permissions" do
    test "admin can CRUD" do
      admin = user(:admin)
      assert Authorization.can?(admin, :create, collection())
      assert Authorization.can?(admin, :update, collection())
      assert Authorization.can?(admin, :delete, collection())
    end

    test "submitter can only read" do
      submitter = user(:submitter)
      assert Authorization.can?(submitter, :read, collection())
      refute Authorization.can?(submitter, :create, collection())
    end
  end

  # ── Community & Collection read visibility ─────────────────────────────────

  describe "community read visibility" do
    test "open community readable by anyone" do
      assert Authorization.can?(nil, :read, %Community{access_level: :open})
      assert Authorization.can?(user(:submitter), :read, %Community{access_level: :open})
    end

    test "internal community hidden from anonymous, visible to logged-in" do
      c = %Community{access_level: :internal}
      refute Authorization.can?(nil, :read, c)
      assert Authorization.can?(user(:submitter), :read, c)
      assert Authorization.can?(user(:admin), :read, c)
    end

    test "restricted community staff-only" do
      c = %Community{access_level: :restricted}
      refute Authorization.can?(nil, :read, c)
      refute Authorization.can?(user(:internal), :read, c)
      assert Authorization.can?(user(:reviewer), :read, c)
    end

    test "inactive community staff-only" do
      c = %Community{is_active: false}
      refute Authorization.can?(nil, :read, c)
      refute Authorization.can?(user(:internal), :read, c)
      assert Authorization.can?(user(:admin), :read, c)
    end
  end

  describe "collection read visibility" do
    test "internal collection hidden from anonymous" do
      c = %Collection{access_level: :internal}
      refute Authorization.can?(nil, :read, c)
      assert Authorization.can?(user(:internal), :read, c)
    end

    test "closed collection staff-only" do
      c = %Collection{access_level: :closed}
      refute Authorization.can?(nil, :read, c)
      refute Authorization.can?(user(:submitter), :read, c)
      assert Authorization.can?(user(:admin), :read, c)
    end

    test "inactive collection staff-only" do
      c = %Collection{is_active: false}
      refute Authorization.can?(nil, :read, c)
      assert Authorization.can?(user(:reviewer), :read, c)
    end
  end

  # ── Item read ──────────────────────────────────────────────────────────────

  describe "item read permissions" do
    test "published open item readable by anyone" do
      assert Authorization.can?(user(:submitter), :read, item())
      assert Authorization.can?(nil, :read, item())
    end

    test "reviewer can read any item" do
      reviewer = user(:reviewer)
      assert Authorization.can?(reviewer, :read, item(%{status: :draft}))
      assert Authorization.can?(reviewer, :read, item(%{status: :under_review}))
    end

    test "submitter can read own item" do
      uid = Ecto.UUID.generate()
      submitter = user(:submitter, uid)
      own_item = item(%{submitter_id: uid, status: :draft})
      assert Authorization.can?(submitter, :read, own_item)
    end

    test "submitter cannot read others' draft" do
      submitter = user(:submitter)
      others_draft = item(%{submitter_id: Ecto.UUID.generate(), status: :draft})
      refute Authorization.can?(submitter, :read, others_draft)
    end

    test "published :internal item hidden from anonymous, visible to logged-in" do
      internal_item = item(%{access_level: :internal})

      refute Authorization.can?(nil, :read, internal_item)
      assert Authorization.can?(user(:submitter), :read, internal_item)
      assert Authorization.can?(user(:internal), :read, internal_item)
      assert Authorization.can?(user(:reviewer), :read, internal_item)
    end

    test "published :restricted item only visible to staff" do
      restricted = item(%{access_level: :restricted})

      refute Authorization.can?(nil, :read, restricted)
      refute Authorization.can?(user(:submitter), :read, restricted)
      refute Authorization.can?(user(:internal), :read, restricted)
      assert Authorization.can?(user(:reviewer), :read, restricted)
      assert Authorization.can?(user(:admin), :read, restricted)
    end

    test "published :closed item only visible to staff" do
      closed = item(%{access_level: :closed})

      refute Authorization.can?(nil, :read, closed)
      refute Authorization.can?(user(:internal), :read, closed)
      assert Authorization.can?(user(:admin), :read, closed)
    end

    test "internal user can read non-published items" do
      internal = user(:internal)
      assert Authorization.can?(internal, :read, item(%{status: :draft}))
      assert Authorization.can?(internal, :read, item(%{status: :submitted}))
    end
  end

  # ── Visibility scope ──────────────────────────────────────────────────────

  describe "visibility_scope/1" do
    test "nil user is public" do
      assert Authorization.visibility_scope(nil) == :public
    end

    test "submitter and internal are internal scope" do
      assert Authorization.visibility_scope(user(:submitter)) == :internal
      assert Authorization.visibility_scope(user(:internal)) == :internal
    end

    test "reviewer, admin, superadmin are staff scope" do
      assert Authorization.visibility_scope(user(:reviewer)) == :staff
      assert Authorization.visibility_scope(user(:admin)) == :staff
      assert Authorization.visibility_scope(user(:superadmin)) == :staff
    end
  end

  describe "visible_access_levels/1" do
    test "public sees only open" do
      assert Authorization.visible_access_levels(:public) == [:open]
    end

    test "internal sees open and internal" do
      assert Authorization.visible_access_levels(:internal) == [:open, :internal]
    end

    test "staff sees all levels" do
      assert Authorization.visible_access_levels(:staff) ==
               [:open, :internal, :restricted, :closed]
    end
  end

  # ── Item create ────────────────────────────────────────────────────────────

  describe "item create permissions" do
    test "submitter can create" do
      assert Authorization.can?(user(:submitter), :create, item())
    end

    test "admin can create" do
      assert Authorization.can?(user(:admin), :create, item())
    end
  end

  # ── Item update ────────────────────────────────────────────────────────────

  describe "item update permissions" do
    test "submitter can update own draft" do
      uid = Ecto.UUID.generate()
      submitter = user(:submitter, uid)
      own_draft = item(%{submitter_id: uid, status: :draft})
      assert Authorization.can?(submitter, :update, own_draft)
    end

    test "submitter can update own submitted item" do
      uid = Ecto.UUID.generate()
      submitter = user(:submitter, uid)
      own = item(%{submitter_id: uid, status: :submitted})
      assert Authorization.can?(submitter, :update, own)
    end

    test "submitter cannot update own published item" do
      uid = Ecto.UUID.generate()
      submitter = user(:submitter, uid)
      own_published = item(%{submitter_id: uid, status: :published})
      refute Authorization.can?(submitter, :update, own_published)
    end

    test "admin can update any item" do
      admin = user(:admin)
      assert Authorization.can?(admin, :update, item(%{status: :published}))
    end
  end

  # ── Workflow actions ───────────────────────────────────────────────────────

  describe "workflow actions" do
    test "reviewer can review, publish, withdraw, lift_embargo" do
      reviewer = user(:reviewer)
      assert Authorization.can?(reviewer, :review, item())
      assert Authorization.can?(reviewer, :publish, item())
      assert Authorization.can?(reviewer, :withdraw, item())
      assert Authorization.can?(reviewer, :lift_embargo, item())
    end

    test "submitter cannot perform workflow actions" do
      submitter = user(:submitter)
      refute Authorization.can?(submitter, :review, item())
      refute Authorization.can?(submitter, :publish, item())
      refute Authorization.can?(submitter, :withdraw, item())
    end
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  describe "item delete permissions" do
    test "admin can delete" do
      assert Authorization.can?(user(:admin), :delete, item())
    end

    test "reviewer cannot delete" do
      refute Authorization.can?(user(:reviewer), :delete, item())
    end
  end

  # ── Catch-all ──────────────────────────────────────────────────────────────

  describe "catch-all" do
    test "unknown action denied" do
      refute Authorization.can?(user(:admin), :unknown_action, item())
    end

    test "nil user denied for non-public" do
      refute Authorization.can?(nil, :create, item())
      refute Authorization.can?(nil, :update, item())
    end
  end

  # ── RBAC policy grants ─────────────────────────────────────────────────────

  describe "RBAC policy grants — item read" do
    test "collection-scoped :read policy grants read on a restricted item" do
      coll_id = Ecto.UUID.generate()

      restricted =
        item(%{collection_id: coll_id, access_level: :restricted})

      submitter =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :collection,
            resource_id: coll_id,
            action: :read
          })
        ])

      # Without the policy a submitter cannot read a restricted item.
      refute Authorization.can?(user(:submitter), :read, restricted)
      # With the policy, they can.
      assert Authorization.can?(submitter, :read, restricted)
    end

    test "policy on one collection does not leak into another" do
      coll_a = Ecto.UUID.generate()
      coll_b = Ecto.UUID.generate()

      item_b = item(%{collection_id: coll_b, access_level: :restricted})

      submitter =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :collection,
            resource_id: coll_a,
            action: :read
          })
        ])

      refute Authorization.can?(submitter, :read, item_b)
    end

    test "item-scoped :read policy grants read on that specific item" do
      item_id = Ecto.UUID.generate()
      closed = item(%{id: item_id, access_level: :closed})

      submitter =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :item,
            resource_id: item_id,
            action: :read
          })
        ])

      assert Authorization.can?(submitter, :read, closed)
    end
  end

  describe "RBAC policy grants — workflow actions" do
    test "collection-scoped :review policy grants review on items in it" do
      coll_id = Ecto.UUID.generate()
      item_in_coll = item(%{collection_id: coll_id, status: :submitted})

      liaison =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :collection,
            resource_id: coll_id,
            action: :review
          })
        ])

      # A plain submitter cannot review.
      refute Authorization.can?(user(:submitter), :review, item_in_coll)
      # The liaison can review, withdraw, and lift embargo.
      assert Authorization.can?(liaison, :review, item_in_coll)
      assert Authorization.can?(liaison, :withdraw, item_in_coll)
      assert Authorization.can?(liaison, :lift_embargo, item_in_coll)
    end

    test ":review policy does not grant :publish" do
      coll_id = Ecto.UUID.generate()
      item_in_coll = item(%{collection_id: coll_id})

      liaison =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :collection,
            resource_id: coll_id,
            action: :review
          })
        ])

      refute Authorization.can?(liaison, :publish, item_in_coll)
    end

    test ":manage policy grants every workflow action" do
      coll_id = Ecto.UUID.generate()
      item_in_coll = item(%{collection_id: coll_id})

      manager =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :collection,
            resource_id: coll_id,
            action: :manage
          })
        ])

      assert Authorization.can?(manager, :review, item_in_coll)
      assert Authorization.can?(manager, :publish, item_in_coll)
      assert Authorization.can?(manager, :withdraw, item_in_coll)
      assert Authorization.can?(manager, :read, item_in_coll)
    end
  end

  describe "RBAC policy grants — hierarchy" do
    test "community-scoped policy covers collections in that community" do
      comm_id = Ecto.UUID.generate()

      coll = %Collection{
        id: Ecto.UUID.generate(),
        community_id: comm_id,
        access_level: :restricted
      }

      viewer =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :community,
            resource_id: comm_id,
            action: :read
          })
        ])

      assert Authorization.can?(viewer, :read, coll)
    end

    test "community-scoped policy covers an item when its collection is preloaded" do
      comm_id = Ecto.UUID.generate()
      coll_id = Ecto.UUID.generate()

      item_with_collection =
        item(%{
          collection_id: coll_id,
          access_level: :restricted,
          collection: %Collection{id: coll_id, community_id: comm_id}
        })

      viewer =
        user_with_policies(:submitter, [
          policy(%{
            resource_type: :community,
            resource_id: comm_id,
            action: :read
          })
        ])

      assert Authorization.can?(viewer, :read, item_with_collection)
    end

    test "global :read policy grants read on any resource" do
      viewer = user_with_policies(:submitter, [policy(%{action: :read, resource_type: :global})])

      assert Authorization.can?(viewer, :read, item(%{access_level: :closed}))
      assert Authorization.can?(viewer, :read, %Collection{access_level: :restricted})
    end
  end

  describe "RBAC policy — additive only" do
    test "policy never revokes an existing role grant" do
      admin = user_with_policies(:admin, [])
      assert Authorization.can?(admin, :read, item())
    end

    test "user with no policies behaves as before" do
      refute Authorization.can?(user(:submitter), :publish, item())
    end
  end
end
