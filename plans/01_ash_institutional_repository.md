# Institutional Repository — Ash Framework Edition
## DSpace Replacement: Ash + Phoenix + AshPostgres + AshAuthentication + AshAdmin

---

## 0. The Ash Mental Model — Read This First

Before touching code, internalize these paradigm shifts. The original guide was written for plain Ecto + Phoenix contexts. Ash replaces or absorbs most of that layer.

| Original (Ecto/Phoenix) | Ash Equivalent |
|---|---|
| `Ecto.Schema` module | `Ash.Resource` |
| Context module (`Repository`, `Accounts`) | `Ash.Domain` |
| `Repo.insert / update / delete` | `Ash.create / update / destroy` |
| `Ecto.Changeset` | Ash action with `accept`, `validate`, `change` |
| `Ecto.Query` | `Ash.Query` |
| Custom `can?/3` auth function | `Ash.Policy.Authorizer` built into each resource |
| Custom RBAC policy table lookups | Ash policy `authorize_if` with custom checks |
| `phx_gen_auth` | `AshAuthentication` + `AshAuthenticationPhoenix` |
| Manual admin LiveViews | `AshAdmin` (zero-code admin panel) |
| Guardian JWT | `AshAuthentication` token strategy |
| Oban workers | `AshOban` (Oban integrated into Ash actions) |
| REST API controllers | `AshJsonApi` (auto-generated from resources) |

### The Golden Rule

> In Ash you **define** your domain model (attributes, relationships, actions, policies) declaratively inside `Ash.Resource` modules. You do **not** write separate context functions, changeset helpers, or query builders. The Ash engine runs them.

Calling `Ash.create(Community, %{name: "UNPAD"}, actor: current_user)` goes through the resource's `create` action, runs all validations, fires all changes, checks all Ash policies, and writes to the database — in one call.

---

## 1. Dependencies — `mix.exs`

Replace the original dependency list with this Ash-idiomatic set.

```elixir
defp deps do
  [
    # ── Phoenix Core ──────────────────────────────────────────────────────────
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_live_dashboard, "~> 0.8"},
    {:bandit, ">= 0.0.0"},

    # ── Ash Core ─────────────────────────────────────────────────────────────
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},       # Primary data layer (PostgreSQL)
    {:ash_phoenix, "~> 2.0"},        # LiveView + form helpers
    {:ash_admin, "~> 0.11"},         # Zero-code admin panel
    {:ash_authentication, "~> 4.0"}, # Auth strategies (password, JWT, etc.)
    {:ash_authentication_phoenix, "~> 2.0"}, # Auth routes & LiveViews
    {:ash_oban, "~> 0.2"},           # Background jobs via Oban
    {:ash_json_api, "~> 1.0"},       # REST API (DSpace 7 API compatibility)

    # ── Database Drivers ──────────────────────────────────────────────────────
    {:postgrex, ">= 0.0.0"},         # PostgreSQL (primary)
    {:tds, "~> 2.3"},                # MSSQL (legacy import only)
    {:ecto_sql, "~> 3.11"},          # Still needed for LegacyRepo (MSSQL)

    # ── Background Jobs ───────────────────────────────────────────────────────
    {:oban, "~> 2.17"},              # AshOban depends on this

    # ── File / Storage ────────────────────────────────────────────────────────
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:sweet_xml, "~> 0.7"},

    # ── HTTP ─────────────────────────────────────────────────────────────────
    {:req, "~> 0.5"},

    # ── OAI-PMH XML ──────────────────────────────────────────────────────────
    {:xml_builder, "~> 2.2"},

    # ── Utilities ────────────────────────────────────────────────────────────
    {:nimble_csv, "~> 1.2"},
    {:slugify, "~> 1.3"},
    {:image, "~> 0.54"},

    # ── Dev / Test ────────────────────────────────────────────────────────────
    {:igniter, "~> 0.3", only: [:dev]},  # Ash code generation
  ]
end
```

> **Why no `guardian` or `bcrypt_elixir` directly?** `AshAuthentication` handles both JWT tokens and password hashing internally. You don't manage those packages yourself.

> **Why `igniter`?** Ash's `mix ash.install` and resource generators use Igniter for safe code patching. Install it as dev-only.

---

## 2. Application Structure

```
lib/
  institutional_repository/
    # ── Ash Domains ─────────────────────────────────────────────────────
    repository.ex           # Ash.Domain: Community, Collection, Item, etc.
    accounts.ex             # Ash.Domain: User, Group, GroupMembership
    content.ex              # Ash.Domain: Bitstream
    access.ex               # Ash.Domain: RbacPolicy (the grant table)
    analytics.ex            # Ash.Domain: ViewEvent

    # ── Ash Resources ───────────────────────────────────────────────────
    repository/
      community.ex
      collection.ex
      item.ex
      item_keyword.ex
      item_author.ex
      item_advisor.ex
      item_metadata.ex
    content/
      bitstream.ex
    accounts/
      user.ex
      user/token.ex          # AshAuthentication token resource
      group.ex
      group_membership.ex
    access/
      rbac_policy.ex         # The RBAC grant table (renamed to avoid clash)
    analytics/
      view_event.ex

    # ── Legacy (MSSQL read-only, NOT Ash resources) ──────────────────────
    legacy_repo.ex
    legacy_thesis.ex         # Plain Ecto schema for tbtMhsUploadThesis

    # ── Supporting Modules ───────────────────────────────────────────────
    access/
      policy_checks.ex       # Custom Ash.Policy.Check modules
    embargo/
      lifter_worker.ex       # AshOban worker
    oai/
      builder.ex
    export/
      citation.ex

  institutional_repository_web/
    router.ex
    controllers/
      handle_controller.ex
      bitstream_controller.ex
      oai_pmh_controller.ex
      citation_controller.ex
    live/
      # (same structure as original, but using AshPhoenix helpers)
    components/

priv/
  repo/
    migrations/              # Generated by `mix ash.generate_migrations`
    seeds.exs

lib/mix/tasks/
  import_from_mssql.ex
```

---

## 3. Repos & Database Configuration

### 3.1 Primary Repo (AshPostgres — PostgreSQL)

```elixir
# lib/institutional_repository/repo.ex
defmodule InstitutionalRepository.Repo do
  use AshPostgres.Repo,
    otp_app: :institutional_repository

  def installed_extensions do
    # Add "uuid-ossp" if your PG version < 13; otherwise pgcrypto handles it.
    ["uuid-ossp", "citext"]
  end
end
```

### 3.2 Legacy Repo (Plain Ecto — MSSQL, read-only, import-time only)

```elixir
# lib/institutional_repository/legacy_repo.ex
defmodule InstitutionalRepository.LegacyRepo do
  use Ecto.Repo,
    otp_app: :institutional_repository,
    adapter: Ecto.Adapters.Tds
end
```

This is a **plain Ecto repo**, not an Ash data layer. It is started in `application.ex` alongside the Ash repo and used only in the import Mix task.

### 3.3 Application Supervisor

```elixir
# lib/institutional_repository/application.ex
children = [
  InstitutionalRepository.Repo,
  InstitutionalRepository.LegacyRepo,
  InstitutionalRepositoryWeb.Endpoint,
  {Oban, Application.fetch_env!(:institutional_repository, Oban)},
]
```

### 3.4 Runtime Config

```elixir
# config/runtime.exs

# Primary (PostgreSQL — open source default)
config :institutional_repository, InstitutionalRepository.Repo,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

# Legacy MSSQL (import-time only)
config :institutional_repository, InstitutionalRepository.LegacyRepo,
  adapter: Ecto.Adapters.Tds,
  hostname: System.get_env("MSSQL_HOST"),
  database: System.get_env("MSSQL_DB"),
  username: System.get_env("MSSQL_USER"),
  password: System.get_env("MSSQL_PASS"),
  port: 1433,
  pool_size: 2
```

> **Internal MSSQL mode**: If your primary DB must stay MSSQL, use `Ash.DataLayer.Ecto` as the data layer instead of `AshPostgres.DataLayer` and point it at your TDS repo. This loses some AshPostgres-specific features (e.g. `AshPostgres.Tsquery` full-text). PostgreSQL is strongly recommended for Ash.

---

## 4. Ash Domains

Each domain groups related resources. The domain is the entry point for calling actions in code.

```elixir
# lib/institutional_repository/repository.ex
defmodule InstitutionalRepository.Repository do
  use Ash.Domain, otp_app: :institutional_repository

  resources do
    resource InstitutionalRepository.Repository.Community
    resource InstitutionalRepository.Repository.Collection
    resource InstitutionalRepository.Repository.Item
    resource InstitutionalRepository.Repository.ItemKeyword
    resource InstitutionalRepository.Repository.ItemAuthor
    resource InstitutionalRepository.Repository.ItemAdvisor
    resource InstitutionalRepository.Repository.ItemMetadata
  end
end
```

```elixir
# lib/institutional_repository/accounts.ex
defmodule InstitutionalRepository.Accounts do
  use Ash.Domain, otp_app: :institutional_repository

  resources do
    resource InstitutionalRepository.Accounts.User
    resource InstitutionalRepository.Accounts.Token
    resource InstitutionalRepository.Accounts.Group
    resource InstitutionalRepository.Accounts.GroupMembership
  end
end
```

```elixir
# lib/institutional_repository/content.ex
defmodule InstitutionalRepository.Content do
  use Ash.Domain, otp_app: :institutional_repository

  resources do
    resource InstitutionalRepository.Content.Bitstream
  end
end
```

```elixir
# lib/institutional_repository/access.ex
defmodule InstitutionalRepository.Access do
  use Ash.Domain, otp_app: :institutional_repository

  resources do
    resource InstitutionalRepository.Access.RbacPolicy
  end
end
```

```elixir
# lib/institutional_repository/analytics.ex
defmodule InstitutionalRepository.Analytics do
  use Ash.Domain, otp_app: :institutional_repository

  resources do
    resource InstitutionalRepository.Analytics.ViewEvent
  end
end
```

Register all domains in `config/config.exs`:

```elixir
config :institutional_repository,
  ash_domains: [
    InstitutionalRepository.Repository,
    InstitutionalRepository.Accounts,
    InstitutionalRepository.Content,
    InstitutionalRepository.Access,
    InstitutionalRepository.Analytics,
  ]
```

---

## 5. Ash Resources

### 5.1 Community

```elixir
# lib/institutional_repository/repository/community.ex
defmodule InstitutionalRepository.Repository.Community do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "communities"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name,              :string,  allow_nil?: false, public?: true
    attribute :handle,            :string,  public?: true
    attribute :short_description, :string,  public?: true
    attribute :description,       :string,  public?: true
    attribute :logo_bitstream_id, :uuid,    public?: true
    attribute :position,          :integer, default: 0, public?: true
    attribute :is_active,         :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :parent_community, __MODULE__, public?: true
    has_many   :subcommunities,   __MODULE__,
      destination_attribute: :parent_community_id, public?: true
    has_many :collections, InstitutionalRepository.Repository.Collection,
      public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :handle, :short_description, :description,
              :logo_bitstream_id, :position, :parent_community_id, :is_active]
      validate present(:name)
    end

    update :update do
      accept [:name, :handle, :short_description, :description,
              :logo_bitstream_id, :position, :is_active]
    end

    read :by_handle do
      argument :handle, :string, allow_nil?: false
      filter expr(handle == ^arg(:handle))
    end
  end

  # ── Authorization ──────────────────────────────────────────────────────────
  policies do
    # Anyone can read communities
    policy action_type(:read) do
      authorize_if always()
    end

    # Only admins can create/update/delete
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end
  end
end
```

### 5.2 Collection

```elixir
# lib/institutional_repository/repository/collection.ex
defmodule InstitutionalRepository.Repository.Collection do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "collections"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name,              :string,  allow_nil?: false, public?: true
    attribute :handle,            :string,  public?: true
    attribute :short_description, :string,  public?: true
    attribute :description,       :string,  public?: true
    attribute :logo_bitstream_id, :uuid,    public?: true
    attribute :license_text,      :string,  public?: true
    attribute :position,          :integer, default: 0, public?: true
    attribute :is_active,         :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :community, InstitutionalRepository.Repository.Community,
      allow_nil?: false, public?: true
    has_many :items, InstitutionalRepository.Repository.Item, public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :handle, :short_description, :description,
              :logo_bitstream_id, :license_text, :position,
              :community_id, :is_active]
      validate present(:name)
    end

    update :update do
      accept [:name, :handle, :short_description, :description,
              :logo_bitstream_id, :license_text, :position, :is_active]
    end

    read :by_handle do
      argument :handle, :string, allow_nil?: false
      filter expr(handle == ^arg(:handle))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end
  end
end
```

### 5.3 Item

This is the most important resource. Note how validations and lifecycle logic move into the resource itself.

```elixir
# lib/institutional_repository/repository/item.ex
defmodule InstitutionalRepository.Repository.Item do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "items"
    repo InstitutionalRepository.Repo

    custom_indexes do
      index [:student_id]
      index [:status]
      index [:publication_year]
      index [:discoverable]
      index [:department]
      index [:faculty]
    end
  end

  # ── Status & Access Level enums ────────────────────────────────────────────

  @status_values ~w(draft submitted under_review published embargoed withdrawn)a
  @access_values ~w(open restricted closed)a
  @type_values   ~w(thesis dissertation article book report dataset)a
  @degree_values ~w(bachelor master doctoral)a

  attributes do
    uuid_primary_key :id

    # Identity
    attribute :handle,            :string,  public?: true
    attribute :legacy_id,         :string,  public?: true
    attribute :idpustaka,         :string,  public?: true

    # Bibliographic
    attribute :title,             :string,  allow_nil?: false, public?: true
    attribute :title_raw,         :string,  public?: true
    attribute :title_alt,         :string,  public?: true
    attribute :abstract,          :string,  public?: true
    attribute :abstract_raw,      :string,  public?: true
    attribute :language,          :string,  default: "id", public?: true

    # Classification
    attribute :item_type,         :atom,
      constraints: [one_of: @type_values],
      default: :thesis, public?: true
    attribute :degree_level,      :atom,
      constraints: [one_of: @degree_values],
      public?: true
    attribute :department,        :string, public?: true
    attribute :faculty,           :string, public?: true
    attribute :program_study,     :string, public?: true

    # Student (thesis-specific)
    attribute :student_id,        :string, public?: true
    attribute :student_name,      :string, public?: true

    # Lifecycle
    attribute :status,            :atom,
      constraints: [one_of: @status_values],
      default: :draft, public?: true
    attribute :access_level,      :atom,
      constraints: [one_of: @access_values],
      default: :open, public?: true
    attribute :discoverable,      :boolean, default: true, public?: true
    attribute :withdrawn,         :boolean, default: false, public?: true

    # Dates
    attribute :date_submitted,    :date,    public?: true
    attribute :date_issued,       :date,    public?: true
    attribute :date_available,    :date,    public?: true
    attribute :publication_year,  :integer, public?: true
    attribute :published_at,      :naive_datetime, public?: true

    # Embargo
    attribute :embargo_open_date,  :date,   public?: true
    attribute :embargo_close_date, :date,   public?: true
    attribute :embargo_reason,     :string, public?: true

    # Source
    attribute :base_url,           :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :collection, InstitutionalRepository.Repository.Collection,
      allow_nil?: false, public?: true
    belongs_to :submitter, InstitutionalRepository.Accounts.User,
      allow_nil?: true, public?: true

    has_many :item_keywords, InstitutionalRepository.Repository.ItemKeyword,
      public?: true
    has_many :item_authors,  InstitutionalRepository.Repository.ItemAuthor,
      public?: true
    has_many :item_advisors, InstitutionalRepository.Repository.ItemAdvisor,
      public?: true
    has_many :bitstreams,    InstitutionalRepository.Content.Bitstream,
      public?: true
    has_many :metadata_extras, InstitutionalRepository.Repository.ItemMetadata,
      public?: true
    has_many :rbac_policies, InstitutionalRepository.Access.RbacPolicy,
      destination_attribute: :resource_id,
      public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end

  # ── Calculations ───────────────────────────────────────────────────────────
  # Calculations let you compute derived data on-the-fly.

  calculations do
    calculate :files_embargoed?, :boolean,
      InstitutionalRepository.Repository.Item.Calculations.FilesEmbargoed
  end

  actions do
    defaults [:destroy]

    # Default read with access filtering built in
    read :read do
      primary? true
      # Filter to discoverable, non-withdrawn items for public reads.
      # Admins bypass this with their actor privileges.
      prepare build(filter: expr(discoverable == true and withdrawn == false))
    end

    # Admin-only: read all items including hidden ones
    read :read_all do
      filter expr(true)
    end

    read :by_handle do
      argument :handle, :string, allow_nil?: false
      filter expr(handle == ^arg(:handle))
    end

    read :by_legacy_id do
      argument :legacy_id, :string, allow_nil?: false
      filter expr(legacy_id == ^arg(:legacy_id))
    end

    read :search do
      argument :term,        :string
      argument :department,  :string
      argument :faculty,     :string
      argument :year,        :integer
      argument :item_type,   :atom
      argument :access_level,:atom
      argument :page,        :integer, default: 1
      argument :per_page,    :integer, default: 20

      prepare InstitutionalRepository.Repository.Item.Preparations.Search

      pagination keyset?: true, offset?: true, default_limit: 20, max_page_size: 100
    end

    read :browse_by_date do
      argument :year, :integer
      filter expr(publication_year == ^arg(:year) and status == :published)
      pagination offset?: true, default_limit: 20
    end

    create :create do
      accept [
        :collection_id, :submitter_id,
        :handle, :legacy_id, :idpustaka,
        :title, :title_raw, :title_alt,
        :abstract, :abstract_raw, :language,
        :item_type, :degree_level, :department, :faculty, :program_study,
        :student_id, :student_name,
        :status, :access_level, :discoverable, :withdrawn,
        :date_submitted, :date_issued, :date_available, :publication_year,
        :published_at, :embargo_open_date, :embargo_close_date, :embargo_reason,
        :base_url
      ]

      validate present(:title)
      validate present(:collection_id)

      # After creating, apply default access level policies
      change after_action(fn changeset, record, _context ->
        InstitutionalRepository.Access.PolicyManager.apply_access_level(record, record.access_level)
        {:ok, record}
      end)
    end

    # Import action for the MSSQL import task (bypasses normal authorization)
    create :import do
      accept [:collection_id, :submitter_id, :handle, :legacy_id, :idpustaka,
              :title, :title_raw, :title_alt, :abstract, :abstract_raw,
              :language, :item_type, :degree_level, :department, :faculty,
              :program_study, :student_id, :student_name, :status,
              :access_level, :discoverable, :withdrawn, :date_submitted,
              :date_issued, :date_available, :publication_year, :published_at,
              :embargo_open_date, :embargo_close_date, :embargo_reason, :base_url]

      # Skip authorization for this internal import action
      skip_unknown_inputs [:*]
    end

    update :update do
      accept [:title, :title_raw, :title_alt, :abstract, :abstract_raw,
              :language, :item_type, :degree_level, :department, :faculty,
              :program_study, :status, :access_level, :discoverable, :withdrawn,
              :date_submitted, :date_issued, :date_available, :publication_year,
              :embargo_open_date, :embargo_close_date, :embargo_reason]

      change after_action(fn _changeset, record, _context ->
        # Re-apply access policies when access_level changes
        InstitutionalRepository.Access.PolicyManager.apply_access_level(record, record.access_level)
        {:ok, record}
      end)
    end

    update :publish do
      change set_attribute(:status, :published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
      change set_attribute(:discoverable, true)
    end

    update :withdraw do
      change set_attribute(:status, :withdrawn)
      change set_attribute(:withdrawn, true)
      change set_attribute(:discoverable, false)
    end

    update :lift_embargo do
      change set_attribute(:status, :published)
      change set_attribute(:embargo_open_date, nil)
    end
  end

  # ── Authorization ──────────────────────────────────────────────────────────
  policies do
    # All actors (including anonymous = nil) can read open, published items.
    # We use a custom check that looks at the database RbacPolicy table.
    policy action_type(:read) do
      authorize_if InstitutionalRepository.Access.PolicyChecks.CanRead
    end

    # Submitters can create items in collections they are permitted for.
    policy action(:create) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
      authorize_if actor_attribute_equals(:user_type, "submitter")
    end

    # Owner or admin can update
    policy action(:update) do
      authorize_if relates_to_actor_via(:submitter)
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end

    # Import action: always authorize (called from trusted Mix task)
    policy action(:import) do
      authorize_if always()
    end

    # Publish/withdraw: admin only
    policy action([:publish, :withdraw, :lift_embargo]) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
      authorize_if actor_attribute_equals(:user_type, "reviewer")
    end

    # Destroy: admin only
    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end
  end
end
```

#### Item Calculation: FilesEmbargoed

```elixir
# lib/institutional_repository/repository/item/calculations/files_embargoed.ex
defmodule InstitutionalRepository.Repository.Item.Calculations.FilesEmbargoed do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    today = Date.utc_today()

    Enum.map(records, fn item ->
      open_blocked  = item.embargo_open_date &&
                      Date.compare(today, item.embargo_open_date) == :lt
      close_blocked = item.embargo_close_date &&
                      Date.compare(today, item.embargo_close_date) != :lt
      open_blocked || close_blocked || false
    end)
  end
end
```

#### Item Search Preparation

```elixir
# lib/institutional_repository/repository/item/preparations/search.ex
defmodule InstitutionalRepository.Repository.Item.Preparations.Search do
  use Ash.Resource.Preparation
  import Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    term       = Ash.Query.get_argument(query, :term)
    department = Ash.Query.get_argument(query, :department)
    faculty    = Ash.Query.get_argument(query, :faculty)
    year       = Ash.Query.get_argument(query, :year)
    item_type  = Ash.Query.get_argument(query, :item_type)

    query
    |> filter_if(term, fn q ->
      Ash.Query.filter(q, expr(
        fragment("to_tsvector('indonesian', coalesce(title,'') || ' ' || coalesce(abstract,'')) @@ plainto_tsquery(?)", ^term)
      ))
    end)
    |> filter_if(department, fn q -> Ash.Query.filter(q, expr(department == ^department)) end)
    |> filter_if(faculty,    fn q -> Ash.Query.filter(q, expr(faculty == ^faculty)) end)
    |> filter_if(year,       fn q -> Ash.Query.filter(q, expr(publication_year == ^year)) end)
    |> filter_if(item_type,  fn q -> Ash.Query.filter(q, expr(item_type == ^item_type)) end)
    |> Ash.Query.filter(expr(status == :published and discoverable == true))
    |> Ash.Query.sort(desc: :published_at)
  end

  defp filter_if(query, nil, _fun), do: query
  defp filter_if(query, _value, fun), do: fun.(query)
end
```

### 5.4 ItemKeyword

```elixir
# lib/institutional_repository/repository/item_keyword.ex
defmodule InstitutionalRepository.Repository.ItemKeyword do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_keywords"
    repo InstitutionalRepository.Repo
    custom_indexes do
      index [:keyword]
      index [:item_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :keyword,  :string, allow_nil?: false, public?: true
    attribute :language, :string, default: "id", public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:keyword, :language, :item_id]
      validate present(:keyword)
    end

    create :import do
      accept [:keyword, :language, :item_id]
    end
  end
end
```

### 5.5 ItemAuthor

```elixir
# lib/institutional_repository/repository/item_author.ex
defmodule InstitutionalRepository.Repository.ItemAuthor do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_authors"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :author_name,        :string, allow_nil?: false, public?: true
    attribute :author_email,       :string, public?: true
    attribute :author_affiliation, :string, public?: true
    attribute :sequence,           :integer, default: 1, public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:author_name, :author_email, :author_affiliation, :sequence, :item_id]
      validate present(:author_name)
    end

    create :import do
      accept [:author_name, :author_email, :author_affiliation, :sequence, :item_id]
    end
  end
end
```

### 5.6 ItemAdvisor

```elixir
# lib/institutional_repository/repository/item_advisor.ex
defmodule InstitutionalRepository.Repository.ItemAdvisor do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_advisors"
    repo InstitutionalRepository.Repo
  end

  @advisor_roles ~w(main_advisor co_advisor examiner chair)a

  attributes do
    uuid_primary_key :id
    attribute :advisor_name, :string, allow_nil?: false, public?: true
    attribute :advisor_role, :atom,
      constraints: [one_of: @advisor_roles],
      default: :main_advisor, public?: true
    attribute :advisor_nip,  :string, public?: true
    attribute :sequence,     :integer, default: 1, public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:advisor_name, :advisor_role, :advisor_nip, :sequence, :item_id]
      validate present(:advisor_name)
    end

    create :import do
      accept [:advisor_name, :advisor_role, :advisor_nip, :sequence, :item_id]
    end
  end
end
```

### 5.7 ItemMetadata

```elixir
# lib/institutional_repository/repository/item_metadata.ex
defmodule InstitutionalRepository.Repository.ItemMetadata do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_metadata"
    repo InstitutionalRepository.Repo
    custom_indexes do
      index [:field_schema, :field_element]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :field_schema,    :string, allow_nil?: false, public?: true
    attribute :field_element,   :string, allow_nil?: false, public?: true
    attribute :field_qualifier, :string, public?: true
    attribute :field_value,     :string, allow_nil?: false, public?: true
    attribute :language,        :string, public?: true
    attribute :confidence,      :integer, default: 0, public?: true
    attribute :place,           :integer, default: 1, public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  calculations do
    calculate :full_field, :string,
      InstitutionalRepository.Repository.ItemMetadata.Calculations.FullField
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:field_schema, :field_element, :field_qualifier,
              :field_value, :language, :confidence, :place, :item_id]
    end

    create :import do
      accept [:field_schema, :field_element, :field_qualifier,
              :field_value, :language, :confidence, :place, :item_id]
    end
  end
end
```

### 5.8 Bitstream

```elixir
# lib/institutional_repository/content/bitstream.ex
defmodule InstitutionalRepository.Content.Bitstream do
  use Ash.Resource,
    domain: InstitutionalRepository.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bitstreams"
    repo InstitutionalRepository.Repo
    custom_indexes do
      index [:bundle_name]
    end
  end

  @bundle_names   ~w(ORIGINAL THUMBNAIL CHAPTER SUPPLEMENTAL ADMINISTRATIVE LICENSE)a
  @storage_types  ~w(url s3 local)a
  @access_levels  ~w(inherit open restricted closed)a

  attributes do
    uuid_primary_key :id

    attribute :filename,           :string, allow_nil?: false, public?: true
    attribute :bundle_name,        :atom,
      constraints: [one_of: @bundle_names],
      default: :ORIGINAL, public?: true
    attribute :sequence,           :integer, default: 0, public?: true
    attribute :description,        :string, public?: true

    attribute :storage_type,       :atom,
      constraints: [one_of: @storage_types],
      default: :url, public?: true
    attribute :storage_url,        :string, public?: true
    attribute :storage_path,       :string, public?: true
    attribute :storage_bucket,     :string, public?: true

    attribute :mime_type,          :string, public?: true
    attribute :size_bytes,         :integer, default: 0, public?: true
    attribute :checksum,           :string, public?: true
    attribute :checksum_algorithm, :string, default: "md5", public?: true

    attribute :access_level,       :atom,
      constraints: [one_of: @access_levels],
      default: :inherit, public?: true

    attribute :embargo_open_date,  :date, public?: true
    attribute :embargo_close_date, :date, public?: true

    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  calculations do
    calculate :resolved_url, :string,
      InstitutionalRepository.Content.Bitstream.Calculations.ResolveUrl
    calculate :files_embargoed?, :boolean,
      InstitutionalRepository.Content.Bitstream.Calculations.FilesEmbargoed
  end

  validations do
    validate InstitutionalRepository.Content.Bitstream.Validations.StorageFields
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:filename, :bundle_name, :sequence, :description,
              :storage_type, :storage_url, :storage_path, :storage_bucket,
              :mime_type, :size_bytes, :checksum, :checksum_algorithm,
              :access_level, :embargo_open_date, :embargo_close_date, :item_id]
    end

    create :import do
      accept [:filename, :bundle_name, :sequence, :description,
              :storage_type, :storage_url, :storage_path, :storage_bucket,
              :mime_type, :size_bytes, :checksum, :checksum_algorithm,
              :access_level, :embargo_open_date, :embargo_close_date, :item_id]
    end

    update :update do
      accept [:access_level, :embargo_open_date, :embargo_close_date, :description]
    end

    update :lift_embargo do
      change set_attribute(:embargo_open_date, nil)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if InstitutionalRepository.Access.PolicyChecks.CanReadBitstream
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
      authorize_if actor_attribute_equals(:user_type, "submitter")
    end

    policy action(:import) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end
  end
end
```

#### Bitstream Validation: StorageFields

```elixir
# lib/institutional_repository/content/bitstream/validations/storage_fields.ex
defmodule InstitutionalRepository.Content.Bitstream.Validations.StorageFields do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :storage_type) do
      :url   -> require_field(changeset, :storage_url)
      :s3    -> require_fields(changeset, [:storage_path, :storage_bucket])
      :local -> require_field(changeset, :storage_path)
      _      -> :ok
    end
  end

  defp require_field(changeset, field) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil -> {:error, field: field, message: "is required for this storage type"}
      _   -> :ok
    end
  end

  defp require_fields(changeset, fields) do
    Enum.find_value(fields, :ok, fn f -> require_field(changeset, f) end)
  end
end
```

#### Bitstream Calculation: ResolveUrl

```elixir
# lib/institutional_repository/content/bitstream/calculations/resolve_url.ex
defmodule InstitutionalRepository.Content.Bitstream.Calculations.ResolveUrl do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn bitstream ->
      case bitstream.storage_type do
        :url   -> {:redirect, bitstream.storage_url}
        :local -> {:send_file, bitstream.storage_path}
        :s3    ->
          url = ExAws.S3.presigned_url(
            ExAws.Config.new(:s3), :get,
            bitstream.storage_bucket, bitstream.storage_path,
            expires_in: 3600
          )
          {:redirect, url}
      end
    end)
  end
end
```

### 5.9 User (AshAuthentication)

```elixir
# lib/institutional_repository/accounts/user.ex
defmodule InstitutionalRepository.Accounts.User do
  use Ash.Resource,
    domain: InstitutionalRepository.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  postgres do
    table "users"
    repo InstitutionalRepository.Repo
  end

  @user_types ~w(member submitter reviewer admin superadmin)a

  authentication do
    strategies do
      password :password do
        identity_field :email
        sign_in_tokens_enabled? true
      end
    end

    tokens do
      enabled? true
      token_resource InstitutionalRepository.Accounts.Token
      signing_secret fn _, _ ->
        Application.fetch_env(:institutional_repository, :token_signing_secret)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email,       :ci_string, allow_nil?: false, public?: true
    attribute :full_name,   :string, public?: true
    attribute :external_id, :string, public?: true
    attribute :user_type,   :atom,
      constraints: [one_of: @user_types],
      default: :member, public?: true
    attribute :active,      :boolean, default: true, public?: true

    # hashed_password is managed by AshAuthentication — do not touch directly
    timestamps()
  end

  relationships do
    has_many :group_memberships, InstitutionalRepository.Accounts.GroupMembership,
      public?: true
    has_many :groups, InstitutionalRepository.Accounts.Group,
      through: InstitutionalRepository.Accounts.GroupMembership,
      public?: true
    has_many :submitted_items, InstitutionalRepository.Repository.Item,
      destination_attribute: :submitter_id, public?: true
  end

  identities do
    identity :unique_email, [:email]
  end

  actions do
    defaults [:read]

    read :current_user do
      get? true
      manual InstitutionalRepository.Accounts.User.Actions.CurrentUser
    end

    update :update_profile do
      accept [:full_name, :external_id]
    end

    update :set_user_type do
      accept [:user_type]
      # Only admins can change user types (enforced by policy)
    end

    update :deactivate do
      change set_attribute(:active, false)
    end
  end

  policies do
    # AshAuthentication internal actions bypass policy check
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Users can read their own data; admins can read all
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
      authorize_if relates_to_actor_via(:id)
    end

    # Only admins can change user_type
    policy action(:set_user_type) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end

    # Users can update their own profile
    policy action(:update_profile) do
      authorize_if relates_to_actor_via(:id)
      authorize_if actor_attribute_equals(:user_type, "admin")
    end
  end
end
```

#### Token Resource (Required by AshAuthentication)

```elixir
# lib/institutional_repository/accounts/token.ex
defmodule InstitutionalRepository.Accounts.Token do
  use Ash.Resource,
    domain: InstitutionalRepository.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo InstitutionalRepository.Repo
  end

  actions do
    defaults [:read, :destroy]
  end
end
```

### 5.10 Group

```elixir
# lib/institutional_repository/accounts/group.ex
defmodule InstitutionalRepository.Accounts.Group do
  use Ash.Resource,
    domain: InstitutionalRepository.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "groups"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name,        :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :is_system,   :boolean, default: false, public?: true
    timestamps()
  end

  relationships do
    has_many :group_memberships, InstitutionalRepository.Accounts.GroupMembership,
      public?: true
    has_many :users, InstitutionalRepository.Accounts.User,
      through: InstitutionalRepository.Accounts.GroupMembership,
      public?: true
  end

  identities do
    identity :unique_name, [:name]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :is_system]
      validate present(:name)
    end

    update :update do
      accept [:name, :description]
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      get? true
      filter expr(name == ^arg(:name))
    end
  end
end
```

### 5.11 GroupMembership

```elixir
# lib/institutional_repository/accounts/group_membership.ex
defmodule InstitutionalRepository.Accounts.GroupMembership do
  use Ash.Resource,
    domain: InstitutionalRepository.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "group_memberships"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :expires_at, :naive_datetime, public?: true
    timestamps()
  end

  relationships do
    belongs_to :user,  InstitutionalRepository.Accounts.User,
      allow_nil?: false, public?: true
    belongs_to :group, InstitutionalRepository.Accounts.Group,
      allow_nil?: false, public?: true
  end

  identities do
    identity :unique_user_group, [:user_id, :group_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :group_id, :expires_at]
    end
  end
end
```

### 5.12 RbacPolicy (the database grant table)

> **Important naming**: This is the database table that stores grant records (who can do what on which resource). It is **not** Ash's built-in policy system. Renamed from `Policy` to `RbacPolicy` to avoid collision with the Ash framework's `Ash.Policy` namespace.

```elixir
# lib/institutional_repository/access/rbac_policy.ex
defmodule InstitutionalRepository.Access.RbacPolicy do
  use Ash.Resource,
    domain: InstitutionalRepository.Access,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rbac_policies"
    repo InstitutionalRepository.Repo
    custom_indexes do
      index [:resource_type, :resource_id]
      index [:group_id]
      index [:user_id]
    end
  end

  @resource_types ~w(Community Collection Item Bitstream)a
  @actions        ~w(read write delete admin)a
  @policy_types   ~w(custom embargo default)a

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :atom,
      constraints: [one_of: @resource_types],
      allow_nil?: false, public?: true
    attribute :resource_id,   :uuid, allow_nil?: false, public?: true

    # Principal (exactly one of group_id or user_id must be set)
    attribute :group_id, :uuid, public?: true
    attribute :user_id,  :uuid, public?: true

    attribute :action,      :atom,
      constraints: [one_of: @actions],
      allow_nil?: false, public?: true
    attribute :start_date,  :naive_datetime, public?: true
    attribute :end_date,    :naive_datetime, public?: true
    attribute :policy_type, :atom,
      constraints: [one_of: @policy_types],
      default: :custom, public?: true

    timestamps()
  end

  validations do
    validate InstitutionalRepository.Access.RbacPolicy.Validations.ExactlyOnePrincipal
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:resource_type, :resource_id, :group_id, :user_id,
              :action, :start_date, :end_date, :policy_type]
    end

    read :active_for_resource do
      argument :resource_type, :atom, allow_nil?: false
      argument :resource_id,   :uuid, allow_nil?: false

      filter expr(
        resource_type == ^arg(:resource_type) and
        resource_id   == ^arg(:resource_id) and
        (is_nil(start_date) or start_date <= ^NaiveDateTime.utc_now()) and
        (is_nil(end_date)   or end_date   >= ^NaiveDateTime.utc_now())
      )
    end
  end
end
```

#### Validation: ExactlyOnePrincipal

```elixir
defmodule InstitutionalRepository.Access.RbacPolicy.Validations.ExactlyOnePrincipal do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    group_id = Ash.Changeset.get_attribute(changeset, :group_id)
    user_id  = Ash.Changeset.get_attribute(changeset, :user_id)

    cond do
      is_nil(group_id) and is_nil(user_id) ->
        {:error, field: :group_id, message: "either group_id or user_id is required"}
      not is_nil(group_id) and not is_nil(user_id) ->
        {:error, field: :group_id, message: "cannot set both group_id and user_id"}
      true ->
        :ok
    end
  end
end
```

### 5.13 ViewEvent

```elixir
# lib/institutional_repository/analytics/view_event.ex
defmodule InstitutionalRepository.Analytics.ViewEvent do
  use Ash.Resource,
    domain: InstitutionalRepository.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "view_events"
    repo InstitutionalRepository.Repo
    custom_indexes do
      index [:resource_type, :resource_id]
      index [:inserted_at]
    end
  end

  @resource_types ~w(Item Bitstream)a

  attributes do
    uuid_primary_key :id

    attribute :resource_type, :atom,
      constraints: [one_of: @resource_types],
      allow_nil?: false, public?: true
    attribute :resource_id,   :uuid, allow_nil?: false, public?: true
    attribute :ip_hash,       :string, public?: true
    attribute :user_agent,    :string, public?: true
    attribute :referrer,      :string, public?: true
    attribute :country_code,  :string, public?: true

    create_timestamp :inserted_at
    # No updated_at needed for append-only event log
  end

  relationships do
    belongs_to :user, InstitutionalRepository.Accounts.User,
      allow_nil?: true, public?: true
  end

  aggregates do
    count :view_count, :id
  end

  actions do
    defaults [:read]

    create :track do
      accept [:resource_type, :resource_id, :ip_hash,
              :user_agent, :referrer, :country_code, :user_id]
      # Fire-and-forget: skip authorization for tracking
    end

    read :count_for_resource do
      argument :resource_type, :atom, allow_nil?: false
      argument :resource_id,   :uuid, allow_nil?: false

      prepare build(
        filter: expr(
          resource_type == ^arg(:resource_type) and
          resource_id   == ^arg(:resource_id)
        ),
        aggregate: [count: :id]
      )
    end
  end

  policies do
    policy action(:track) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:user_type, "admin")
      authorize_if actor_attribute_equals(:user_type, "superadmin")
    end
  end
end
```

---

## 6. Authorization — Ash Policy Checks

The original `Access.can?/3` function becomes a set of custom `Ash.Policy.Check` modules. These are referenced inside resource `policies` blocks.

### 6.1 CanRead Check (for Items)

```elixir
# lib/institutional_repository/access/policy_checks.ex
defmodule InstitutionalRepository.Access.PolicyChecks do
  defmodule CanRead do
    @moduledoc """
    Authorizes a read on an Item by consulting the rbac_policies table.
    Falls back to item.access_level for simple open/restricted checks.
    """
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "can read this item based on RBAC policies"

    @impl true
    def match?(actor, %{resource: resource, query: query}, _opts) do
      # For list reads, we let the data layer filter; for single-record checks
      # we do the full RBAC evaluation.
      case resource do
        InstitutionalRepository.Repository.Item ->
          # Open items: always allow
          # For non-open items: check RbacPolicy table
          item = query  # may be a record or a query
          check_item_access(actor, item)
        _ ->
          true
      end
    end

    defp check_item_access(_actor, item) when is_map(item) do
      case item.access_level do
        :open -> true
        _     -> false  # handled by row-level filter in query prep
      end
    end

    defp check_item_access(_actor, _query), do: true
  end

  defmodule CanReadBitstream do
    @moduledoc """
    Authorizes reading/downloading a Bitstream.
    Checks embargo dates and RBAC policies.
    """
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "can read this bitstream"

    @impl true
    def match?(_actor, _context, _opts), do: true
    # Detailed embargo + RBAC logic is enforced in the BitstreamController
    # (see Section 9) before calling Ash. The Ash policy here is a permissive
    # gate; the real logic lives in the controller where we have the full
    # request context (actor + loaded bitstream + item).
  end
end
```

### 6.2 PolicyManager (RbacPolicy helper)

This replaces the original `YourApp.Access.PolicyManager` context.

```elixir
# lib/institutional_repository/access/policy_manager.ex
defmodule InstitutionalRepository.Access.PolicyManager do
  alias InstitutionalRepository.Access
  alias InstitutionalRepository.Access.RbacPolicy
  alias InstitutionalRepository.Accounts

  @doc """
  Apply default read policies based on access_level.
  Call this after creating or updating an item's access_level.
  """
  def apply_access_level(resource, access_level) do
    resource_type = resource_type_atom(resource)
    resource_id   = resource.id

    anon_group  = Accounts.Group |> Ash.get!(Ash.Query.filter(name: "ANONYMOUS"))
    authed_group = Accounts.Group |> Ash.get!(Ash.Query.filter(name: "AUTHENTICATED"))

    # Remove existing default read policies
    RbacPolicy
    |> Ash.Query.filter(
      resource_type == ^resource_type and
      resource_id   == ^resource_id and
      action        == :read and
      policy_type   == :default
    )
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    case access_level do
      :open ->
        Ash.create!(RbacPolicy, %{
          resource_type: resource_type,
          resource_id:   resource_id,
          group_id:      anon_group.id,
          action:        :read,
          policy_type:   :default
        }, authorize?: false)

      :restricted ->
        Ash.create!(RbacPolicy, %{
          resource_type: resource_type,
          resource_id:   resource_id,
          group_id:      authed_group.id,
          action:        :read,
          policy_type:   :default
        }, authorize?: false)

      :closed ->
        :noop
    end
  end

  defp resource_type_atom(%InstitutionalRepository.Repository.Community{}), do: :Community
  defp resource_type_atom(%InstitutionalRepository.Repository.Collection{}), do: :Collection
  defp resource_type_atom(%InstitutionalRepository.Repository.Item{}),       do: :Item
  defp resource_type_atom(%InstitutionalRepository.Content.Bitstream{}),     do: :Bitstream
end
```

---

## 7. Migrations

**Do not write migrations by hand.** Ash generates them from your resource definitions.

```bash
# After defining or updating any resource:
mix ash.generate_migrations --name create_core_schema

# Apply migrations:
mix ash.migrate

# Or use standard Ecto migration apply:
mix ecto.migrate
```

Run `mix ash.generate_migrations` every time you add/change attributes, relationships, or identities in any resource. The generated migration files go into `priv/repo/migrations/` and are standard Ecto migrations — you can edit them before running.

### Key migration notes

- All tables use UUID primary keys (handled by `uuid_primary_key :id` in each resource).
- Indexes declared in `postgres do ... custom_indexes` blocks are included in the generated migration.
- The `rbac_policies` table is named so (not `policies`) to avoid collision with Ash internals.
- The `tokens` table is generated by `AshAuthentication.TokenResource` — do not create it manually.

---

## 8. Seeds (`priv/repo/seeds.exs`)

```elixir
# priv/repo/seeds.exs
alias InstitutionalRepository.Accounts
alias InstitutionalRepository.Accounts.{Group, User, GroupMembership}
alias InstitutionalRepository.Repository.{Community, Collection}

# ── System groups ─────────────────────────────────────────────────────────────
for name <- ["ANONYMOUS", "AUTHENTICATED", "ADMIN"] do
  case Ash.get(Group, Ash.Query.filter(Group, name: name), authorize?: false) do
    {:ok, _}   -> :skip
    {:error, _} ->
      Ash.create!(Group, %{name: name, is_system: true}, authorize?: false)
  end
end

# ── Admin user ────────────────────────────────────────────────────────────────
admin_group = Ash.get!(Group, Ash.Query.filter(Group, name: "ADMIN"), authorize?: false)

{:ok, admin} = AshAuthentication.Strategy.Password.register(
  User,
  %{
    email:                 "admin@yourinstitution.ac.id",
    password:              "ChangeMe123!",
    password_confirmation: "ChangeMe123!",
    full_name:             "System Administrator",
    user_type:             :superadmin
  },
  authorize?: false
)

Ash.create!(GroupMembership, %{user_id: admin.id, group_id: admin_group.id}, authorize?: false)

# ── Default community + collection ────────────────────────────────────────────
{:ok, community} = Ash.create(Community, %{
  name:   "Universitas Padjadjaran",
  handle: "123456789/0"
}, authorize?: false)

Ash.create!(Collection, %{
  name:         "Thesis & Dissertations",
  handle:       "123456789/1",
  community_id: community.id,
  description:  "Undergraduate and postgraduate thesis collection"
}, authorize?: false)

IO.puts("Seeds complete.")
```

---

## 9. MSSQL Data Import (`mix import_from_mssql`)

The import task is **not** an Ash resource. It uses the plain `LegacyRepo` (Ecto + TDS) to read `tbtMhsUploadThesis`, then calls Ash actions (using `authorize?: false`) to write records.

```elixir
# lib/mix/tasks/import_from_mssql.ex
defmodule Mix.Tasks.ImportFromMssql do
  use Mix.Task
  require Logger
  import Ecto.Query

  alias InstitutionalRepository.LegacyRepo
  alias InstitutionalRepository.LegacyThesis
  alias InstitutionalRepository.Repository.{Collection, Item, ItemKeyword, ItemAuthor}
  alias InstitutionalRepository.Content.Bitstream
  alias InstitutionalRepository.Access.PolicyManager

  @shortdoc "Import theses from tbtMhsUploadThesis into Ash resources"

  def run(args) do
    Mix.Task.run("app.start")
    opts = parse_args(args)

    Logger.info("=== Starting import from tbtMhsUploadThesis ===")

    collection = get_or_create_default_collection()
    theses     = load_legacy_theses(opts)
    total      = length(theses)

    Logger.info("Found #{total} theses to import")

    # Collect already-imported legacy IDs
    existing_ids =
      Item
      |> Ash.Query.filter(not is_nil(legacy_id))
      |> Ash.read!(authorize?: false)
      |> MapSet.new(& &1.legacy_id)

    theses
    |> Enum.reject(&MapSet.member?(existing_ids, &1.MhsNPM))
    |> Enum.with_index(1)
    |> Enum.each(fn {thesis, idx} ->
      case import_one(thesis, collection.id) do
        {:ok, _}    -> :ok
        {:error, e} -> Logger.error("Failed #{thesis.MhsNPM}: #{inspect(e)}")
      end
      print_progress(idx, total)
    end)

    Logger.info("\n=== Import complete! ===")
  end

  defp load_legacy_theses(opts) do
    status_filter = Keyword.get(opts, :status, "published")

    query = from t in LegacyThesis, order_by: [desc: t.UploadTgl]

    query =
      case status_filter do
        "published" -> where(query, [t], t.stPublikasi == true and t.Verifikasi == true)
        "all"       -> query
        _           -> where(query, [t], t.stPublikasi == true)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil   -> query
        limit -> limit(query, ^limit)
      end

    LegacyRepo.all(query)
  end

  defp get_or_create_default_collection do
    case Ash.get(Collection, Ash.Query.filter(Collection, name: "Thesis & Dissertations"),
           authorize?: false) do
      {:ok, c} ->
        c

      {:error, _} ->
        community = get_or_create_community()
        Ash.create!(Collection, %{
          name:         "Thesis & Dissertations",
          handle:       "123456789/1",
          community_id: community.id
        }, authorize?: false)
    end
  end

  defp get_or_create_community do
    case Ash.get(InstitutionalRepository.Repository.Community,
           Ash.Query.filter(InstitutionalRepository.Repository.Community, handle: "123456789/0"),
           authorize?: false) do
      {:ok, c} -> c
      {:error, _} ->
        Ash.create!(InstitutionalRepository.Repository.Community, %{
          name:   "Universitas Padjadjaran",
          handle: "123456789/0"
        }, authorize?: false)
    end
  end

  defp import_one(thesis, collection_id) do
    npm = thesis.MhsNPM

    # Use the :import action (no authorization check)
    item_attrs = %{
      legacy_id:        npm,
      idpustaka:        thesis.idpustaka,
      handle:           build_handle(npm),
      title:            clean_text(thesis.JudulBersih || thesis.Judul),
      title_raw:        thesis.Judul,
      abstract:         clean_text(thesis.AbstrakBersih || thesis.Abstrak),
      abstract_raw:     thesis.Abstrak,
      language:         parse_language(thesis.Bahasa),
      base_url:         thesis.LinkPath,
      item_type:        :thesis,
      degree_level:     infer_degree_level(npm),
      department:       extract_dept_code(npm),
      student_id:       npm,
      status:           determine_status(thesis),
      access_level:     :open,
      discoverable:     thesis.stPublikasi == true,
      date_submitted:   to_date(thesis.UploadTgl),
      publication_year: extract_year(npm, thesis.UploadTgl),
      embargo_open_date: thesis.EmbargoDate,
      collection_id:    collection_id,
      published_at:     thesis.UploadTgl
    }

    with {:ok, item} <- Ash.create(Item, item_attrs, action: :import, authorize?: false) do
      # Keywords
      if thesis.Keywords do
        thesis.Keywords
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.each(fn kw ->
          Ash.create!(ItemKeyword, %{item_id: item.id, keyword: kw},
            action: :import, authorize?: false)
        end)
      end

      # Author (student)
      Ash.create!(ItemAuthor, %{
        item_id:     item.id,
        author_name: npm,  # Replace with student_name lookup if available
        sequence:    1
      }, action: :import, authorize?: false)

      # Bitstreams
      base_url = thesis.LinkPath || ""

      file_mappings = [
        {thesis.FileAbstrak,    :ORIGINAL,       1, "Abstract PDF"},
        {thesis.FileFullText,   :ORIGINAL,       2, "Full Text PDF"},
        {thesis.FileCover,      :THUMBNAIL,      1, "Cover Image"},
        {thesis.FileBab1,       :CHAPTER,        1, "Chapter 1"},
        {thesis.FileBab2,       :CHAPTER,        2, "Chapter 2"},
        {thesis.FileBab3,       :CHAPTER,        3, "Chapter 3"},
        {thesis.FileBab4,       :CHAPTER,        4, "Chapter 4"},
        {thesis.FileBab5,       :CHAPTER,        5, "Chapter 5"},
        {thesis.FileBab6,       :CHAPTER,        6, "Chapter 6"},
        {thesis.FileDaftarIsi,  :SUPPLEMENTAL,   1, "Table of Contents"},
        {thesis.FileLampiran,   :SUPPLEMENTAL,   2, "Appendix"},
        {thesis.FilePustaka,    :SUPPLEMENTAL,   3, "Bibliography"},
        {thesis.FilePresentasi, :SUPPLEMENTAL,   4, "Presentation"},
        {thesis.FilePengesahan, :ADMINISTRATIVE, 1, "Approval Document"},
        {thesis.FileSurat,      :ADMINISTRATIVE, 2, "Official Letter"},
        {thesis.FileSuratIsi,   :ADMINISTRATIVE, 3, "Letter Content"},
      ]

      Enum.each(file_mappings, fn
        {nil, _, _, _}  -> :skip
        {"", _, _, _}   -> :skip
        {filename, bundle, seq, desc} ->
          Ash.create!(Bitstream, %{
            item_id:      item.id,
            filename:     filename,
            bundle_name:  bundle,
            sequence:     seq,
            description:  desc,
            storage_type: :url,
            storage_url:  Path.join(base_url, filename),
            mime_type:    guess_mime(filename),
            access_level: bitstream_access(bundle)
          }, action: :import, authorize?: false)
      end)

      # Apply open access policy (ANONYMOUS can read)
      PolicyManager.apply_access_level(item, :open)

      {:ok, item}
    end
  end

  # ── Helpers (same logic as original) ─────────────────────────────────────────

  defp build_handle(npm) do
    dept = String.slice(npm, 2, 4)
    "123456789/#{dept}/#{npm}"
  end

  defp extract_dept_code(npm), do: String.slice(npm, 2, 4)

  defp extract_year(npm, upload_tgl) do
    year_suffix = String.slice(npm, 0, 2)
    case Integer.parse(year_suffix) do
      {y, ""} when y >= 70 -> 1900 + y
      {y, ""} when y < 70  -> 2000 + y
      _ ->
        case upload_tgl do
          %NaiveDateTime{year: y} -> y
          _                       -> nil
        end
    end
  end

  defp infer_degree_level(npm) do
    dept = String.slice(npm, 2, 4)
    cond do
      String.starts_with?(dept, "70") -> :doctoral
      String.starts_with?(dept, "80") -> :master
      true                            -> :bachelor
    end
  end

  defp determine_status(%{stPublikasi: true, Verifikasi: true}), do: :published
  defp determine_status(%{stPublikasi: false}),                  do: :withdrawn
  defp determine_status(%{Verifikasi: false}),                   do: :under_review
  defp determine_status(_),                                      do: :submitted

  defp parse_language("Indonesia"),  do: "id"
  defp parse_language("Indonesian"), do: "id"
  defp parse_language("English"),    do: "en"
  defp parse_language(nil),          do: "id"
  defp parse_language(_),            do: "id"

  defp clean_text(nil),  do: nil
  defp clean_text(text), do:
    text |> String.replace(~r/\r\n|\r|\n/, " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
  defp to_date(nil), do: nil

  defp guess_mime(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".pdf"  -> "application/pdf"
      ".jpg"  -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png"  -> "image/png"
      ".doc"  -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      _       -> "application/octet-stream"
    end
  end

  defp bitstream_access(:ADMINISTRATIVE), do: :restricted
  defp bitstream_access(_),               do: :inherit

  defp parse_args(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [limit: :integer, status: :string])
    opts
  end

  defp print_progress(current, total) do
    pct    = div(current * 100, total)
    filled = div(50 * current, total)
    bar    = String.duplicate("█", filled) <> String.duplicate("░", 50 - filled)
    IO.write("\r[#{bar}] #{pct}% (#{current}/#{total})")
    if current == total, do: IO.puts("")
  end
end
```

---

## 10. Routing

### 10.1 Authentication Routes (AshAuthenticationPhoenix)

```elixir
# lib/institutional_repository_web/router.ex
defmodule InstitutionalRepositoryWeb.Router do
  use InstitutionalRepositoryWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InstitutionalRepositoryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session            # AshAuthentication: loads current_user from session
    plug InstitutionalRepositoryWeb.Plugs.TrackVisit
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer             # AshAuthentication: loads actor from Bearer token
  end

  pipeline :xml do
    plug :accepts, ["xml", "json"]
  end

  pipeline :require_auth do
    plug InstitutionalRepositoryWeb.Plugs.RequireAuth
  end

  pipeline :require_admin do
    plug InstitutionalRepositoryWeb.Plugs.RequireAdmin
  end

  # ── AshAuthentication routes (login, register, reset password, token) ───────
  ash_authentication_live_session :authentication_routes,
    on_mount: [{AshAuthentication.Phoenix.LiveSession, :maybe_authentication_live_view}] do
    sign_in_route(register_path: "/register", reset_path: "/forgot-password")
    sign_out_route(AuthController)
    auth_routes_for(InstitutionalRepository.Accounts.User, to: AuthController)
    reset_route []
  end

  # ── Public HTML routes ───────────────────────────────────────────────────────
  scope "/", InstitutionalRepositoryWeb do
    pipe_through :browser

    live "/",     HomeLive.Index
    live "/home", HomeLive.Index

    get "/handle/:prefix/:suffix",            HandleController, :resolve
    get "/handle/:prefix/:suffix/statistics", HandleController, :statistics

    get "/bitstream/handle/:prefix/:suffix/:filename",
        BitstreamController, :download_by_handle_filename
    get "/bitstream/handle/:prefix/:suffix/:sequence/:filename",
        BitstreamController, :download_by_handle

    get "/bitstreams/:id/download", BitstreamController, :download

    live "/items/:id",      ItemLive.Show
    live "/items/:id/full", ItemLive.ShowFull

    live "/communities",     CommunityLive.Index
    live "/communities/:id", CommunityLive.Show

    live "/collections/:id", CollectionLive.Show

    live "/browse",            BrowseLive.Index
    live "/browse/author",     BrowseLive.Author
    live "/browse/title",      BrowseLive.Title
    live "/browse/dateissued", BrowseLive.Date
    live "/browse/subject",    BrowseLive.Subject

    live "/search", SearchLive.Index

    live "/statistics",                 StatisticsLive.Index
    live "/statistics/items/:id",       StatisticsLive.Item
    live "/statistics/collections/:id", StatisticsLive.Collection

    live "/info/about",    InfoLive.About
    live "/info/privacy",  InfoLive.Privacy
    live "/info/help",     InfoLive.Help
  end

  # ── Authenticated routes ──────────────────────────────────────────────────────
  ash_authentication_live_session :authenticated_routes,
    on_mount: [{AshAuthentication.Phoenix.LiveSession, :live_no_user_callback},
               InstitutionalRepositoryWeb.LiveHooks.RequireAuth] do

    scope "/", InstitutionalRepositoryWeb do
      pipe_through [:browser, :require_auth]

      live "/mykiroku",                MyKirokuLive.Dashboard
      live "/items/:id/edit",          ItemLive.Edit
      live "/submit",                  SubmissionLive.SelectCollection
      live "/workspaceitems/:id",      SubmissionLive.Workspace
      live "/workspaceitems/:id/edit", SubmissionLive.Edit
      live "/workflowitems/:id",       WorkflowLive.Review
      live "/profile",                 ProfileLive.Show
      live "/profile/edit",            ProfileLive.Edit
      live "/collections/:id/submit",  SubmissionLive.New
    end
  end

  # ── Admin routes (AshAdmin) ───────────────────────────────────────────────────
  scope "/admin", InstitutionalRepositoryWeb do
    pipe_through [:browser, :require_admin]

    # AshAdmin auto-generates this panel from your resource definitions
    ash_admin "/",
      domains: [
        InstitutionalRepository.Repository,
        InstitutionalRepository.Accounts,
        InstitutionalRepository.Content,
        InstitutionalRepository.Access,
        InstitutionalRepository.Analytics,
      ]

    # Keep custom LiveViews for complex admin tasks not covered by AshAdmin
    live "/embargo",       Admin.EmbargoLive.Index
    live "/batch-import",  Admin.BatchImportLive.Index
  end

  # ── DSpace 7 REST API (AshJsonApi) ────────────────────────────────────────────
  scope "/server/api" do
    pipe_through :api

    forward "/", InstitutionalRepositoryWeb.AshJsonApiRouter
  end

  # ── OAI-PMH ──────────────────────────────────────────────────────────────────
  scope "/server/oai", InstitutionalRepositoryWeb do
    pipe_through :xml
    get "/request", OaiPmhController, :handle_request
  end

  scope "/oai", InstitutionalRepositoryWeb do
    pipe_through :xml
    get "/request", OaiPmhController, :handle_request
  end

  # ── Citation export ───────────────────────────────────────────────────────────
  scope "/", InstitutionalRepositoryWeb do
    pipe_through :browser
    get "/items/:id/export.bib", CitationController, :bibtex
    get "/items/:id/export.ris", CitationController, :ris
    get "/items/:id/export.enw", CitationController, :endnote
  end
end
```

---

## 11. Controllers

### 11.1 Handle Controller

```elixir
# lib/institutional_repository_web/controllers/handle_controller.ex
defmodule InstitutionalRepositoryWeb.HandleController do
  use InstitutionalRepositoryWeb, :controller

  alias InstitutionalRepository.Repository.{Item, Collection, Community}

  def resolve(conn, %{"prefix" => prefix, "suffix" => suffix}) do
    handle = "#{prefix}/#{suffix}"
    query  = URI.encode_query(conn.query_params)

    cond do
      {:ok, item} = Ash.get(Item, Ash.Query.filter(Item, handle: handle), authorize?: false) ->
        target = if query != "", do: "/items/#{item.id}?#{query}", else: "/items/#{item.id}"
        redirect(conn, to: target)

      {:ok, col} = Ash.get(Collection, Ash.Query.filter(Collection, handle: handle), authorize?: false) ->
        redirect(conn, to: "/collections/#{col.id}")

      {:ok, com} = Ash.get(Community, Ash.Query.filter(Community, handle: handle), authorize?: false) ->
        redirect(conn, to: "/communities/#{com.id}")

      true ->
        conn
        |> put_status(:not_found)
        |> put_view(html: InstitutionalRepositoryWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  def statistics(conn, %{"prefix" => prefix, "suffix" => suffix}) do
    handle = "#{prefix}/#{suffix}"
    item = Ash.get!(Item, Ash.Query.filter(Item, handle: handle), authorize?: false)
    redirect(conn, to: "/statistics/items/#{item.id}")
  end
end
```

### 11.2 Bitstream Controller

```elixir
# lib/institutional_repository_web/controllers/bitstream_controller.ex
defmodule InstitutionalRepositoryWeb.BitstreamController do
  use InstitutionalRepositoryWeb, :controller

  alias InstitutionalRepository.Content.Bitstream
  alias InstitutionalRepository.Repository.Item
  alias InstitutionalRepository.Access.{RbacPolicy, PolicyChecks}
  alias InstitutionalRepository.Analytics

  def download(conn, %{"id" => id}) do
    # Load bitstream and its parent item
    bitstream =
      Ash.get!(Bitstream, id, authorize?: false)
      |> Ash.load!(:item, authorize?: false)

    item   = bitstream.item
    actor  = conn.assigns[:current_user]

    # 1. Check embargo
    embargoed? = bitstream_embargoed?(bitstream)

    # 2. Check RBAC
    can_read? = rbac_can_read?(actor, bitstream, item)

    cond do
      not can_read? ->
        conn |> put_status(:forbidden) |> json(%{error: "Access denied"})

      embargoed? and not admin_or_override?(actor, item) ->
        conn |> put_status(:forbidden) |> json(%{error: "This file is under embargo"})

      true ->
        # Track the download event
        Analytics.ViewEvent
        |> Ash.create!(%{
          resource_type: :Bitstream,
          resource_id:   bitstream.id,
          ip_hash:       hash_ip(conn.remote_ip),
          user_agent:    get_req_header(conn, "user-agent") |> List.first(),
          user_id:       actor && actor.id
        }, action: :track, authorize?: false)

        # Serve the file
        serve_bitstream(conn, bitstream)
    end
  end

  def download_by_handle_filename(conn, %{
    "prefix" => prefix, "suffix" => suffix, "filename" => filename
  }) do
    handle = "#{prefix}/#{suffix}"
    item = Ash.get!(Item, Ash.Query.filter(Item, handle: handle), authorize?: false)

    bitstream =
      Bitstream
      |> Ash.Query.filter(item_id: item.id, filename: filename)
      |> Ash.read_one!(authorize?: false)

    # Redirect to canonical URL
    redirect(conn, to: "/bitstreams/#{bitstream.id}/download")
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp bitstream_embargoed?(bitstream) do
    today = Date.utc_today()
    open_blocked  = bitstream.embargo_open_date &&
                    Date.compare(today, bitstream.embargo_open_date) == :lt
    close_blocked = bitstream.embargo_close_date &&
                    Date.compare(today, bitstream.embargo_close_date) != :lt
    open_blocked || close_blocked
  end

  defp rbac_can_read?(actor, bitstream, item) do
    # Resolve effective access level
    effective_level =
      case bitstream.access_level do
        :inherit -> item.access_level
        level    -> level
      end

    case effective_level do
      :open -> true
      :restricted -> not is_nil(actor)
      :closed -> actor && actor.user_type in [:admin, :superadmin]
    end
  end

  defp admin_or_override?(actor, _item) do
    actor && actor.user_type in [:admin, :superadmin]
  end

  defp serve_bitstream(conn, bitstream) do
    case bitstream.storage_type do
      :url ->
        redirect(conn, external: bitstream.storage_url)

      :local ->
        send_file(conn, 200, bitstream.storage_path)

      :s3 ->
        {:ok, url} = ExAws.S3.presigned_url(
          ExAws.Config.new(:s3), :get,
          bitstream.storage_bucket, bitstream.storage_path,
          expires_in: 3600
        )
        redirect(conn, external: url)
    end
  end

  defp hash_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
```

---

## 12. LiveView Integration with AshPhoenix

`AshPhoenix` provides form helpers and query bindings for LiveView. This replaces manual `Ecto.Changeset`-based form handling.

### 12.1 Item Show LiveView

```elixir
# lib/institutional_repository_web/live/item_live/show.ex
defmodule InstitutionalRepositoryWeb.ItemLive.Show do
  use InstitutionalRepositoryWeb, :live_view

  alias InstitutionalRepository.Repository.Item
  alias InstitutionalRepository.Analytics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item =
      Ash.get!(Item, id,
        load: [:item_keywords, :item_authors, :item_advisors, :bitstreams],
        actor: socket.assigns[:current_user]
      )

    # Track view
    Analytics.ViewEvent
    |> Ash.create!(%{
      resource_type: :Item,
      resource_id:   item.id,
      user_id:       socket.assigns[:current_user]&.id
    }, action: :track, authorize?: false)

    {:ok, assign(socket, item: item, page_title: item.title)}
  end
end
```

### 12.2 Item Edit LiveView (AshPhoenix.Form)

```elixir
# lib/institutional_repository_web/live/item_live/edit.ex
defmodule InstitutionalRepositoryWeb.ItemLive.Edit do
  use InstitutionalRepositoryWeb, :live_view
  alias AshPhoenix.Form
  alias InstitutionalRepository.Repository.Item

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item = Ash.get!(Item, id, actor: socket.assigns.current_user)

    form =
      item
      |> Form.for_update(:update, as: "item", actor: socket.assigns.current_user)

    {:ok, assign(socket, form: form, item: item)}
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    form = Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"item" => params}, socket) do
    case Form.submit(socket.assigns.form, params: params) do
      {:ok, updated_item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item updated successfully.")
         |> push_navigate(to: ~p"/items/#{updated_item.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end
end
```

### 12.3 Search LiveView

```elixir
# lib/institutional_repository_web/live/search_live/index.ex
defmodule InstitutionalRepositoryWeb.SearchLive.Index do
  use InstitutionalRepositoryWeb, :live_view
  alias InstitutionalRepository.Repository.Item

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, results: [], loading: false, query: params["q"] || "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    term    = params["q"]
    dept    = params["department"]
    faculty = params["faculty"]
    year    = params["year"] && String.to_integer(params["year"])

    results =
      Item
      |> Ash.Query.for_read(:search, %{
        term:       term,
        department: dept,
        faculty:    faculty,
        year:       year
      }, actor: socket.assigns[:current_user])
      |> Ash.read!()

    {:noreply, assign(socket, results: results, query: term || "")}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: ~p"/search?q=#{q}")}
  end
end
```

---

## 13. Admin Panel — AshAdmin

`AshAdmin` auto-generates a full admin panel from your resource definitions with zero custom code for CRUD operations.

### 13.1 Enable AshAdmin on resources

Add `admin?` configuration blocks to resources you want visible in the admin panel:

```elixir
# In Community resource:
admin do
  show_action :read
  create_actions [:create]
  update_actions [:update]
  destroy_actions [:destroy]

  table_columns [:name, :handle, :is_active, :position]
  form do
    field :name, type: :text_input
    field :handle, type: :text_input
    field :description, type: :textarea
    field :is_active, type: :boolean
  end
end
```

```elixir
# In Item resource:
admin do
  show_action :read_all       # Use the admin-only action that sees all items
  update_actions [:update, :publish, :withdraw, :lift_embargo]
  read_actions [:read_all]

  table_columns [:title, :student_id, :status, :access_level, :publication_year, :department]

  form do
    field :title
    field :status, type: :select, values: ~w(draft submitted under_review published embargoed withdrawn)
    field :access_level, type: :select, values: ~w(open restricted closed)
    field :embargo_open_date, type: :date
    field :embargo_close_date, type: :date
    field :discoverable, type: :boolean
  end
end
```

```elixir
# In User resource:
admin do
  update_actions [:update_profile, :set_user_type, :deactivate]
  table_columns [:email, :full_name, :user_type, :active, :inserted_at]
end
```

### 13.2 Router registration

Already shown in Section 10 with:
```elixir
ash_admin "/",
  domains: [
    InstitutionalRepository.Repository,
    InstitutionalRepository.Accounts,
    InstitutionalRepository.Content,
    InstitutionalRepository.Access,
    InstitutionalRepository.Analytics,
  ]
```

This gives you a full `/admin` panel with listing, filtering, sorting, and CRUD forms for all registered resources.

---

## 14. REST API — AshJsonApi

`AshJsonApi` auto-generates DSpace 7-compatible REST routes from your resource definitions.

### 14.1 Add JSON:API to resources

```elixir
# In Item resource, add the extension:
use Ash.Resource,
  ...,
  extensions: [AshJsonApi.Resource]

json_api do
  type "items"

  routes do
    base "/items"
    get    :read
    index  :search
    post   :create
    patch  :update
    delete :destroy
  end
end
```

```elixir
# In Collection resource:
json_api do
  type "collections"
  routes do
    base "/collections"
    get   :read
    index :read
  end
end
```

```elixir
# In Community resource:
json_api do
  type "communities"
  routes do
    base "/communities"
    get   :read
    index :read
  end
end
```

### 14.2 AshJsonApi Router

```elixir
# lib/institutional_repository_web/ash_json_api_router.ex
defmodule InstitutionalRepositoryWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [
      InstitutionalRepository.Repository,
      InstitutionalRepository.Accounts,
      InstitutionalRepository.Content,
    ],
    open_api: "/open_api"
end
```

This router is forwarded from the main router at `/server/api` (see Section 10). It produces a JSON:API-compatible REST API with automatic OpenAPI documentation at `/server/api/open_api`.

---

## 15. Background Jobs — AshOban (Embargo Processor)

### 15.1 Oban Config

```elixir
# config/config.exs
config :institutional_repository, Oban,
  repo: InstitutionalRepository.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", InstitutionalRepository.Embargo.LifterWorker},
      {"30 2 * * *", InstitutionalRepository.Analytics.AggregatorWorker}
    ]}
  ],
  queues: [
    default:   10,
    import:    3,
    embargo:   2,
    analytics: 20
  ]
```

### 15.2 Embargo Lifter Worker

```elixir
# lib/institutional_repository/embargo/lifter_worker.ex
defmodule InstitutionalRepository.Embargo.LifterWorker do
  use Oban.Worker, queue: :embargo

  alias InstitutionalRepository.Repository.Item
  alias InstitutionalRepository.Content.Bitstream
  alias InstitutionalRepository.Access.PolicyManager

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    # Lift open embargoes whose date has passed
    Item
    |> Ash.Query.filter(status: :embargoed)
    |> Ash.Query.filter(not is_nil(embargo_open_date))
    |> Ash.Query.filter(embargo_open_date <= ^today)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn item ->
      {:ok, updated} = Ash.update(item, %{}, action: :lift_embargo, authorize?: false)

      # Clear embargo on bitstreams
      Bitstream
      |> Ash.Query.filter(item_id: item.id)
      |> Ash.Query.filter(not is_nil(embargo_open_date))
      |> Ash.Query.filter(embargo_open_date <= ^today)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn b ->
        Ash.update!(b, %{}, action: :lift_embargo, authorize?: false)
      end)

      # Re-apply access level policies
      PolicyManager.apply_access_level(updated, updated.access_level)
    end)

    # Close access for items whose close_embargo_date has passed
    Item
    |> Ash.Query.filter(not is_nil(embargo_close_date))
    |> Ash.Query.filter(embargo_close_date < ^today)
    |> Ash.Query.filter(status != :withdrawn)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn item ->
      Ash.update!(item, %{}, action: :withdraw, authorize?: false)
    end)

    :ok
  end
end
```

---

## 16. AshAuthentication Setup

### 16.1 Required config

```elixir
# config/runtime.exs
config :institutional_repository,
  token_signing_secret: System.fetch_env!("SECRET_KEY_BASE")
```

### 16.2 Auth Plug for LiveViews

```elixir
# lib/institutional_repository_web/plugs/require_auth.ex
defmodule InstitutionalRepositoryWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: "/sign-in")
      |> halt()
    end
  end
end
```

```elixir
# lib/institutional_repository_web/plugs/require_admin.ex
defmodule InstitutionalRepositoryWeb.Plugs.RequireAdmin do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.user_type in [:admin, :superadmin] do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(html: InstitutionalRepositoryWeb.ErrorHTML)
      |> render(:"403")
      |> halt()
    end
  end
end
```

### 16.3 LiveView on_mount hooks

```elixir
# lib/institutional_repository_web/live_hooks/require_auth.ex
defmodule InstitutionalRepositoryWeb.LiveHooks.RequireAuth do
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/sign-in")}
    end
  end
end
```

---

## 17. Legacy Ecto Schema (MSSQL, Read-Only)

This is a plain Ecto schema, not an Ash resource. It is only used in the import task.

```elixir
# lib/institutional_repository/legacy_thesis.ex
defmodule InstitutionalRepository.LegacyThesis do
  use Ecto.Schema

  @primary_key {:MhsNPM, :string, autogenerate: false}

  schema "tbtMhsUploadThesis" do
    field :FileAbstrak,    :string
    field :FileCover,      :string
    field :LinkPath,       :string
    field :Judul,          :string
    field :UploadTgl,      :naive_datetime
    field :FileSuratIsi,   :string
    field :FileSurat,      :string
    field :FileDaftarIsi,  :string
    field :FileBab1,       :string
    field :FileBab2,       :string
    field :FileBab3,       :string
    field :FileBab4,       :string
    field :FileBab5,       :string
    field :FileBab6,       :string
    field :FileLampiran,   :string
    field :FilePustaka,    :string
    field :FilePengesahan, :string
    field :FilePresentasi, :string
    field :FileFullText,   :string
    field :Abstrak,        :string
    field :Bahasa,         :string
    field :Keywords,       :string
    field :idpustaka,      :string
    field :TagPustaka,     :string
    field :stPublikasi,    :boolean
    field :Verifikasi,     :boolean
    field :Validasi,       :boolean
    field :JudulBersih,    :string
    field :AbstrakBersih,  :string
    field :EmbargoDate,    :date
    field :DataAge,        :integer
  end
end
```

---

## 18. OAI-PMH & Citation Export

These modules do not need to be Ash resources. They remain plain Phoenix controllers that call Ash read actions.

### 18.1 OAI-PMH Controller

```elixir
# lib/institutional_repository_web/controllers/oai_pmh_controller.ex
defmodule InstitutionalRepositoryWeb.OaiPmhController do
  use InstitutionalRepositoryWeb, :controller
  alias InstitutionalRepository.Repository.Item
  alias InstitutionalRepository.Oai.Builder

  def handle_request(conn, params) do
    verb = params["verb"]

    items =
      Item
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(status: :published, discoverable: true)
      |> Ash.Query.load([:item_keywords, :item_authors])
      |> Ash.read!(authorize?: false)

    xml = Builder.build(verb, items, params, conn)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
```

### 18.2 Citation Controller

```elixir
# lib/institutional_repository_web/controllers/citation_controller.ex
defmodule InstitutionalRepositoryWeb.CitationController do
  use InstitutionalRepositoryWeb, :controller
  alias InstitutionalRepository.Repository.Item

  def bibtex(conn, %{"id" => id}) do
    item    = Ash.get!(Item, id, load: [:item_authors, collection: :community], authorize?: false)
    authors = item.item_authors |> Enum.map(& &1.author_name) |> Enum.join(" and ")
    year    = item.publication_year || ""

    content = """
    @phdthesis{#{String.replace(item.handle, "/", "_")},
      title    = {#{item.title}},
      author   = {#{authors}},
      year     = {#{year}},
      school   = {#{item.collection.community.name}},
      url      = {https://yourrepo.ac.id/handle/#{item.handle}}
    }
    """

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("content-disposition",
       ~s|attachment; filename="citation_#{item.student_id || item.id}.bib"|)
    |> send_resp(200, content)
  end

  def ris(conn, %{"id" => id}) do
    item    = Ash.get!(Item, id, load: [:item_authors, collection: :community], authorize?: false)
    authors = item.item_authors |> Enum.map(&"AU  - #{&1.author_name}\n") |> Enum.join()

    content = """
    TY  - THES
    TI  - #{item.title}
    #{authors}PY  - #{item.publication_year}
    PB  - #{item.collection.community.name}
    UR  - https://yourrepo.ac.id/handle/#{item.handle}
    ER  -
    """

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("content-disposition",
       ~s|attachment; filename="citation_#{item.student_id || item.id}.ris"|)
    |> send_resp(200, content)
  end
end
```

---

## 19. Full-Text Search

For PostgreSQL (AshPostgres), full-text search is handled with a fragment inside the `Search` preparation (see Section 5.3).

For an MSSQL-primary deployment using `Ash.DataLayer.Ecto`, override the preparation:

```elixir
# In the Search preparation, detect adapter:
case Application.get_env(:institutional_repository, :db_adapter, :postgres) do
  :mssql ->
    Ash.Query.filter(q, expr(
      fragment("CONTAINS((title, abstract), ?)", ^term)
    ))
  :postgres ->
    Ash.Query.filter(q, expr(
      fragment(
        "to_tsvector('indonesian', coalesce(title,'') || ' ' || coalesce(abstract,'')) @@ plainto_tsquery(?)",
        ^term
      )
    ))
end
```

---

## 20. Generating & Running Migrations

```bash
# 1. Install Ash (first time only)
mix ash.install

# 2. After defining all resources, generate migrations
mix ash.generate_migrations --name create_core_schema

# 3. Review generated files in priv/repo/migrations/

# 4. Apply migrations
mix ash.migrate

# 5. Seed the database
mix run priv/repo/seeds.exs

# 6. Run the import
mix import_from_mssql
# or test with limit:
mix import_from_mssql --limit 50

# 7. Verify
mix run -e "
  IO.inspect Ash.count!(InstitutionalRepository.Repository.Item, authorize?: false)
"
```

---

## 21. Deployment Checklist

### Environment Variables

```
DATABASE_URL          → PostgreSQL connection string
MSSQL_HOST / MSSQL_DB / MSSQL_USER / MSSQL_PASS → Legacy MSSQL (import only)
SECRET_KEY_BASE       → Generate with: mix phx.gen.secret
PHX_HOST              → Your domain name
PHX_PORT              → Default 4000
POOL_SIZE             → Default 10
```

### Pre-launch Steps

1. Run `mix ash.generate_migrations` to ensure all migration files are up to date.
2. Run `mix ash.migrate` in production.
3. Run seeds: `mix run priv/repo/seeds.exs`.
4. Run import: `mix import_from_mssql`.
5. Verify handle resolution for your top-cited theses:
   `curl -I https://yourrepo.ac.id/handle/123456789/...`
6. Verify OAI-PMH: `curl https://yourrepo.ac.id/server/oai/request?verb=Identify`
7. Verify Oban jobs running: query `oban_jobs` table.
8. Log in as a non-admin user and confirm restricted items show no download button.
9. Switch Nginx to point at Phoenix (same config as original guide — unchanged).

---

## 22. Schema Relationship Summary (Ash Edition)

```
Domain: Repository
  Community
    └─ belongs_to parent Community (self-referential)
    └─ has_many Collections

  Collection
    └─ belongs_to Community
    └─ has_many Items

  Item  ← core record (maps from tbtMhsUploadThesis)
    └─ belongs_to Collection
    └─ belongs_to User (submitter)
    └─ has_many ItemKeywords
    └─ has_many ItemAuthors
    └─ has_many ItemAdvisors
    └─ has_many Bitstreams (from Content domain)
    └─ has_many ItemMetadata
    └─ calculate :files_embargoed? (boolean)

Domain: Content
  Bitstream
    └─ belongs_to Item
    └─ storage_type: url | s3 | local (atom)
    └─ access_level: inherit | open | restricted | closed (atom)
    └─ calculate :resolved_url
    └─ calculate :files_embargoed?

Domain: Accounts
  User (AshAuthentication managed)
    └─ has_many GroupMemberships → Groups
    └─ has_many submitted Items

  Group
    └─ has_many GroupMemberships → Users
    └─ System groups: ANONYMOUS, AUTHENTICATED, ADMIN

  GroupMembership (join table with expires_at)
  Token (AshAuthentication managed)

Domain: Access
  RbacPolicy (the database grant table)
    └─ resource_type: Community | Collection | Item | Bitstream
    └─ resource_id: UUID of the resource
    └─ principal: group_id XOR user_id (exactly one)
    └─ action: read | write | delete | admin
    └─ time window: start_date / end_date (embargo-style grants)
    └─ policy_type: custom | embargo | default

Domain: Analytics
  ViewEvent (append-only event log)
    └─ resource_type: Item | Bitstream
    └─ resource_id: UUID

Authorization model:
  Ash.Policy.Authorizer runs on every Ash action.
  Policies inside each resource define who can do what.
  The RbacPolicy table holds dynamic grants consulted by custom Check modules.
  PolicyManager.apply_access_level/2 syncs RbacPolicy rows when access_level changes.
```

---

## 23. Quick Reference: Ash Patterns for Your Coding Agent

These are the exact call patterns your agent should use throughout the codebase.

```elixir
# READ — single record by ID
Ash.get!(Item, id, actor: current_user)
Ash.get!(Item, id, authorize?: false)  # trusted internal calls

# READ — single record by filter
Ash.get!(Item, Ash.Query.filter(Item, handle: "123456789/0"), authorize?: false)

# READ — list with named read action
Item |> Ash.Query.for_read(:search, %{term: "neural network"}, actor: current_user) |> Ash.read!()

# READ — with preloads
Ash.get!(Item, id, load: [:item_keywords, :item_authors, :bitstreams], actor: actor)

# CREATE — default create action
Ash.create!(Item, %{title: "My Thesis", collection_id: cid}, actor: current_user)

# CREATE — named action
Ash.create!(Item, %{...attrs...}, action: :import, authorize?: false)

# UPDATE — named action
Ash.update!(item, %{status: :published}, action: :publish, actor: current_user)

# UPDATE — default update
Ash.update!(item, %{title: "New Title"}, actor: current_user)

# DESTROY
Ash.destroy!(item, actor: current_user)

# BULK DESTROY
Item |> Ash.Query.filter(status: :draft) |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

# COUNT
Ash.count!(Item, authorize?: false)

# AshPhoenix form (in LiveView)
form = AshPhoenix.Form.for_create(Item, :create, as: "item", actor: current_user)
form = AshPhoenix.Form.for_update(item,  :update, as: "item", actor: current_user)
form = AshPhoenix.Form.validate(form, params)
{:ok, record} = AshPhoenix.Form.submit(form, params: params)
```
