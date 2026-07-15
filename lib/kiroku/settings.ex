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
  Priority: DB setting → S3_REGION env var → "ap-southeast-1".
  """
  def storage_region do
    get("storage_region") ||
      System.get_env("S3_REGION") ||
      "ap-southeast-1"
  end

  @doc """
  Returns the S3 access key ID.
  Priority: DB setting → S3_ACCESS_KEY_ID env var.
  """
  def storage_access_key_id do
    get("storage_access_key_id") || System.get_env("S3_ACCESS_KEY_ID")
  end

  @doc """
  Returns the S3 secret access key.
  Priority: DB setting → S3_SECRET_ACCESS_KEY env var.
  """
  def storage_secret_access_key do
    get("storage_secret_access_key") || System.get_env("S3_SECRET_ACCESS_KEY")
  end

  @doc """
  Returns the custom S3-compatible endpoint URL (for non-AWS S3, e.g. MinIO, R2).
  Priority: DB setting → S3_ENDPOINT env var → nil (uses default AWS endpoints).
  """
  def storage_endpoint do
    get("storage_endpoint") || System.get_env("S3_ENDPOINT")
  end

  @doc """
  Returns an explicit public base URL override for building file download links.
  Only needed when the public-facing domain differs from the S3_ENDPOINT API host.
  When S3_ENDPOINT is set (MinIO, R2, etc.), public URLs are derived automatically
  as endpoint/bucket/key — set this only to override that behaviour.
  Priority: DB setting → S3_PUBLIC_URL env var → nil.
  """
  def storage_public_url do
    get("storage_public_url") || System.get_env("S3_PUBLIC_URL")
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
      endpoint: storage_endpoint(),
      public_url: storage_public_url()
    }
  end

  # ── Brand-specific helpers ─────────────────────────────────────────────────

  @doc "Returns the brand/repository name."
  def brand_name, do: get("brand_name") || "Kiroku"

  @doc "Returns the brand tagline."
  def brand_tagline,
    do: get("brand_tagline") || "Every work recorded. Every scholar remembered."

  @doc "Returns the brand description shown on the homepage."
  def brand_description,
    do:
      get("brand_description") ||
        "The institutional repository for scholarly works — theses, legal memoranda, creative works, and research by the academic community."

  @doc "Returns the public contact e-mail address."
  def brand_contact_email, do: get("brand_contact_email") || "curatorian@proton.me"

  @doc "Returns the public contact phone number."
  def brand_contact_phone, do: get("brand_contact_phone") || "08123456789"

  @doc """
  Returns the URL of the brand logo image, or nil to use the text wordmark /
  default favicon. Empty/whitespace values are normalized to nil so fallbacks
  work correctly (an empty string is truthy in Elixir).
  """
  def brand_logo_url do
    case get("brand_logo_url") do
      nil ->
        nil

      s ->
        s
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end
    end
  end

  @doc """
  Returns the primary brand color as a CSS hex string (e.g. \"#7B4FA6\").
  This color overrides --color-patchouli site-wide.
  """
  def brand_primary_color, do: get("brand_primary_color") || "#7B4FA6"

  @doc "Returns a map of all current brand settings for the admin UI."
  def brand_settings do
    %{
      name: brand_name(),
      tagline: brand_tagline(),
      description: brand_description(),
      contact_email: brand_contact_email(),
      contact_phone: brand_contact_phone(),
      logo_url: brand_logo_url(),
      primary_color: brand_primary_color()
    }
  end

  # ── Embargo scheduler helpers ──────────────────────────────────────────────

  @default_embargo_cron "0 2 * * *"

  @doc """
  Returns the cron schedule for the embargo lifter worker.
  Priority: DB setting → EMBARGO_CRON env var → default (daily at 02:00).
  The cron value is read at application startup, so changes here take effect
  on the next restart.
  """
  def embargo_cron_schedule do
    get("embargo_cron_schedule") ||
      System.get_env("EMBARGO_CRON", @default_embargo_cron)
  end

  @doc "Returns a map of embargo scheduler settings for the admin UI."
  def embargo_settings do
    %{
      cron_schedule: embargo_cron_schedule()
    }
  end

  # ── Mailer helpers ───────────────────────────────────────────────────────────

  @doc """
  Returns the mailer provider.
  Priority: DB setting → MAILER_PROVIDER env var → "local" (dev/test, no sending).
  """
  def mailer_provider, do: get("mailer_provider") || System.get_env("MAILER_PROVIDER") || "local"

  @doc "Returns the default From address for outgoing email."
  def mailer_from,
    do: get("mailer_from") || System.get_env("MAILER_FROM") || "noreply@kiroku.local"

  @doc "Returns the SMTP host."
  def mailer_smtp_host, do: get("smtp_host") || System.get_env("SMTP_HOST")

  @doc "Returns the SMTP port as an integer, or nil."
  def mailer_smtp_port do
    case get("smtp_port") || System.get_env("SMTP_PORT") do
      nil -> nil
      v -> String.to_integer(v)
    end
  end

  @doc "Returns the SMTP username."
  def mailer_smtp_username, do: get("smtp_username") || System.get_env("SMTP_USERNAME")

  @doc "Returns the SMTP password."
  def mailer_smtp_password, do: get("smtp_password") || System.get_env("SMTP_PASSWORD")

  @doc "Returns a map of all current mailer settings for the admin UI."
  def mailer_settings do
    %{
      provider: mailer_provider(),
      from: mailer_from(),
      host: mailer_smtp_host(),
      port: mailer_smtp_port(),
      username: mailer_smtp_username(),
      password: mailer_smtp_password()
    }
  end

  # ── Onboarding helpers ───────────────────────────────────────────────────────

  @setup_key "setup_complete"

  @doc "Returns whether the first-run onboarding wizard has been completed."
  def setup_complete?, do: get(@setup_key) == "true"

  @doc "Marks the onboarding wizard as completed."
  def mark_setup_complete do
    put(@setup_key, "true", "Whether the first-run onboarding wizard has been completed")
  end

  # ── Submission toggle ────────────────────────────────────────────────────────

  @doc """
  Returns whether regular users are allowed to submit new items.

  When `false`, only staff (admins/superadmins) can create items. Controlled by
  the `allow_user_submit` setting, defaulting to `false`.
  """
  def allow_user_submit?, do: get("allow_user_submit", "false") == "true"

  @doc """
  Returns whether self-registration is allowed.
  When false, the standard email/password registration form is disabled.
  PAuS OAuth login always works regardless of this setting.
  Defaults to true.
  """
  def allow_registration?, do: get("allow_registration", "true") == "true"

  # ── Repository handle ────────────────────────────────────────────────────────

  @doc """
  Returns the handle prefix for this repository (e.g. "kandaga").
  Used when constructing item, community, and collection handles during import.
  Defaults to "kandaga".
  """
  def handle_prefix, do: get("handle_prefix", "kandaga")

  @doc """
  Returns the list of bitstream descriptions that are globally locked
  (e.g. ["Bab 2", "Bab 3"]). Locked files are visible only to :internal
  users and staff. Returns [] when unset.
  """
  def locked_bitstream_descriptions do
    get("locked_bitstream_descriptions", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  @doc "Sets the locked bitstream descriptions from a list."
  def put_locked_bitstream_descriptions(descriptions) when is_list(descriptions) do
    put(
      "locked_bitstream_descriptions",
      Enum.join(descriptions, ","),
      "Bitstream descriptions locked from public view (visible to internal + staff)"
    )
  end

  # ── DOI minting helpers ──────────────────────────────────────────────────────

  @doc """
  Master switch for DOI minting on publish. When false, no DOI worker is
  enqueued. Defaults to false — must be explicitly enabled after credentials
  are configured. Priority: DB setting → DOI_ENABLED env → false.
  """
  def doi_enabled?, do: get("doi_enabled", System.get_env("DOI_ENABLED", "false")) == "true"

  @doc """
  Active DOI provider key. One of "mock" (dev/test, no network) or "datacite".
  Priority: DB setting → DOI_PROVIDER env → "mock".
  """
  def doi_provider, do: get("doi_provider", System.get_env("DOI_PROVIDER", "mock"))

  @doc """
  DOI prefix (the registrant prefix assigned by DataCite/Crossref).
  Example: "10.5555". Priority: DB setting → DOI_PREFIX env → "10.5555".
  """
  def doi_prefix, do: get("doi_prefix", System.get_env("DOI_PREFIX", "10.5555"))

  @doc "DataCite REST API username. Priority: DB setting → DATACITE_USERNAME env."
  def doi_username, do: get("doi_username", System.get_env("DATACITE_USERNAME"))

  @doc "DataCite REST API password. Priority: DB setting → DATACITE_PASSWORD env."
  def doi_password, do: get("doi_password", System.get_env("DATACITE_PASSWORD"))

  @doc "Returns a map of all DOI settings for the admin UI."
  def doi_settings do
    %{
      enabled: doi_enabled?(),
      provider: doi_provider(),
      prefix: doi_prefix(),
      username: doi_username(),
      endpoint: get("doi_endpoint", System.get_env("DOI_ENDPOINT", "https://api.datacite.org"))
    }
  end
end
