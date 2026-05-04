defmodule Kiroku.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @rand_size 32

  # Token validity windows
  @session_validity_in_days 60
  @confirm_validity_in_days 7
  @reset_password_validity_in_days 1
  @change_email_validity_in_days 7

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Kiroku.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed-secret cookie session.
  Returns {token_to_store_in_cookie, %UserToken{} to persist}.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Returns the token struct query for a session token.
  The token is valid for @session_validity_in_days days.
  """
  def verify_session_token_query(token) do
    query =
      from t in by_token_and_context_query(token, "session"),
        join: u in assoc(t, :user),
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        select: u

    {:ok, query}
  end

  @doc """
  Builds an email token and its hash to store in the DB.
  Returns {url-safe encoded token, %UserToken{}}.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks the token is valid and returns its underlying lookup query.
  The query returns the user found by the token, if any.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from t in by_token_and_context_query(hashed_token, context),
            join: u in assoc(t, :user),
            where: t.inserted_at > ago(^days, "day") and t.sent_to == u.email,
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context("change:" <> _), do: @change_email_validity_in_days

  @doc """
  Returns the token struct for the given token value and context.
  """
  def by_token_and_context_query(token, context) do
    from t in __MODULE__, where: t.token == ^token and t.context == ^context
  end

  @doc """
  Returns the given user's tokens for the given contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
