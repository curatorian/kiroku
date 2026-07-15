defmodule Kiroku.Access.Authorization do
  @moduledoc """
  Role-based authorization. Single `can?/3` entry point.
  Usage:
      if Authorization.can?(current_user, :publish, item) do ... end

  The third argument can be a struct or a bare atom (:global) for
  non-resource actions.

  ## Two layers of authorization

  1. **Role rules** — hardcoded clauses keyed on `user_type` (the fast path).
     These establish the baseline: what a submitter/internal/reviewer/admin can
     do anywhere.
  2. **RBAC policies** — per-user grants stored in `rbac_policies` and preloaded
     onto `%User{rbac_policies: [...]}` at the auth boundary. A policy can only
     *grant additional* access, never revoke it. This is how a faculty liaison,
     for example, can be empowered to review items in one specific collection
     without being promoted to a global `:reviewer`.

  Resource matching honours the repository hierarchy: a policy on a community
  or collection covers the items within it (collection→items via `collection_id`,
  community→items via the collection's `community_id` when preloaded).
  """

  alias Kiroku.Repository.{Community, Collection, Item}
  alias Kiroku.Accounts.User
  alias Kiroku.Access.{RbacPolicy, RolePolicy, RolePolicies}

  # ── Visibility scope ──────────────────────────────────────────────────────────
  #
  # A "visibility scope" is the maximum access tier a viewer may see, derived
  # from their role. It drives item discovery filtering (listings/search) and
  # the published-item read check. The three tiers map to the repository's
  # public / internal / private model:
  #
  #   :public  — anonymous visitor         → sees :open items only
  #   :internal — any logged-in user        → sees :open + :internal items
  #   :staff    — reviewer/admin/superadmin → sees every access level

  @doc "Returns the visibility scope for a user (or nil for anonymous)."
  def visibility_scope(%User{user_type: type}) when type in [:reviewer, :admin, :superadmin],
    do: :staff

  def visibility_scope(%User{user_type: type}) when type in [:internal, :submitter],
    do: :internal

  def visibility_scope(_user), do: :public

  @doc """
  Returns the list of `access_level` atoms visible to the given scope.

      visible_access_levels(:public)  ~> [:open]
      visible_access_levels(:internal) ~> [:open, :internal]
      visible_access_levels(:staff)    ~> [:open, :internal, :restricted, :closed]
  """
  def visible_access_levels(:staff), do: [:open, :internal, :restricted, :closed]
  def visible_access_levels(:internal), do: [:open, :internal]
  def visible_access_levels(:public), do: [:open]
  def visible_access_levels(_other), do: [:open]

  # Superadmin may do anything
  def can?(%User{user_type: :superadmin}, _action, _resource), do: true

  # ── Community CRUD (superadmin only) ─────────────────────────────────────────
  #
  # Community management — including the hierarchical structure — is restricted
  # to superadmins. Admins and below may only read.
  #
  # Read access is gated by `is_active` and `access_level`: an inactive or
  # non-open community is hidden from public/internal viewers (both in browse
  # listings and on direct handle access).

  def can?(user, :read, %Community{is_active: false} = community),
    do: visibility_scope(user) == :staff or policy_allows?(user, :read, community)

  def can?(user, :read, %Community{} = community),
    do:
      community.access_level in visible_access_levels(visibility_scope(user)) or
        policy_allows?(user, :read, community)

  # ── Collection CRUD ───────────────────────────────────────────────────────────

  def can?(%User{user_type: type}, action, %Collection{})
      when type in [:admin] and action in [:create, :update, :delete] do
    true
  end

  def can?(%User{user_type: :admin}, :read, %Collection{}), do: true

  def can?(user, :read, %Collection{is_active: false} = collection),
    do: visibility_scope(user) == :staff or policy_allows?(user, :read, collection)

  def can?(user, :read, %Collection{} = collection),
    do:
      collection.access_level in visible_access_levels(visibility_scope(user)) or
        policy_allows?(user, :read, collection)

  # ── Item read ─────────────────────────────────────────────────────────────────
  #
  # Published items are gated by `access_level` according to the viewer's scope
  # (public / internal / staff). This is what prevents a :closed or :restricted
  # item's metadata from leaking to anonymous or non-staff viewers.

  def can?(user, :read, %Item{status: :published, discoverable: true} = item) do
    item.access_level in visible_access_levels(visibility_scope(user)) or
      policy_allows?(user, :read, item)
  end

  # Non-published items (draft, submitted, under_review, embargoed, withdrawn)
  # are readable by internal users and staff. The `status != :published` guard
  # is essential: without it this clause would re-grant access to published
  # items that the access_level check above just denied.
  def can?(%User{user_type: type}, :read, %Item{status: status})
      when type in [:internal, :reviewer, :admin] and status != :published do
    true
  end

  def can?(%User{id: user_id}, :read, %Item{submitter_id: submitter_id})
      when user_id == submitter_id do
    true
  end

  # ── Item create ───────────────────────────────────────────────────────────────

  def can?(%User{user_type: type}, :create, %Item{})
      when type in [:submitter, :admin] do
    true
  end

  # ── Item update (own draft/submitted) ─────────────────────────────────────────

  def can?(%User{id: user_id, user_type: :submitter}, :update, %Item{
        submitter_id: submitter_id,
        status: status
      })
      when user_id == submitter_id and status in [:draft, :submitted] do
    true
  end

  def can?(%User{user_type: :admin}, :update, %Item{}), do: true

  # ── Workflow actions (review, publish, withdraw, lift_embargo) ────────────────

  def can?(%User{user_type: type}, action, %Item{})
      when type in [:reviewer, :admin] and
             action in [:review, :publish, :withdraw, :lift_embargo] do
    true
  end

  # ── Delete item ───────────────────────────────────────────────────────────────

  def can?(%User{user_type: :admin}, :delete, %Item{}), do: true

  # ── Global / administrative actions ──────────────────────────────────────────

  def can?(%User{user_type: :admin}, action, :global)
      when action in [:manage_users, :manage_communities, :manage_collections] do
    true
  end

  # ── Catch-all / RBAC policy fallback ─────────────────────────────────────────
  #
  # Anything not matched by a role rule above is denied — unless an explicit
  # RBAC policy grants it. Two layers of policy are checked:
  #
  # 1. **Role policies** — stored in `role_policies` and keyed on `user_type`.
  #    These apply to every user with that role (e.g. "all reviewers can read
  #    items in collection X"). They are fetched from the DB on demand since
  #    they are only needed on authorization misses (the slow path).
  # 2. **Per-user policies** — stored in `rbac_policies` and preloaded onto the
  #    user struct at the auth boundary. These grant additional access to a
  #    specific individual.

  def can?(%User{} = user, action, resource) do
    role_policy_allows?(user.user_type, action, resource) or
      policy_allows?(user, action, resource)
  end

  def can?(_user, _action, _resource), do: false

  # ── Role policy evaluation ──────────────────────────────────────────────────
  #
  # Role policies are fetched from the DB (not preloaded on the user) because
  # they are keyed on user_type, not user_id. They are only evaluated on the
  # slow path (when role rules don't already grant access), so the DB hit is
  # acceptable.

  defp role_policy_allows?(user_type, action, resource) do
    RolePolicies.cached_policies_for_type(user_type)
    |> Enum.any?(&role_policy_matches?(&1, action, resource))
  end

  defp role_policy_matches?(%RolePolicy{} = policy, action, resource) do
    action_grants?(policy.action, action) and resource_matches?(policy, resource)
  end

  # ── Per-user RBAC policy evaluation ─────────────────────────────────────────
  #
  # Policies are preloaded onto the user as a list (`%User{rbac_policies: [...]}`).
  # When the association is not loaded (e.g. bare structs in unit tests, or code
  # paths that didn't preload), there are no custom grants and this returns false.

  defp policy_allows?(%User{rbac_policies: policies}, action, resource)
       when is_list(policies) do
    Enum.any?(policies, &policy_matches?(&1, action, resource))
  end

  defp policy_allows?(_user, _action, _resource), do: false

  defp policy_matches?(%RbacPolicy{} = policy, action, resource) do
    action_grants?(policy.action, action) and resource_matches?(policy, resource)
  end

  # :manage is a wildcard — it grants every action on the scoped resource.
  defp action_grants?(:manage, _action), do: true

  defp action_grants?(:review, action) when action in [:review, :withdraw, :lift_embargo],
    do: true

  defp action_grants?(:publish, :publish), do: true
  defp action_grants?(:submit, :create), do: true
  defp action_grants?(:read, :read), do: true
  defp action_grants?(_policy_action, _requested), do: false

  # A policy's resource scope matches when it is global, or points at the
  # resource itself, its parent collection, or its parent community. UUIDs are
  # binaries; nil resource_ids never match a specific resource.
  defp resource_matches?(%RbacPolicy{resource_type: :global}, _resource), do: true

  defp resource_matches?(%RbacPolicy{resource_type: :item, resource_id: rid}, %Item{id: id})
       when is_binary(rid) and is_binary(id),
       do: rid == id

  defp resource_matches?(
         %RbacPolicy{resource_type: :collection, resource_id: rid},
         %Item{collection_id: cid}
       )
       when is_binary(rid) and is_binary(cid),
       do: rid == cid

  defp resource_matches?(
         %RbacPolicy{resource_type: :collection, resource_id: rid},
         %Collection{id: id}
       )
       when is_binary(rid) and is_binary(id),
       do: rid == id

  defp resource_matches?(
         %RbacPolicy{resource_type: :community, resource_id: rid},
         %Collection{community_id: cmid}
       )
       when is_binary(rid) and is_binary(cmid),
       do: rid == cmid

  defp resource_matches?(%RbacPolicy{resource_type: :community, resource_id: rid}, %Community{
         id: id
       })
       when is_binary(rid) and is_binary(id),
       do: rid == id

  # Item → community, but only when the item's collection is preloaded.
  defp resource_matches?(
         %RbacPolicy{resource_type: :community, resource_id: rid},
         %Item{collection: %Collection{community_id: cmid}}
       )
       when is_binary(rid) and is_binary(cmid),
       do: rid == cmid

  defp resource_matches?(_policy, _resource), do: false
end
