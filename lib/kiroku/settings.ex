defmodule Kiroku.Settings do
  @moduledoc """
  Context for runtime system settings stored in the database.
  Settings can be overridden by environment variables; DB values take precedence.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Settings.SystemSetting

  @doc """
  Gets a setting value by key. Returns nil if not set.
  """
  def get(key) when is_binary(key) do
    case Repo.get_by(SystemSetting, key: key) do
      nil -> nil
      setting -> setting.value
    end
  end

  @doc """
  Gets a setting value by key with a fallback default.
  """
  def get(key, default) when is_binary(key) do
    get(key) || default
  end

  @doc """
  Sets (upserts) a setting value.
  """
  def put(key, value, description \\ nil) do
    case Repo.get_by(SystemSetting, key: key) do
      nil ->
        %SystemSetting{}
        |> SystemSetting.changeset(%{key: key, value: value, description: description})
        |> Repo.insert()

      existing ->
        existing
        |> SystemSetting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Returns all settings as a list.
  """
  def list_settings do
    Repo.all(from s in SystemSetting, order_by: s.key)
  end

  # ── Storage-specific helpers ───────────────────────────────────────────────

  @doc """
  Returns the storage adapter: :s3 or :local.
  Priority: DB setting → STORAGE_ADAPTER env var → :local (default).
  """
  def storage_adapter do
    db_val = get("storage_adapter")
    env_val = System.get_env("STORAGE_ADAPTER")

    case db_val || env_val do
      "s3" ->
        :s3

      "local" ->
        :local

      nil ->
        :local

      other ->
        try do
          String.to_existing_atom(other)
        rescue
          _ -> :local
        end
    end
  end

  @doc """
  Returns the S3 bucket name.
  Priority: DB setting → S3_BUCKET env var → "kiroku-uploads".
  """
  def storage_bucket do
    get("storage_bucket") || System.get_env("S3_BUCKET") || "kiroku-uploads"
  end

  @doc """
  Returns the S3 region.
  Priority: DB setting → AWS_REGION env var → "ap-southeast-1".
  """
  def storage_region do
    get("storage_region") ||
      System.get_env("AWS_REGION") ||
      "ap-southeast-1"
  end

  @doc """
  Returns the S3 access key ID.
  Priority: DB setting → AWS_ACCESS_KEY_ID env var.
  """
  def storage_access_key_id do
    get("storage_access_key_id") || System.get_env("AWS_ACCESS_KEY_ID")
  end

  @doc """
  Returns the S3 secret access key.
  Priority: DB setting → AWS_SECRET_ACCESS_KEY env var.
  """
  def storage_secret_access_key do
    get("storage_secret_access_key") || System.get_env("AWS_SECRET_ACCESS_KEY")
  end

  @doc """
  Returns the custom S3-compatible endpoint URL (for non-AWS S3, e.g. MinIO, R2).
  Priority: DB setting → S3_ENDPOINT env var → nil (uses default AWS endpoints).
  """
  def storage_endpoint do
    get("storage_endpoint") || System.get_env("S3_ENDPOINT")
  end

  @doc """
  Returns a map of all current storage settings for the admin UI.
  """
  def storage_settings do
    %{
      adapter: storage_adapter(),
      bucket: storage_bucket(),
      region: storage_region(),
      access_key_id: storage_access_key_id(),
      secret_access_key: storage_secret_access_key(),
      endpoint: storage_endpoint()
    }
  end
end
