defmodule Kiroku.Access.Authorization do
  @moduledoc """
  Role-based authorization. Single `can?/3` entry point.
  Usage:
      if Authorization.can?(current_user, :publish, item) do ... end

  The third argument can be a struct or a bare atom (:global) for
  non-resource actions.
  """

  alias Kiroku.Repository.{Community, Collection, Item}
  alias Kiroku.Accounts.User

  # Superadmin may do anything
  def can?(%User{user_type: :superadmin}, _action, _resource), do: true

  # ── Community CRUD (superadmin only) ─────────────────────────────────────────
  #
  # Community management — including the hierarchical structure — is restricted
  # to superadmins. Admins and below may only read.

  def can?(_user, :read, %Community{}), do: true

  # ── Collection CRUD ───────────────────────────────────────────────────────────

  def can?(%User{user_type: type}, action, %Collection{})
      when type in [:admin] and action in [:read, :create, :update, :delete] do
    true
  end

  def can?(_user, :read, %Collection{}), do: true

  # ── Item read ─────────────────────────────────────────────────────────────────

  def can?(_user, :read, %Item{status: :published, discoverable: true}), do: true

  def can?(%User{user_type: type}, :read, %Item{})
      when type in [:internal, :reviewer, :admin] do
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

  # ── Catch-all ─────────────────────────────────────────────────────────────────

  def can?(_user, _action, _resource), do: false
end
