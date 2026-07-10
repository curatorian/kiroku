defmodule Kiroku.ApiTokens do
  @moduledoc """
  API token lifecycle management.

  Tokens are SHA256-hashed before storage so the raw value is never persisted.
  The raw token is only returned once at creation/rotation time and must be
  shown to the user immediately — it cannot be retrieved later.
  """

  import Ecto.Query

  alias Kiroku.{ApiToken, Accounts.User, Repo}

  @prefix "kiroku_"
  @rand_size 32
  @hash_algorithm :sha256

  # ── Queries ──────────────────────────────────────────────────────────────

  @doc """
  Lists all API tokens for a user, newest first.
  Token hashes are not included in the returned data (they're internal).
  """
  def list_tokens(user_id) do
    ApiToken
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  # ── Create ───────────────────────────────────────────────────────────────

  @doc """
  Creates a new API token for the given user.

  Returns `{:ok, raw_token, api_token}` where `raw_token` is the un-hashed
  string the caller must store (shown once). The stored record contains only
  the hash.
  """
  def create_token(%User{} = user, name) do
    raw_token = generate_raw_token()
    token_hash = hash_token(raw_token)

    %ApiToken{}
    |> ApiToken.changeset(%{name: name, token_hash: token_hash, user_id: user.id})
    |> Repo.insert()
    |> case do
      {:ok, api_token} -> {:ok, raw_token, api_token}
      error -> error
    end
  end

  # ── Rotate ───────────────────────────────────────────────────────────────

  @doc """
  Generates a new raw token for an existing API token record, replacing the
  old hash. The old token immediately stops working.

  Returns `{:ok, raw_token, api_token}`.
  """
  def rotate_token(token_id) do
    raw_token = generate_raw_token()
    token_hash = hash_token(raw_token)

    ApiToken
    |> Repo.get(token_id)
    |> case do
      nil ->
        {:error, :not_found}

      api_token ->
        api_token
        |> ApiToken.changeset(%{token_hash: token_hash})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, raw_token, updated}
          error -> error
        end
    end
  end

  # ── Delete ───────────────────────────────────────────────────────────────

  @doc """
  Deletes an API token. The token immediately stops working.
  """
  def delete_token(token_id) do
    ApiToken
    |> Repo.get(token_id)
    |> case do
      nil -> {:error, :not_found}
      api_token -> Repo.delete(api_token)
    end
  end

  # ── Verify ───────────────────────────────────────────────────────────────

  @doc """
  Verifies a raw token string against the stored hashes.

  Returns `{:ok, user}` on success (and updates `last_used_at`), or
  `{:error, :invalid}` if the token does not match.
  """
  def verify_token(nil), do: {:error, :invalid}

  def verify_token(raw_token) when is_binary(raw_token) do
    token_hash = hash_token(raw_token)

    ApiToken
    |> where([t], t.token_hash == ^token_hash)
    |> join(:inner, [t], u in User, on: u.id == t.user_id)
    |> select([t, u], {t, u})
    |> Repo.one()
    |> case do
      nil ->
        {:error, :invalid}

      {api_token, user} ->
        update_last_used(api_token)
        {:ok, user}
    end
  end

  defp update_last_used(api_token) do
    api_token
    |> ApiToken.changeset(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp generate_raw_token do
    @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)
  end

  defp hash_token(raw_token) do
    :crypto.hash(@hash_algorithm, raw_token)
  end
end
