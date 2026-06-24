# Kiroku — Institutional Repository Architecture

## Phoenix + Ecto Edition: Lean, Stable, Reliable

---

## 0. Design Principles

- **Plain Phoenix + Ecto** — no framework abstraction over Ecto. Context modules call `Repo.*` directly.
- **Schemas are data shapes** — `Ecto.Schema` + `Ecto.Changeset` validate data, nothing more.
- **Contexts are the API** — business logic lives in context functions, not in controllers or LiveViews.
- **Authorization is explicit** — `Kiroku.Access.Authorization.can?/3` is called before every mutation, in the LiveView or controller, not buried in data functions.
- **Migrations are source of truth** — every DB change goes through `mix ecto.gen.migration`.

---

## 1. Dependencies — `mix.exs`

```elixir
defp deps do
  [
    # ── Phoenix Core ──────────────────────────────────────────────────────────
    {:phoenix, "~> 1.8"},
    {:phoenix_live_view, "~> 1.0"},
    {:phoenix_live_dashboard, "~> 0.8"},
    {:phoenix_html, "~> 4.1"},
    {:bandit, ">= 0.0.0"},

    # ── Ecto + Database ───────────────────────────────────────────────────────
    {:ecto_sql, "~> 3.12"},
    {:postgrex, ">= 0.0.0"},
    {:tds, "~> 2.3"},               # MSSQL — legacy import only

    # ── Authentication ────────────────────────────────────────────────────────
    {:bcrypt_elixir, "~> 3.0"},     # Password hashing (phx_gen_auth pattern)

    # ── Background Jobs ───────────────────────────────────────────────────────
    {:oban, "~> 2.18"},

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
    {:phoenix_live_reload, "~> 1.2", only: :dev},
    {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
    {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
    {:floki, ">= 0.30.0", only: :test},
    {:ex_machina, "~> 2.8", only: :test},
  ]
end
```

> **No Ash, no Guardian, no AshAuthentication.** Password hashing is handled directly by `bcrypt_elixir`. Auth sessions use the `phx_gen_auth`-generated `UserAuth` plug and `UserToken` schema.

---

## 2. Application Structure

```
lib/
  kiroku/
    # ── Context Modules (business logic & data access) ──────────────────────
    repository.ex         # Context: Community, Collection, Item queries
    accounts.ex           # Context: User, UserToken, session management
    content.ex            # Context: Bitstream (file records)
    access.ex             # Context: RbacPolicy grants
    analytics.ex          # Context: ViewEvent recording

    # ── Ecto Schemas ───────────────────────────────────────────────────────
    repository/
      community.ex
      collection.ex
      item.ex
      item_keyword.ex
      item_author.ex
      item_advisor.ex
      item_examiner.ex      # NEW — not in legacy DB
      item_team_member.ex   # NEW — not in legacy DB
      item_metadata.ex      # Supplementary key-value metadata rows
    content/
      bitstream.ex
    accounts/
      user.ex
      user_token.ex
    access/
      rbac_policy.ex
      authorization.ex      # can?/3 helper — all auth checks go here
    analytics/
      view_event.ex

    # ── Legacy (MSSQL read-only, import only) ─────────────────────────────
    legacy_repo.ex          # Plain Ecto.Repo, TDS adapter
    legacy_thesis.ex        # Plain Ecto.Schema for tbtMhsUploadThesis

    # ── Supporting Modules ────────────────────────────────────────────────
    embargo/
      lifter_worker.ex      # Oban worker — lifts embargoes on schedule
    oai/
      builder.ex            # OAI-PMH XML response builder
    export/
      citation.ex           # Citation format generators (APA, IEEE, etc.)
    storage/
      uploader.ex           # S3 / local file upload abstraction

    # ── Repo ──────────────────────────────────────────────────────────────
    repo.ex                 # Primary Ecto.Repo (PostgreSQL)

  kiroku_web/
    router.ex
    user_auth.ex            # Auth plugs (phx_gen_auth pattern)
    controllers/
      page_controller.ex
      handle_controller.ex    # DSpace handle resolver → redirects
      bitstream_controller.ex # Serves file downloads with access checks
      oai_pmh_controller.ex
      citation_controller.ex
      api/
        v1/
          community_controller.ex
          collection_controller.ex
          item_controller.ex
    live/
      community_live/
        index.ex
        show.ex
      collection_live/
        show.ex
      item_live/
        show.ex           # Public item detail page
        index.ex          # Admin item list
        review.ex         # Admin review/approve
      browse_live.ex
      search_live.ex
      submission_live/
        new.ex            # Multi-step submission wizard
        edit.ex
        index.ex          # "My Submissions"
      user_login_live.ex
      user_registration_live.ex
      user_forgot_password_live.ex
      user_reset_password_live.ex
      admin/
        dashboard_live.ex
        community_live/
          index.ex
          new.ex
          edit.ex
        collection_live/
          index.ex
          new.ex
          edit.ex
        item_live/
          index.ex
          show.ex
          review.ex
        user_live/
          index.ex
          show.ex
    components/
      layouts.ex
      core_components.ex
      item_card.ex
      bitstream_list.ex
      search_filters.ex
      citation_widget.ex

priv/
  repo/
    migrations/
    seeds.exs

lib/mix/tasks/
  import_from_mssql.ex
```

---

## 3. Repos & Database Configuration

### 3.1 Primary Repo (PostgreSQL)

```elixir
# lib/kiroku/repo.ex
defmodule Kiroku.Repo do
  use Ecto.Repo,
    otp_app: :kiroku,
    adapter: Ecto.Adapters.Postgres
end
```

### 3.2 Legacy Repo (MSSQL — read-only, import-time only)

```elixir
# lib/kiroku/legacy_repo.ex
defmodule Kiroku.LegacyRepo do
  use Ecto.Repo,
    otp_app: :kiroku,
    adapter: Ecto.Adapters.Tds
end
```

This is a **read-only** Ecto repo started only during the import Mix task. It is never called from web request paths.

### 3.3 Application Supervisor

```elixir
# lib/kiroku/application.ex
children = [
  Kiroku.Repo,
  KirokuWeb.Telemetry,
  {DNSCluster, query: Application.get_env(:kiroku, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: Kiroku.PubSub},
  KirokuWeb.Endpoint,
  {Oban, Application.fetch_env!(:kiroku, Oban)},
]

# LegacyRepo is started explicitly in mix import_from_mssql, NOT here
```

### 3.4 Runtime Config

```elixir
# config/runtime.exs
config :kiroku, Kiroku.Repo,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
  ssl: String.to_existing_atom(System.get_env("DB_SSL", "false"))

# MSSQL (import-time only — not in prod supervision tree)
config :kiroku, Kiroku.LegacyRepo,
  adapter: Ecto.Adapters.Tds,
  hostname: System.get_env("MSSQL_HOST"),
  database: System.get_env("MSSQL_DB"),
  username: System.get_env("MSSQL_USER"),
  password: System.get_env("MSSQL_PASS"),
  port: 1433,
  pool_size: 2

config :kiroku, Oban,
  repo: Kiroku.Repo,
  queues: [default: 10, embargo: 2, notifications: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]
```

---

## 4. Ecto Schemas

### 4.1 Community

```elixir
# lib/kiroku/repository/community.ex
defmodule Kiroku.Repository.Community do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "communities" do
    field :name,              :string
    field :handle,            :string
    field :short_description, :string
    field :description,       :string
    field :logo_bitstream_id, :binary_id
    field :position,          :integer, default: 0
    field :is_active,         :boolean, default: true

    belongs_to :parent_community, __MODULE__
    has_many   :subcommunities, __MODULE__, foreign_key: :parent_community_id
    has_many   :collections, Kiroku.Repository.Collection

    timestamps()
  end

  def changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :handle, :short_description, :description,
                    :logo_bitstream_id, :position, :parent_community_id, :is_active])
    |> validate_required([:name])
    |> unique_constraint(:handle)
  end
end
```

### 4.2 Collection

```elixir
# lib/kiroku/repository/collection.ex
defmodule Kiroku.Repository.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "collections" do
    field :name,              :string
    field :handle,            :string
    field :short_description, :string
    field :description,       :string
    field :logo_bitstream_id, :binary_id
    field :license_text,      :string
    field :position,          :integer, default: 0
    field :is_active,         :boolean, default: true

    belongs_to :community, Kiroku.Repository.Community
    has_many   :items, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :handle, :short_description, :description,
                    :logo_bitstream_id, :license_text, :position,
                    :community_id, :is_active])
    |> validate_required([:name, :community_id])
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:community_id)
  end
end
```

### 4.3 Item

```elixir
# lib/kiroku/repository/item.ex
defmodule Kiroku.Repository.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @item_types ~w(
    skripsi tesis disertasi tugas_akhir
    memorandum_hukum studi_kasus laporan_proyek karya_kreatif
    karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone
  )a

  @status_values ~w(draft submitted under_review published embargoed withdrawn)a
  @access_values ~w(open restricted closed)a
  @degree_values ~w(d3 d4 s1_terapan s1 s2 s3)a
  @language_values ~w(id en)a

  schema "items" do
    field :handle,            :string
    field :legacy_id,         :string
    field :idpustaka,         :string

    # Bibliographic
    field :title,             :string
    field :title_alt,         :string
    field :abstract,          :string
    field :abstract_alt,      :string
    field :language,          Ecto.Enum, values: @language_values, default: :id

    # Classification
    field :item_type,         Ecto.Enum, values: @item_types, default: :skripsi
    field :degree_level,      Ecto.Enum, values: @degree_values
    field :department,        :string
    field :faculty,           :string
    field :program_study,     :string
    field :institution,       :string

    # Student
    field :student_id,        :string
    field :student_name,      :string

    # Type-specific scalars (nullable — only set for relevant types)
    field :legal_subject_matter,  Ecto.Enum, values: ~w(pidana perdata tata_negara internasional bisnis adat agraria lingkungan)a
    field :case_reference,        :string
    field :court_level,           Ecto.Enum, values: ~w(pn pt ma mk ptun arbitrase bani icc)a
    field :journal_name,          :string
    field :issn,                  :string
    field :eissn,                 :string
    field :doi,                   :string
    field :volume,                :string
    field :issue,                 :string
    field :page_start,            :integer
    field :page_end,              :integer
    field :publisher,             :string
    field :place_of_publication,  :string
    field :isbn,                  :string
    field :conference_name,       :string
    field :conference_location,   :string
    field :conference_date,       :string
    field :sinta_accreditation,   Ecto.Enum, values: ~w(s1 s2 s3 s4 s5 s6)a
    field :scopus_indexed,        :boolean, default: false
    field :wos_indexed,           :boolean, default: false
    field :quartile,              Ecto.Enum, values: ~w(q1 q2 q3 q4)a
    field :patent_number,         :string
    field :hki_number,            :string
    field :artwork_medium,        :string
    field :artwork_dimensions,    :string
    field :research_location,     :string
    field :research_period,       :string
    field :funding_source,        :string
    field :subject_classification,:string
    field :thesis_type_detail,    Ecto.Enum, values: ~w(kuantitatif kualitatif mixed_methods rnd ptk)a
    field :mbkm_scheme,           Ecto.Enum, values: ~w(magang kkn_t penelitian proyek_independen pertukaran_mahasiswa wirausaha)a
    field :capstone_partner,      :string

    # Lifecycle
    field :status,            Ecto.Enum, values: @status_values, default: :draft
    field :access_level,      Ecto.Enum, values: @access_values, default: :open
    field :discoverable,      :boolean, default: true
    field :withdrawn,         :boolean, default: false

    # Dates
    field :date_submitted,    :date
    field :date_issued,       :date
    field :date_available,    :date
    field :publication_year,  :integer
    field :published_at,      :naive_datetime

    # Embargo
    field :embargo_open_date,  :date
    field :embargo_close_date, :date
    field :embargo_reason,     :string

    # Legacy import source
    field :base_url,           :string

    belongs_to :collection, Kiroku.Repository.Collection
    belongs_to :submitter,  Kiroku.Accounts.User

    has_many :item_keywords,    Kiroku.Repository.ItemKeyword
    has_many :item_authors,     Kiroku.Repository.ItemAuthor
    has_many :item_advisors,    Kiroku.Repository.ItemAdvisor
    has_many :item_examiners,   Kiroku.Repository.ItemExaminer
    has_many :item_team_members,Kiroku.Repository.ItemTeamMember
    has_many :bitstreams,       Kiroku.Content.Bitstream
    has_many :metadata_extras,  Kiroku.Repository.ItemMetadata

    timestamps()
  end

  @required_fields ~w(title collection_id)a
  @optional_fields ~w(
    handle legacy_id idpustaka title_alt abstract abstract_alt language
    item_type degree_level department faculty program_study institution
    student_id student_name
    legal_subject_matter case_reference court_level journal_name issn eissn
    doi volume issue page_start page_end publisher place_of_publication isbn
    conference_name conference_location conference_date sinta_accreditation
    scopus_indexed wos_indexed quartile patent_number hki_number
    artwork_medium artwork_dimensions research_location research_period
    funding_source subject_classification thesis_type_detail
    mbkm_scheme capstone_partner
    status access_level discoverable withdrawn
    date_submitted date_issued date_available publication_year published_at
    embargo_open_date embargo_close_date embargo_reason
    base_url submitter_id
  )a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:collection_id)
    |> foreign_key_constraint(:submitter_id)
  end

  # Looser changeset for the MSSQL import task — skips collection_id requirement
  def import_changeset(item, attrs) do
    item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required([:title])
    |> unique_constraint(:handle)
  end

  # Helpers for embargo state
  def files_embargoed?(%__MODULE__{} = item) do
    today = Date.utc_today()
    open_blocked  = item.embargo_open_date &&
                    Date.compare(today, item.embargo_open_date) == :lt
    close_blocked = item.embargo_close_date &&
                    Date.compare(today, item.embargo_close_date) != :lt
    open_blocked || close_blocked || false
  end
end
```

### 4.4 ItemKeyword

```elixir
# lib/kiroku/repository/item_keyword.ex
defmodule Kiroku.Repository.ItemKeyword do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_keywords" do
    field :keyword,  :string
    field :language, Ecto.Enum, values: [:id, :en], default: :id
    field :position, :integer, default: 0

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(keyword, attrs) do
    keyword
    |> cast(attrs, [:keyword, :language, :position, :item_id])
    |> validate_required([:keyword, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.5 ItemAuthor

```elixir
# lib/kiroku/repository/item_author.ex
defmodule Kiroku.Repository.ItemAuthor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_authors" do
    field :author_name,      :string
    field :author_name_alt,  :string
    field :affiliation,      :string
    field :orcid,            :string
    field :scopus_author_id, :string
    field :sequence,         :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(author, attrs) do
    author
    |> cast(attrs, [:author_name, :author_name_alt, :affiliation,
                    :orcid, :scopus_author_id, :sequence, :item_id])
    |> validate_required([:author_name, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.6 ItemAdvisor

```elixir
# lib/kiroku/repository/item_advisor.ex
defmodule Kiroku.Repository.ItemAdvisor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(main_advisor co_advisor external)a

  schema "item_advisors" do
    field :advisor_name,     :string
    field :advisor_name_alt, :string
    field :advisor_role,     Ecto.Enum, values: @roles, default: :main_advisor
    field :affiliation,      :string
    field :nidn,             :string
    field :sequence,         :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(advisor, attrs) do
    advisor
    |> cast(attrs, [:advisor_name, :advisor_name_alt, :advisor_role,
                    :affiliation, :nidn, :sequence, :item_id])
    |> validate_required([:advisor_name, :advisor_role, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.7 ItemExaminer (New)

```elixir
# lib/kiroku/repository/item_examiner.ex
defmodule Kiroku.Repository.ItemExaminer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_examiners" do
    field :examiner_name,     :string
    field :examiner_name_alt, :string
    field :affiliation,       :string
    field :nidn,              :string
    field :sequence,          :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(examiner, attrs) do
    examiner
    |> cast(attrs, [:examiner_name, :examiner_name_alt, :affiliation,
                    :nidn, :sequence, :item_id])
    |> validate_required([:examiner_name, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.8 ItemTeamMember (New)

```elixir
# lib/kiroku/repository/item_team_member.ex
defmodule Kiroku.Repository.ItemTeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(lead_developer developer designer researcher tester other)a

  schema "item_team_members" do
    field :member_name,     :string
    field :member_name_alt, :string
    field :role,            Ecto.Enum, values: @roles, default: :developer
    field :student_id,      :string
    field :affiliation,     :string
    field :sequence,        :integer, default: 1

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:member_name, :member_name_alt, :role, :student_id,
                    :affiliation, :sequence, :item_id])
    |> validate_required([:member_name, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.9 ItemMetadata (Supplementary key-value rows)

```elixir
# lib/kiroku/repository/item_metadata.ex
defmodule Kiroku.Repository.ItemMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "item_metadata_extras" do
    field :field_schema,    :string   # e.g. "dc", "local"
    field :field_element,   :string   # e.g. "description", "relation"
    field :field_qualifier, :string   # e.g. "dedication", "uri"
    field :field_value,     :string
    field :language,        :string
    field :position,        :integer, default: 0

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(meta, attrs) do
    meta
    |> cast(attrs, [:field_schema, :field_element, :field_qualifier,
                    :field_value, :language, :position, :item_id])
    |> validate_required([:field_schema, :field_element, :field_value, :item_id])
    |> foreign_key_constraint(:item_id)
  end
end
```

### 4.10 Bitstream

```elixir
# lib/kiroku/content/bitstream.ex
defmodule Kiroku.Content.Bitstream do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @bundle_names ~w(ORIGINAL THUMBNAIL CHAPTER SUPPLEMENTAL ADMINISTRATIVE LICENSE MEDIA SOURCE)a
  @access_values ~w(open inherit restricted closed)a
  @storage_types ~w(url s3 local)a

  schema "bitstreams" do
    field :filename,          :string
    field :bundle_name,       Ecto.Enum, values: @bundle_names, default: :ORIGINAL
    field :sequence,          :integer, default: 1
    field :description,       :string
    field :mime_type,         :string
    field :file_size,         :integer
    field :checksum,          :string
    field :checksum_algorithm,:string, default: "MD5"

    field :storage_type,      Ecto.Enum, values: @storage_types, default: :s3
    field :storage_url,       :string   # For :url type (external links)
    field :storage_path,      :string   # S3 key or filesystem path
    field :storage_bucket,    :string   # S3 bucket

    field :access_level,      Ecto.Enum, values: @access_values, default: :inherit
    field :embargo_open_date, :date
    field :embargo_close_date,:date

    belongs_to :item, Kiroku.Repository.Item

    timestamps()
  end

  def changeset(bitstream, attrs) do
    bitstream
    |> cast(attrs, [:filename, :bundle_name, :sequence, :description,
                    :mime_type, :file_size, :checksum, :checksum_algorithm,
                    :storage_type, :storage_url, :storage_path, :storage_bucket,
                    :access_level, :embargo_open_date, :embargo_close_date,
                    :item_id])
    |> validate_required([:filename, :bundle_name, :sequence, :storage_type, :item_id])
    |> enforce_bundle_access_rules()
    |> foreign_key_constraint(:item_id)
  end

  # THUMBNAIL is always open; ADMINISTRATIVE and LICENSE are always restricted.
  # These rules cannot be overridden.
  defp enforce_bundle_access_rules(changeset) do
    case get_field(changeset, :bundle_name) do
      :THUMBNAIL ->
        put_change(changeset, :access_level, :open)
      bundle when bundle in [:ADMINISTRATIVE, :LICENSE] ->
        put_change(changeset, :access_level, :restricted)
      _ ->
        changeset
    end
  end
end
```

### 4.11 User

```elixir
# lib/kiroku/accounts/user.ex
defmodule Kiroku.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @user_types ~w(submitter reviewer admin superadmin)a

  schema "users" do
    field :email,           :string
    field :password,        :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at,    :naive_datetime

    field :user_type,       Ecto.Enum, values: @user_types, default: :submitter
    field :display_name,    :string
    field :student_id,      :string
    field :faculty,         :string
    field :department,      :string
    field :avatar_url,      :string

    has_many :items,  Kiroku.Repository.Item, foreign_key: :submitter_id
    has_many :tokens, Kiroku.Accounts.UserToken

    timestamps()
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :display_name, :student_id, :faculty, :department])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :student_id, :faculty, :department, :avatar_url])
    |> validate_required([:display_name])
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
end
```

### 4.12 RbacPolicy

```elixir
# lib/kiroku/access/rbac_policy.ex
defmodule Kiroku.Access.RbacPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @policy_actions ~w(read submit review publish manage)a
  @resource_types ~w(community collection item global)a

  schema "rbac_policies" do
    field :resource_type, Ecto.Enum, values: @resource_types
    field :resource_id,   :binary_id   # nil = applies globally
    field :action,        Ecto.Enum, values: @policy_actions
    field :notes,         :string

    belongs_to :user,  Kiroku.Accounts.User
    # OR
    belongs_to :group, Kiroku.Accounts.Group

    timestamps()
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:resource_type, :resource_id, :action, :notes, :user_id, :group_id])
    |> validate_required([:resource_type, :action])
  end
end
```

---

## 5. Context Modules

### 5.1 Repository Context

```elixir
# lib/kiroku/repository.ex
defmodule Kiroku.Repository do
  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Repository.{Community, Collection, Item, ItemKeyword,
                             ItemAuthor, ItemAdvisor, ItemMetadata}

  # ── Communities ────────────────────────────────────────────────────────────

  def list_communities do
    Repo.all(from c in Community, where: c.is_active == true, order_by: c.position)
  end

  def get_community!(id), do: Repo.get!(Community, id)

  def get_community_by_handle!(handle), do: Repo.get_by!(Community, handle: handle)

  def create_community(attrs) do
    %Community{}
    |> Community.changeset(attrs)
    |> Repo.insert()
  end

  def update_community(%Community{} = community, attrs) do
    community
    |> Community.changeset(attrs)
    |> Repo.update()
  end

  def delete_community(%Community{} = community), do: Repo.delete(community)

  # ── Collections ───────────────────────────────────────────────────────────

  def list_collections_for_community(community_id) do
    Repo.all(
      from c in Collection,
        where: c.community_id == ^community_id and c.is_active == true,
        order_by: c.position
    )
  end

  def get_collection!(id), do: Repo.get!(Collection, id)

  def get_collection_by_handle!(handle), do: Repo.get_by!(Collection, handle: handle)

  def create_collection(attrs) do
    %Collection{}
    |> Collection.changeset(attrs)
    |> Repo.insert()
  end

  def update_collection(%Collection{} = collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  # ── Items ─────────────────────────────────────────────────────────────────

  def get_item!(id), do: Repo.get!(Item, id)

  def get_item_by_handle!(handle), do: Repo.get_by!(Item, handle: handle)

  def get_item_by_handle(handle), do: Repo.get_by(Item, handle: handle)

  def get_item_with_preloads!(id) do
    Repo.get!(Item, id)
    |> Repo.preload([:collection, :submitter, :item_keywords, :item_authors,
                     :item_advisors, :item_examiners, :item_team_members,
                     :bitstreams, :metadata_extras])
  end

  def list_published_items(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    Repo.all(
      from i in Item,
        where: i.status == :published and i.discoverable == true,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset
    )
  end

  def list_items_for_collection(collection_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    Repo.all(
      from i in Item,
        where: i.collection_id == ^collection_id
          and i.status == :published
          and i.discoverable == true,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset
    )
  end

  def search_items(%{} = params) do
    term       = Map.get(params, :term)
    department = Map.get(params, :department)
    faculty    = Map.get(params, :faculty)
    year       = Map.get(params, :year)
    item_type  = Map.get(params, :item_type)
    page       = Map.get(params, :page, 1)
    per_page   = Map.get(params, :per_page, 20)
    offset     = (page - 1) * per_page

    from(i in Item,
      where: i.status == :published and i.discoverable == true
    )
    |> maybe_full_text_filter(term)
    |> maybe_filter(:department, department)
    |> maybe_filter(:faculty, faculty)
    |> maybe_filter(:publication_year, year)
    |> maybe_filter(:item_type, item_type)
    |> order_by([i], desc: i.published_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  defp maybe_full_text_filter(query, nil), do: query
  defp maybe_full_text_filter(query, term) do
    from i in query,
      where: fragment(
        "to_tsvector('indonesian', coalesce(?, '') || ' ' || coalesce(?, '')) @@ plainto_tsquery(?)",
        i.title, i.abstract, ^term
      )
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value) do
    from i in query, where: field(i, ^field) == ^value
  end

  def count_items_for_collection(collection_id) do
    Repo.one(
      from i in Item,
        where: i.collection_id == ^collection_id
          and i.status == :published,
        select: count(i.id)
    )
  end

  def list_items_by_submitter(user_id) do
    Repo.all(from i in Item, where: i.submitter_id == ^user_id, order_by: [desc: i.inserted_at])
  end

  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  def publish_item(%Item{} = item) do
    item
    |> Ecto.Changeset.change(
      status: :published,
      published_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
      discoverable: true
    )
    |> Repo.update()
  end

  def withdraw_item(%Item{} = item) do
    item
    |> Ecto.Changeset.change(status: :withdrawn, withdrawn: true, discoverable: false)
    |> Repo.update()
  end

  def lift_embargo(%Item{} = item) do
    item
    |> Ecto.Changeset.change(status: :published, embargo_open_date: nil)
    |> Repo.update()
  end

  def delete_item(%Item{} = item), do: Repo.delete(item)

  # ── Import (called from mix import_from_mssql only) ───────────────────────

  def import_item(attrs) do
    %Item{}
    |> Item.import_changeset(attrs)
    |> Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]},
                   conflict_target: :legacy_id)
  end
end
```

### 5.2 Accounts Context

```elixir
# lib/kiroku/accounts.ex
defmodule Kiroku.Accounts do
  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Accounts.{User, UserToken}

  # ── User registration ─────────────────────────────────────────────────────

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  # ── Session tokens ────────────────────────────────────────────────────────

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

  # ── Email confirmation ────────────────────────────────────────────────────

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      Kiroku.Accounts.UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token)
      )
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
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  # ── Password reset ────────────────────────────────────────────────────────

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    Kiroku.Accounts.UserNotifier.deliver_reset_password_instructions(
      user,
      reset_password_url_fun.(encoded_token)
    )
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
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
```

### 5.3 Content Context

```elixir
# lib/kiroku/content.ex
defmodule Kiroku.Content do
  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Content.Bitstream

  def list_bitstreams_for_item(item_id) do
    Repo.all(
      from b in Bitstream,
        where: b.item_id == ^item_id,
        order_by: [asc: b.bundle_name, asc: b.sequence]
    )
  end

  def get_bitstream!(id), do: Repo.get!(Bitstream, id)

  def get_bitstream(id), do: Repo.get(Bitstream, id)

  def create_bitstream(attrs) do
    %Bitstream{}
    |> Bitstream.changeset(attrs)
    |> Repo.insert()
  end

  def update_bitstream(%Bitstream{} = bitstream, attrs) do
    bitstream
    |> Bitstream.changeset(attrs)
    |> Repo.update()
  end

  def delete_bitstream(%Bitstream{} = bitstream), do: Repo.delete(bitstream)

  # Checks whether a specific bitstream is accessible given the item's embargo state.
  # The abstract (bundle: ORIGINAL, sequence: 1) is NEVER embargoed.
  def accessible?(%Bitstream{} = bitstream, current_user \\ nil, %{} = item) do
    cond do
      # THUMBNAIL is always accessible
      bitstream.bundle_name == :THUMBNAIL ->
        true

      # ADMINISTRATIVE and LICENSE are restricted to staff/admin only
      bitstream.bundle_name in [:ADMINISTRATIVE, :LICENSE] ->
        user_is_staff?(current_user)

      # Abstract PDF is never embargoed even if the item is
      bitstream.bundle_name == :ORIGINAL and bitstream.sequence == 1 ->
        access_level_allows?(bitstream.access_level, item.access_level, current_user)

      # Embargo check for everything else
      Kiroku.Repository.Item.files_embargoed?(item) ->
        user_is_staff?(current_user)

      true ->
        access_level_allows?(bitstream.access_level, item.access_level, current_user)
    end
  end

  defp access_level_allows?(:open, _item_level, _user), do: true
  defp access_level_allows?(:inherit, item_level, user), do: access_level_allows?(item_level, item_level, user)
  defp access_level_allows?(:restricted, _item_level, user), do: user_is_staff?(user)
  defp access_level_allows?(:closed, _item_level, _user), do: false

  defp user_is_staff?(nil), do: false
  defp user_is_staff?(%{user_type: type}), do: type in [:reviewer, :admin, :superadmin]
end
```

### 5.4 Authorization Helper

```elixir
# lib/kiroku/access/authorization.ex
defmodule Kiroku.Access.Authorization do
  alias Kiroku.Accounts.User
  alias Kiroku.Repository.{Community, Collection, Item}

  # ── Community ─────────────────────────────────────────────────────────────

  def can?(%User{user_type: type}, action, %Community{})
      when action in [:create, :update, :delete] and type in [:admin, :superadmin],
      do: true

  # ── Collection ────────────────────────────────────────────────────────────

  def can?(%User{user_type: type}, action, %Collection{})
      when action in [:create, :update, :delete] and type in [:admin, :superadmin],
      do: true

  # ── Item ──────────────────────────────────────────────────────────────────

  def can?(_user, :read, %Item{status: :published, access_level: :open}), do: true

  def can?(%User{user_type: type}, :read, %Item{})
      when type in [:reviewer, :admin, :superadmin],
      do: true

  def can?(%User{id: id}, :read, %Item{submitter_id: id}), do: true

  def can?(%User{user_type: type}, :create_item, _collection)
      when type in [:submitter, :admin, :superadmin],
      do: true

  def can?(%User{id: id}, :update_item, %Item{submitter_id: id, status: status})
      when status in [:draft, :submitted],
      do: true

  def can?(%User{user_type: type}, :update_item, %Item{})
      when type in [:admin, :superadmin],
      do: true

  def can?(%User{user_type: type}, action, _resource)
      when action in [:publish_item, :review_item, :withdraw_item, :lift_embargo]
       and type in [:reviewer, :admin, :superadmin],
      do: true

  def can?(%User{user_type: type}, action, _resource)
      when action in [:manage_users, :manage_communities, :manage_collections]
       and type in [:admin, :superadmin],
      do: true

  def can?(_user, _action, _resource), do: false
end
```

---

## 6. Router

```elixir
# lib/kiroku_web/router.ex
defmodule KirokuWeb.Router do
  use KirokuWeb, :router

  import KirokuWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KirokuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Static public pages ────────────────────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/handle/*path", HandleController, :show       # DSpace handle resolver
    get "/bitstream/:id/:filename", BitstreamController, :show
    get "/citation/:id.:format", CitationController, :show
  end

  # ── OAI-PMH ───────────────────────────────────────────────────────────────
  scope "/oai", KirokuWeb do
    pipe_through :api
    get "/", OaiPmhController, :index
  end

  # ── REST API v1 ──────────────────────────────────────────────────────────
  scope "/api/v1", KirokuWeb.Api.V1 do
    pipe_through :api
    resources "/communities", CommunityController, only: [:index, :show]
    resources "/collections", CollectionController, only: [:index, :show]
    resources "/items", ItemController, only: [:index, :show] do
      get "/bitstreams", ItemController, :bitstreams, as: :bitstream
    end
  end

  # ── Auth (unauthenticated only) ────────────────────────────────────────────
  scope "/auth", KirokuWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :unauthenticated,
      on_mount: [{KirokuWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/login",            UserLoginLive, :new
      live "/register",         UserRegistrationLive, :new
      live "/forgot-password",  UserForgotPasswordLive, :new
      live "/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/login", UserSessionController, :create
  end

  scope "/auth", KirokuWeb do
    pipe_through :browser
    delete "/logout", UserSessionController, :delete
    get "/confirm/:token", UserConfirmationController, :edit
    post "/confirm", UserConfirmationController, :create
  end

  # ── Public LiveView browsing (current_scope mounted but not required) ──────
  scope "/", KirokuWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{KirokuWeb.UserAuth, :mount_current_scope_for_user}] do
      live "/browse",                      BrowseLive, :index
      live "/search",                      SearchLive, :index
      live "/communities",                 CommunityLive.Index, :index
      live "/communities/:handle",         CommunityLive.Show, :show
      live "/collections/:handle",         CollectionLive.Show, :show
      live "/items/:handle",               ItemLive.Show, :show
    end
  end

  # ── Authenticated submitter routes ────────────────────────────────────────
  scope "/", KirokuWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{KirokuWeb.UserAuth, :ensure_authenticated}] do
      live "/my/submissions",  SubmissionLive.Index, :index
      live "/submit",          SubmissionLive.New, :new
      live "/submit/:id/edit", SubmissionLive.Edit, :edit
    end
  end

  # ── Admin routes ──────────────────────────────────────────────────────────
  scope "/admin", KirokuWeb.Admin do
    pipe_through [:browser, :require_admin_user]

    live_session :admin,
      on_mount: [{KirokuWeb.UserAuth, :ensure_admin}] do
      live "/",                       DashboardLive, :index
      live "/communities",            CommunityLive.Index, :index
      live "/communities/new",        CommunityLive.New, :new
      live "/communities/:id/edit",   CommunityLive.Edit, :edit
      live "/collections",            CollectionLive.Index, :index
      live "/collections/new",        CollectionLive.New, :new
      live "/collections/:id/edit",   CollectionLive.Edit, :edit
      live "/items",                  ItemLive.Index, :index
      live "/items/:id",              ItemLive.Show, :show
      live "/items/:id/review",       ItemLive.Review, :review
      live "/users",                  UserLive.Index, :index
      live "/users/:id",              UserLive.Show, :show
    end
  end

  # Phoenix Live Dashboard (dev / admin)
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router
    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: KirokuWeb.Telemetry
    end
  end
end
```

---

## 7. Controllers

### 7.1 Handle Controller (DSpace URL compatibility)

```elixir
# lib/kiroku_web/controllers/handle_controller.ex
defmodule KirokuWeb.HandleController do
  use KirokuWeb, :controller

  alias Kiroku.Repository

  # Resolves /handle/prefix/suffix → item, collection, or community
  def show(conn, %{"path" => path_parts}) do
    handle = Enum.join(path_parts, "/")

    cond do
      item = Repository.get_item_by_handle(handle) ->
        redirect(conn, to: ~p"/items/#{handle}")

      community = Kiroku.Repo.get_by(Kiroku.Repository.Community, handle: handle) ->
        redirect(conn, to: ~p"/communities/#{community.handle}")

      collection = Kiroku.Repo.get_by(Kiroku.Repository.Collection, handle: handle) ->
        redirect(conn, to: ~p"/collections/#{collection.handle}")

      true ->
        conn
        |> put_status(:not_found)
        |> put_view(KirokuWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
```

### 7.2 Bitstream Controller

```elixir
# lib/kiroku_web/controllers/bitstream_controller.ex
defmodule KirokuWeb.BitstreamController do
  use KirokuWeb, :controller

  alias Kiroku.{Content, Repository}

  def show(conn, %{"id" => id, "filename" => _filename}) do
    bitstream = Content.get_bitstream!(id)
    item = Repository.get_item!(bitstream.item_id)
    current_user = conn.assigns[:current_user]

    if Content.accessible?(bitstream, current_user, item) do
      serve_bitstream(conn, bitstream)
    else
      conn
      |> put_status(:forbidden)
      |> put_view(KirokuWeb.ErrorHTML)
      |> render(:"403")
    end
  end

  defp serve_bitstream(conn, %{storage_type: :url, storage_url: url}) do
    redirect(conn, external: url)
  end

  defp serve_bitstream(conn, %{storage_type: :s3} = bitstream) do
    # Generate a time-limited pre-signed S3 URL and redirect
    url = Kiroku.Storage.Uploader.presign_url(bitstream.storage_bucket, bitstream.storage_path)
    redirect(conn, external: url)
  end

  defp serve_bitstream(conn, %{storage_type: :local} = bitstream) do
    conn
    |> put_resp_content_type(bitstream.mime_type || "application/octet-stream")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{bitstream.filename}"))
    |> send_file(200, bitstream.storage_path)
  end
end
```

### 7.3 OAI-PMH Controller

```elixir
# lib/kiroku_web/controllers/oai_pmh_controller.ex
defmodule KirokuWeb.OaiPmhController do
  use KirokuWeb, :controller

  alias Kiroku.Oai.Builder

  def index(conn, params) do
    verb = Map.get(params, "verb")

    xml =
      case verb do
        "Identify"            -> Builder.identify()
        "ListMetadataFormats" -> Builder.list_metadata_formats()
        "ListSets"            -> Builder.list_sets()
        "GetRecord"           -> Builder.get_record(params)
        "ListRecords"         -> Builder.list_records(params)
        "ListIdentifiers"     -> Builder.list_identifiers(params)
        _                     -> Builder.error("badVerb", "Illegal OAI verb")
      end

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, xml)
  end
end
```

---

## 8. LiveViews

### 8.1 Public Item Show

```elixir
# lib/kiroku_web/live/item_live/show.ex
defmodule KirokuWeb.ItemLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content, Analytics}

  @impl true
  def mount(%{"handle" => handle}, _session, socket) do
    item = Repository.get_item_by_handle!(handle)
           |> Kiroku.Repo.preload([:collection, :item_keywords, :item_authors,
                                    :item_advisors, :item_examiners, :bitstreams])

    if item.status != :published or not item.discoverable do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      Analytics.record_view(item.id, socket.assigns[:current_user])
      {:ok, assign(socket, item: item, bitstreams: item.bitstreams, page_title: item.title)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Item detail page content --%>
    </Layouts.app>
    """
  end
end
```

### 8.2 Search LiveView

```elixir
# lib/kiroku_web/live/search_live.ex
defmodule KirokuWeb.SearchLive do
  use KirokuWeb, :live_view

  alias Kiroku.Repository

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, items: [], query: %{}, page_title: "Search")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = %{
      term:       Map.get(params, "q"),
      department: Map.get(params, "dept"),
      faculty:    Map.get(params, "faculty"),
      year:       params["year"] && String.to_integer(params["year"]),
      item_type:  params["type"] && String.to_existing_atom(params["type"]),
      page:       (params["page"] && String.to_integer(params["page"])) || 1
    }

    items = if query.term || query.department || query.faculty || query.year || query.item_type do
      Repository.search_items(query)
    else
      []
    end

    {:noreply, assign(socket, items: items, query: query)}
  end

  @impl true
  def handle_event("search", %{"q" => term} = params, socket) do
    {:noreply, push_patch(socket, to: ~p"/search?#{params}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Search form and results --%>
    </Layouts.app>
    """
  end
end
```

### 8.3 Submission Wizard (Multi-step)

```elixir
# lib/kiroku_web/live/submission_live/new.ex
defmodule KirokuWeb.SubmissionLive.New do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content, Accounts}
  alias Kiroku.Repository.Item
  alias Kiroku.Access.Authorization

  @steps ~w(type metadata files review submit)a

  @impl true
  def mount(_params, _session, socket) do
    collections = Repository.list_all_collections()

    {:ok, assign(socket,
      step: :type,
      steps: @steps,
      form: to_form(Item.changeset(%Item{}, %{}), as: "item"),
      collections: collections,
      uploaded_files: [],
      page_title: "Submit Work"
    )}
  end

  @impl true
  def handle_event("next_step", params, socket) do
    # Validate current step, advance if valid
    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    current_index = Enum.find_index(@steps, &(&1 == socket.assigns.step))
    prev = Enum.at(@steps, current_index - 1)
    {:noreply, assign(socket, step: prev)}
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset = Item.changeset(%Item{}, params)
    {:noreply, assign(socket, form: to_form(changeset, as: "item", action: :validate))}
  end

  @impl true
  def handle_event("submit", %{"item" => params}, socket) do
    user = socket.assigns.current_scope.user

    if Authorization.can?(user, :create_item, :any) do
      attrs = Map.put(params, "submitter_id", user.id)
      case Repository.create_item(attrs) do
        {:ok, item} -> {:noreply, push_navigate(socket, to: ~p"/my/submissions")}
        {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset, as: "item"))}
      end
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to submit.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Multi-step form --%>
    </Layouts.app>
    """
  end
end
```

---

## 9. Background Jobs

### 9.1 Embargo Lifter Worker

```elixir
# lib/kiroku/embargo/lifter_worker.ex
defmodule Kiroku.Embargo.LifterWorker do
  use Oban.Worker, queue: :embargo, max_attempts: 3

  import Ecto.Query
  alias Kiroku.{Repo, Repository}
  alias Kiroku.Repository.Item

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    # Items whose embargo_open_date has passed — lift them
    items_to_lift =
      Repo.all(
        from i in Item,
          where: not is_nil(i.embargo_open_date)
            and i.embargo_open_date <= ^today
            and i.status == :embargoed
      )

    Enum.each(items_to_lift, fn item ->
      case Repository.lift_embargo(item) do
        {:ok, _} -> :ok
        {:error, reason} ->
          # Log the error but continue — don't fail the entire job
          require Logger
          Logger.error("Failed to lift embargo on item #{item.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
```

Schedule it via `Oban.Plugins.Cron`. The cron expression is configurable
at runtime via a System Setting (DB) or the `EMBARGO_CRON` env var, defaulting
to daily at 02:00. Changes to the DB setting take effect on the next application
restart. Admins can also trigger an immediate run from the admin settings page.

```elixir
# config/config.exs
embargo_cron = System.get_env("EMBARGO_CRON", "0 2 * * *")

config :kiroku, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {embargo_cron, Kiroku.Embargo.LifterWorker},
     ]}
  ]
```

The `Kiroku.Settings` context exposes helpers for the admin UI:

```elixir
# lib/kiroku/settings.ex
Settings.embargo_cron_schedule()  # → "0 2 * * *" (DB value, env var, or default)
Settings.embargo_settings()       # → %{cron_schedule: "0 2 * * *"}
```

---

## 10. Legacy Import Task

```elixir
# lib/mix/tasks/import_from_mssql.ex
defmodule Mix.Tasks.ImportFromMssql do
  use Mix.Task

  @shortdoc "Import legacy theses from MSSQL database into Kiroku"

  alias Kiroku.{Repo, LegacyRepo, Repository, Content}
  alias Kiroku.LegacyThesis

  @impl Mix.Task
  def run(_args) do
    # Start repos manually — LegacyRepo is not in the supervision tree
    {:ok, _} = Application.ensure_all_started(:kiroku)
    {:ok, _} = LegacyRepo.start_link([])

    Mix.shell().info("Starting MSSQL import...")

    LegacyRepo.all(LegacyThesis)
    |> Enum.each(&import_thesis/1)

    Mix.shell().info("Import complete.")
  end

  defp import_thesis(%LegacyThesis{} = legacy) do
    attrs = %{
      legacy_id:        legacy.id,
      title:            legacy.judul,
      title_alt:        legacy.judul_inggris,
      abstract:         legacy.abstrak,
      student_id:       legacy.nim,
      student_name:     legacy.nama_mahasiswa,
      faculty:          legacy.fakultas,
      department:       legacy.jurusan,
      publication_year: legacy.tahun,
      status:           :published,
      access_level:     :open,
      discoverable:     true,
      item_type:        :skripsi,
      degree_level:     map_degree(legacy.jenjang),
      base_url:         legacy.url_file,
    }

    case Repository.import_item(attrs) do
      {:ok, item} ->
        if legacy.url_file do
          Content.create_bitstream(%{
            item_id:      item.id,
            filename:     "fulltext.pdf",
            bundle_name:  :ORIGINAL,
            sequence:     2,
            storage_type: :url,
            storage_url:  legacy.url_file,
            access_level: :inherit,
            description:  "Full Text (Legacy)"
          })
        end

      {:error, changeset} ->
        Mix.shell().error("Failed to import #{legacy.id}: #{inspect(changeset.errors)}")
    end
  end

  defp map_degree("S1"), do: :s1
  defp map_degree("S2"), do: :s2
  defp map_degree("S3"), do: :s3
  defp map_degree(_),    do: :s1
end
```

---

## 11. Migrations Reference

Run `mix ecto.gen.migration` to create migration files. Key tables to create in order (respect FK dependencies):

1. `communities` — self-referential `parent_community_id`
2. `collections` — FK → `communities`
3. `users` — standalone
4. `user_tokens` — FK → `users`
5. `items` — FK → `collections`, `users`
6. `item_keywords` — FK → `items`
7. `item_authors` — FK → `items`
8. `item_advisors` — FK → `items`
9. `item_examiners` — FK → `items`
10. `item_team_members` — FK → `items`
11. `item_metadata_extras` — FK → `items`
12. `bitstreams` — FK → `items`
13. `rbac_policies` — FK → `users` (nullable)
14. `view_events` — FK → `items`, `users` (nullable)
15. `oban_jobs` — generated by Oban migration helper

For `items`, add PostgreSQL indexes:

```elixir
# In the items migration:
create index(:items, [:student_id])
create index(:items, [:status])
create index(:items, [:publication_year])
create index(:items, [:discoverable])
create index(:items, [:department])
create index(:items, [:faculty])
create index(:items, [:handle], unique: true)
create index(:items, [:legacy_id])

# Full-text search index (Indonesian dictionary)
execute """
CREATE INDEX items_fulltext_idx ON items
USING GIN (to_tsvector('indonesian', coalesce(title, '') || ' ' || coalesce(abstract, '')));
"""
```

---
