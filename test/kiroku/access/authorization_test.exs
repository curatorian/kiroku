defmodule Kiroku.Access.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Kiroku.Access.Authorization
  alias Kiroku.Accounts.User
  alias Kiroku.Repository.{Community, Collection, Item}

  defp user(type, id \\ Ecto.UUID.generate()) do
    %User{id: id, user_type: type}
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
end
