defmodule Kiroku.Onboarding do
  @moduledoc """
  First-run onboarding state.

  The application is in "setup mode" until the first-run wizard has been
  completed at least once. The state is derived from a DB-backed setting and
  cached in `:persistent_term` so that the guard plug does not hit the database
  on every request.

  Setup is considered complete when EITHER:
    - the `setup_complete` setting exists, OR
    - a superadmin user already exists (so existing seeded deployments are
      never accidentally locked into setup mode).

  The cache is sticky and only refreshed explicitly (via `mark_setup_complete/0`
  or `refresh_setup_state/0`). On a fresh restart the value is recomputed
  lazily on first access.
  """

  alias Kiroku.{Repo, Settings}
  alias Kiroku.Accounts.User

  import Ecto.Query

  @term_key {__MODULE__, :setup_complete}

  @doc "Returns true when onboarding has been completed."
  def setup_complete? do
    case :persistent_term.get(@term_key, :unknown) do
      :unknown -> refresh_setup_state()
      cached -> cached
    end
  end

  @doc "Returns true when the first-run wizard should be shown."
  def needs_setup?, do: not setup_complete?()

  @doc "Marks onboarding as complete and updates the in-memory cache."
  def mark_setup_complete do
    Settings.mark_setup_complete()
    :persistent_term.put(@term_key, true)
    :ok
  end

  @doc """
  Recomputes the setup state from the database and caches it.
  Useful after an external change (e.g. running seeds).
  """
  def refresh_setup_state do
    result = Settings.setup_complete?() or superadmin_exists?()
    :persistent_term.put(@term_key, result)
    result
  end

  @doc """
  Forces the cached setup state to a known value without touching the database.
  Intended for tests where the in-memory cache would otherwise interfere with
  sandboxed database state.
  """
  def force_setup_state(value) when is_boolean(value) do
    :persistent_term.put(@term_key, value)
    :ok
  end

  @doc "Returns whether any superadmin user exists."
  def superadmin_exists? do
    Repo.exists?(from u in User, where: u.user_type == :superadmin)
  end

  @doc """
  Creates the first superadmin user (auto-confirmed).
  Only permitted when no superadmin exists yet.
  """
  def create_first_superadmin(attrs) do
    if superadmin_exists?() do
      {:error, :superadmin_exists}
    else
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      %User{}
      |> User.registration_changeset(attrs)
      |> Ecto.Changeset.put_change(:user_type, :superadmin)
      |> Ecto.Changeset.put_change(:confirmed_at, now)
      |> Repo.insert()
    end
  end
end
