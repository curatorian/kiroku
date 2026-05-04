defmodule Kiroku.Repository.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @item_types ~w(
    skripsi memorandum_hukum studi_kasus laporan_proyek karya_kreatif
    karya_teknologi jurnal_nasional jurnal_internasional prosiding capstone
  )a

  @status_values ~w(draft submitted under_review published embargoed withdrawn)a
  @access_values ~w(open restricted closed)a
  @degree_values ~w(d3 d4 s1 s1_terapan s2 s3)a
  @language_values ~w(id en)a

  schema "items" do
    field :handle, :string
    field :legacy_id, :string
    field :idpustaka, :string

    # Bibliographic
    field :title, :string
    field :title_alt, :string
    field :abstract, :string
    field :abstract_alt, :string
    field :language, Ecto.Enum, values: @language_values, default: :id

    # Classification
    field :item_type, Ecto.Enum, values: @item_types, default: :skripsi
    field :degree_level, Ecto.Enum, values: @degree_values
    field :department, :string
    field :faculty, :string
    field :program_study, :string
    field :institution, :string

    # Student / contributor
    field :student_id, :string
    field :student_name, :string

    # Lifecycle
    field :status, Ecto.Enum, values: @status_values, default: :draft
    field :access_level, Ecto.Enum, values: @access_values, default: :open
    field :discoverable, :boolean, default: true
    field :withdrawn, :boolean, default: false

    # Dates
    field :date_submitted, :date
    field :date_issued, :date
    field :date_available, :date
    field :publication_year, :integer
    field :published_at, :naive_datetime

    # Embargo
    field :embargo_open_date, :date
    field :embargo_close_date, :date
    field :embargo_reason, :string

    # ── Type-specific scalars (NULL for non-applicable types) ────────────────

    # Legal / Hukum
    field :legal_subject_matter, Ecto.Enum,
      values: ~w(pidana perdata tata_negara internasional bisnis adat agraria lingkungan)a

    field :case_reference, :string
    field :court_level, Ecto.Enum, values: ~w(pn pt ma mk ptun arbitrase bani icc)a
    field :legal_issue, :string
    field :jurisdiction, Ecto.Enum, values: ~w(indonesia internasional komparatif)a
    field :legal_analysis_method, Ecto.Enum, values: ~w(normatif empiris komparatif socio_legal)a

    # Studi Kasus
    field :case_study_type, Ecto.Enum,
      values: ~w(bisnis klinis hukum psikologi pendidikan teknik)a

    field :case_subject, :string
    field :case_period, :string
    field :case_location, :string
    field :analysis_framework, :string
    field :subject_anonymized, :boolean, default: false
    field :informed_consent, :boolean, default: false
    field :ethics_approval_number, :string
    field :industry_partner, :string

    field :data_collection_method, Ecto.Enum,
      values: ~w(wawancara observasi dokumen_sekunder mix)a

    # Laporan Proyek / Capstone
    field :project_title, :string

    field :project_type, Ecto.Enum,
      values: ~w(desain konstruksi implementasi_software manufaktur sistem
                 perencanaan_wilayah product service policy research community)a

    field :project_client, :string
    field :project_period, :string
    field :project_location, :string
    field :project_deliverable, :string
    field :project_budget, :string
    field :team_role, Ecto.Enum, values: ~w(ketua anggota pic_teknis)a
    field :patent_pending, :boolean, default: false
    field :partner_institution, :string
    field :problem_statement, :string
    field :solution_description, :string
    field :capstone_theme, :string
    field :capstone_partner, :string

    field :mbkm_scheme, Ecto.Enum,
      values: ~w(magang kkn_t penelitian proyek_independen pertukaran_mahasiswa wirausaha)a

    # Karya Kreatif
    field :creative_work_type, Ecto.Enum,
      values: ~w(novel antologi_puisi film_pendek komposisi_musik lukisan
                 desain_produk animasi game arsitektur kriya)a

    field :medium_material, :string
    field :dimensions_duration, :string
    field :creation_period, :string
    field :artistic_statement, :string
    field :exhibition_performance, :string
    field :exhibition_date, :date
    field :exhibition_venue, :string

    field :copyright_type, Ecto.Enum,
      values: ~w(all_rights_reserved cc_by cc_by_sa cc_by_nc cc_by_nc_sa)a

    field :collection_owner, :string

    # Karya Teknologi
    field :technology_type, Ecto.Enum,
      values: ~w(aplikasi_mobile web_app embedded_system perangkat_keras
                 dataset model_ai_ml algoritma inovasi_proses)a

    field :problem_solved, :string
    field :target_user, :string
    field :implementation_status, Ecto.Enum, values: ~w(prototipe mvp deployed published)a

    field :testing_method, Ecto.Enum,
      values: ~w(black_box white_box user_testing benchmark usability)a

    field :license_type, Ecto.Enum, values: ~w(mit apache_2 gpl bsd proprietary)a
    field :patent_status, Ecto.Enum, values: ~w(tidak_ada dalam_proses granted)a
    field :hki_number, :string
    field :industry_tested_at, :string

    # Journal (Nasional + Internasional)
    field :journal_name, :string
    field :issn, :string
    field :eissn, :string
    field :doi, :string
    field :volume, :string
    field :issue, :string
    field :page_start, :integer
    field :page_end, :integer
    field :publisher, :string
    field :place_of_publication, :string
    field :isbn, :string
    field :sinta_accreditation, Ecto.Enum, values: ~w(s1 s2 s3 s4 s5 s6)a
    field :scopus_indexed, :boolean, default: false
    field :wos_indexed, :boolean, default: false
    field :quartile, Ecto.Enum, values: ~w(q1 q2 q3 q4)a
    field :peer_review_type, Ecto.Enum, values: ~w(single_blind double_blind open_review)a

    field :article_type, Ecto.Enum,
      values: ~w(research_article review short_communication letter)a

    # Prosiding
    field :conference_name, :string
    field :conference_location, :string
    field :conference_date, :string
    field :best_paper_award, :string

    # Shared across thesis types
    field :research_location, :string
    field :research_period, :string
    field :funding_source, :string
    field :subject_classification, :string
    field :originality_statement, :boolean, default: false

    field :thesis_type_detail, Ecto.Enum,
      values: ~w(kuantitatif kualitatif mixed_methods rnd ptk)a

    # Legacy import source
    field :base_url, :string

    # Review workflow
    field :review_note, :string
    field :reviewed_at, :utc_datetime_usec
    field :submitted_at, :utc_datetime_usec
    belongs_to :reviewed_by, Kiroku.Accounts.User, foreign_key: :reviewed_by_id

    belongs_to :collection, Kiroku.Repository.Collection
    belongs_to :submitter, Kiroku.Accounts.User

    has_many :item_keywords, Kiroku.Repository.ItemKeyword
    has_many :item_authors, Kiroku.Repository.ItemAuthor
    has_many :item_advisors, Kiroku.Repository.ItemAdvisor
    has_many :item_examiners, Kiroku.Repository.ItemExaminer
    has_many :item_team_members, Kiroku.Repository.ItemTeamMember
    has_many :bitstreams, Kiroku.Content.Bitstream
    has_many :metadata_extras, Kiroku.Repository.ItemMetadata

    timestamps()
  end

  @required_fields ~w(title collection_id)a
  @optional_fields ~w(
    handle legacy_id idpustaka title_alt abstract abstract_alt language
    item_type degree_level department faculty program_study institution
    student_id student_name
    legal_subject_matter case_reference court_level legal_issue
    jurisdiction legal_analysis_method
    case_study_type case_subject case_period case_location analysis_framework
    subject_anonymized informed_consent ethics_approval_number
    industry_partner data_collection_method
    project_title project_type project_client project_period project_location
    project_deliverable project_budget team_role patent_pending
    partner_institution problem_statement solution_description
    capstone_theme capstone_partner mbkm_scheme
    creative_work_type medium_material dimensions_duration creation_period
    artistic_statement exhibition_performance exhibition_date exhibition_venue
    copyright_type collection_owner
    technology_type problem_solved target_user implementation_status
    testing_method license_type patent_status hki_number industry_tested_at
    journal_name issn eissn doi volume issue page_start page_end
    publisher place_of_publication isbn sinta_accreditation
    scopus_indexed wos_indexed quartile peer_review_type article_type
    conference_name conference_location conference_date best_paper_award
    research_location research_period funding_source subject_classification
    originality_statement thesis_type_detail
    status access_level discoverable withdrawn
    date_submitted date_issued date_available publication_year published_at
    embargo_open_date embargo_close_date embargo_reason
    base_url submitter_id
    review_note reviewed_at submitted_at reviewed_by_id
  )a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 500)
    |> unique_constraint(:handle)
    |> foreign_key_constraint(:collection_id)
    |> foreign_key_constraint(:submitter_id)
  end

  def status_changeset(item, attrs) do
    item
    |> cast(attrs, [:status, :discoverable, :submitted_at])
    |> validate_required([:status])
  end

  def review_changeset(item, attrs) do
    item
    |> cast(attrs, [:status, :discoverable, :review_note, :reviewed_by_id, :reviewed_at])
    |> validate_required([:status])
    |> foreign_key_constraint(:reviewed_by_id)
  end

  # Looser changeset for the MSSQL import task — collection is looked up separately
  def import_changeset(item, attrs) do
    item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
    |> unique_constraint(:handle)
    |> unique_constraint(:legacy_id)
  end

  @doc """
  Returns true if the item's files should currently be under embargo.
  The abstract bitstream (ORIGINAL bundle, sequence 1) is NEVER embargoed
  regardless of this function's return value — that check is in Content.accessible?/3.
  """
  def files_embargoed?(%__MODULE__{} = item) do
    today = Date.utc_today()

    open_blocked =
      not is_nil(item.embargo_open_date) and
        Date.compare(today, item.embargo_open_date) == :lt

    close_blocked =
      not is_nil(item.embargo_close_date) and
        Date.compare(today, item.embargo_close_date) != :lt

    open_blocked or close_blocked
  end
end
