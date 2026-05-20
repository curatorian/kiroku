defmodule Kiroku.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @user_types ~w(submitter reviewer admin superadmin)a

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime

    field :user_type, Ecto.Enum, values: @user_types, default: :submitter
    field :display_name, :string
    field :identifier, :string
    field :faculty, :string
    field :department, :string
    field :avatar_url, :string

    has_many :items, Kiroku.Repository.Item, foreign_key: :submitter_id
    has_many :tokens, Kiroku.Accounts.UserToken

    timestamps()
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :display_name, :identifier, :faculty, :department])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc "Used by admins/superadmins to create or update a user — casts email and user_type."
  def admin_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :email,
      :password,
      :display_name,
      :user_type,
      :identifier,
      :faculty,
      :department,
      :avatar_url
    ])
    |> validate_email(opts)
    |> maybe_validate_and_hash_password(attrs)
    |> unique_identifier_constraint()
  end

  @doc "Used when creating a user from an OAuth provider without a local password."
  def oauth_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :display_name, :identifier, :faculty, :department, :avatar_url])
    |> validate_email(opts)
    |> unique_identifier_constraint()
    |> put_change(:hashed_password, random_hashed_password())
  end

  @doc "Used by admins/superadmins to forcefully set a new password without requiring the current one."
  def admin_set_password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password([])
  end

  @doc "Used by admins/superadmins to update role (user_type) only."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:user_type])
    |> validate_required([:user_type])
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :identifier, :faculty, :department, :avatar_url])
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 255)
    |> unique_identifier_constraint()
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  def confirm_changeset(user) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.
  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Kiroku.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  # Validates and hashes password only when a password was provided in attrs
  defp maybe_validate_and_hash_password(changeset, attrs) do
    if Map.has_key?(attrs, "password") and attrs["password"] != "" do
      changeset
      |> validate_password([])
    else
      changeset
    end
  end

  defp unique_identifier_constraint(changeset) do
    unique_constraint(changeset, :identifier)
  end

  defp random_hashed_password do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> Bcrypt.hash_pwd_salt()
  end
end
