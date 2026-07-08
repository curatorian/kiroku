defmodule Kiroku.Accounts do
  @moduledoc """
  The Accounts context.
  Follows the phx.gen.auth pattern: tokens are persisted in `users_tokens`,
  and the user password is hashed with bcrypt.
  """

  alias Kiroku.Repo
  alias Kiroku.Accounts.{User, UserToken, UserNotifier}

  def list_users do
    Repo.all(User)
  end

  def list_users_with_policies do
    import Ecto.Query
    Repo.all(from u in User, order_by: [asc: u.user_type, asc: u.email])
  end

  @doc """
  Paginated version of `list_users_with_policies/0`.
  Returns `{users, %Kiroku.Pagination{}}`.

  Pass `:type` to filter by `user_type` (e.g. `"admin"`, `"submitter"`).
  Pass `"all"` or `nil` for no type filter.
  """
  def list_users_with_policies_pagination(opts \\ []) do
    import Ecto.Query
    alias Kiroku.Pagination

    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    type = Keyword.get(opts, :type)

    base_query = user_type_query(type)

    count = Repo.aggregate(base_query, :count, :id)
    pagination = Pagination.build(count, page, per_page)

    users =
      Repo.all(
        from u in base_query,
          order_by: [asc: u.user_type, asc: u.email],
          limit: ^per_page,
          offset: ^Pagination.offset(pagination)
      )

    {users, pagination}
  end

  defp user_type_query(nil), do: User

  defp user_type_query("all"), do: User

  defp user_type_query(type) when is_binary(type) do
    import Ecto.Query
    from(u in User, where: u.user_type == ^String.to_existing_atom(type))
  end

  def list_admins do
    import Ecto.Query
    Repo.all(from u in User, where: u.user_type in [:admin, :superadmin])
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  def admin_create_user(attrs) do
    %User{}
    |> User.admin_changeset(attrs)
    |> Ecto.Changeset.put_change(
      :confirmed_at,
      NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    )
    |> Repo.insert()
  end

  def create_user_from_oauth(attrs) do
    %User{}
    |> User.oauth_changeset(attrs)
    |> Ecto.Changeset.put_change(
      :confirmed_at,
      NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    )
    |> Repo.insert()
  end

  @doc """
  Promotes a user to the :internal role (students/lecturers).
  Used by PAuS OAuth — only callers should ensure the user doesn't already
  have a higher role (admin/reviewer/superadmin) before calling this.
  """
  def assign_internal_role(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{user_type: :internal})
    |> Repo.update()
  end

  def admin_update_user(%User{} = user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  def admin_set_password(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.admin_set_password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def admin_change_role(%User{} = user, attrs) do
    user
    |> User.role_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  # Legacy kept for compatibility — delegates to admin_update_user
  def admin_update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  # ── Fetching users ───────────────────────────────────────────────────────────

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  # ── Registration ─────────────────────────────────────────────────────────────

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  # ── Profile updates ──────────────────────────────────────────────────────────

  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  # ── Email changes ────────────────────────────────────────────────────────────

  def apply_user_email(%User{} = user, password, attrs) do
    if User.valid_password?(user, password) do
      user
      |> User.email_changeset(attrs)
      |> Ecto.Changeset.apply_action(:update)
    else
      {:error,
       Ecto.Changeset.add_error(
         User.email_changeset(user, attrs),
         :current_password,
         "is not valid"
       )}
    end
  end

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_email_token_query(token, context),
         %User{} = user_to_update <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user_to_update, token, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, _token, context) do
    changeset = user |> User.email_changeset(%{}) |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, [context])
    )
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, url_fun)
      when is_function(url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(%{user | email: current_email}, "change:#{user.email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, url_fun.(encoded_token))
  end

  # ── Email confirmation ────────────────────────────────────────────────────────

  def get_user_by_email_and_password_for_confirmation(email, password) do
    get_user_by_email_and_password(email, password)
  end

  def deliver_user_confirmation_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, url_fun.(encoded_token))
    end
  end

  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"])
    )
  end

  # ── Password resets ───────────────────────────────────────────────────────────

  def deliver_user_reset_password_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, url_fun.(encoded_token))
  end

  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # ── Session tokens ────────────────────────────────────────────────────────────

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
