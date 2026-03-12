defmodule Kiroku.Repository.Item do
  use Ash.Resource,
    otp_app: :kiroku,
    domain: Kiroku.Repository,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table "items"
    repo Kiroku.Repo

    custom_indexes do
      index [:student_id]
      index [:status]
      index [:publication_year]
      index [:discoverable]
      index [:department]
      index [:faculty]
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      prepare build(filter: expr(discoverable == true and withdrawn == false))
    end

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
      argument :term, :string
      argument :department, :string
      argument :faculty, :string
      argument :year, :integer
      argument :item_type, :atom
      argument :access_level, :atom
      argument :page, :integer, default: 1
      argument :per_page, :integer, default: 20

      prepare Kiroku.Repository.Item.Preparations.Search

      pagination keyset?: true, offset?: true, default_limit: 20, max_page_size: 100
    end

    read :browse_by_date do
      argument :year, :integer
      filter expr(publication_year == ^arg(:year) and status == :published)
      pagination offset?: true, default_limit: 20
    end

    create :create do
      accept [
        :collection_id,
        :submitter_id,
        :handle,
        :legacy_id,
        :idpustaka,
        :title,
        :title_raw,
        :title_alt,
        :abstract,
        :abstract_raw,
        :abstract_alt,
        :language,
        :item_type,
        :degree_level,
        :department,
        :faculty,
        :program_study,
        :institution,
        :student_id,
        :student_name,
        :status,
        :access_level,
        :discoverable,
        :withdrawn,
        :date_submitted,
        :date_issued,
        :date_available,
        :publication_year,
        :published_at,
        :embargo_open_date,
        :embargo_close_date,
        :embargo_reason,
        :base_url
      ]

      validate present(:title)
      validate present(:collection_id)
    end

    create :import do
      accept [
        :collection_id,
        :submitter_id,
        :handle,
        :legacy_id,
        :idpustaka,
        :title,
        :title_raw,
        :title_alt,
        :abstract,
        :abstract_raw,
        :abstract_alt,
        :language,
        :item_type,
        :degree_level,
        :department,
        :faculty,
        :program_study,
        :institution,
        :student_id,
        :student_name,
        :status,
        :access_level,
        :discoverable,
        :withdrawn,
        :date_submitted,
        :date_issued,
        :date_available,
        :publication_year,
        :published_at,
        :embargo_open_date,
        :embargo_close_date,
        :embargo_reason,
        :base_url
      ]

      skip_unknown_inputs [:*]
    end

    update :update do
      accept [
        :title,
        :title_raw,
        :title_alt,
        :abstract,
        :abstract_raw,
        :abstract_alt,
        :language,
        :item_type,
        :degree_level,
        :department,
        :faculty,
        :program_study,
        :status,
        :access_level,
        :discoverable,
        :withdrawn,
        :date_submitted,
        :date_issued,
        :date_available,
        :publication_year,
        :embargo_open_date,
        :embargo_close_date,
        :embargo_reason
      ]
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

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
      authorize_if actor_attribute_equals(:user_type, :submitter)
    end

    policy action(:update) do
      authorize_if relates_to_actor_via(:submitter)
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
    end

    policy action(:import) do
      authorize_if always()
    end

    policy action([:publish, :withdraw, :lift_embargo]) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
      authorize_if actor_attribute_equals(:user_type, :reviewer)
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:user_type, :admin)
      authorize_if actor_attribute_equals(:user_type, :superadmin)
    end
  end

  attributes do
    uuid_primary_key :id

    # ── Identity ──────────────────────────────────────────────────────────────
    attribute :handle, :string, public?: true
    attribute :legacy_id, :string, public?: true
    attribute :idpustaka, :string, public?: true

    # ── Bibliographic ─────────────────────────────────────────────────────────
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :title_raw, :string, public?: true
    attribute :title_alt, :string, public?: true
    attribute :abstract, :string, public?: true
    attribute :abstract_raw, :string, public?: true
    attribute :abstract_alt, :string, public?: true
    attribute :language, :atom, constraints: [one_of: [:id, :en]], default: :id, public?: true

    # ── Classification ────────────────────────────────────────────────────────
    attribute :item_type, :atom,
      constraints: [
        one_of: [
          :skripsi,
          :memorandum_hukum,
          :studi_kasus,
          :laporan_proyek,
          :karya_kreatif,
          :karya_teknologi,
          :jurnal_nasional,
          :jurnal_internasional,
          :prosiding,
          :capstone
        ]
      ],
      default: :skripsi,
      public?: true

    attribute :degree_level, :atom,
      constraints: [one_of: [:d3, :d4, :s1, :s1_terapan, :s2, :s3]],
      public?: true

    attribute :department, :string, public?: true
    attribute :faculty, :string, public?: true
    attribute :program_study, :string, public?: true
    attribute :institution, :string, public?: true

    # ── Student ───────────────────────────────────────────────────────────────
    attribute :student_id, :string, public?: true
    attribute :student_name, :string, public?: true

    # ── Lifecycle ─────────────────────────────────────────────────────────────
    attribute :status, :atom,
      constraints: [
        one_of: [:draft, :submitted, :under_review, :published, :embargoed, :withdrawn]
      ],
      default: :draft,
      public?: true

    attribute :access_level, :atom,
      constraints: [one_of: [:open, :restricted, :closed]],
      default: :open,
      public?: true

    attribute :discoverable, :boolean, default: true, public?: true
    attribute :withdrawn, :boolean, default: false, public?: true

    # ── Dates ─────────────────────────────────────────────────────────────────
    attribute :date_submitted, :date, public?: true
    attribute :date_issued, :date, public?: true
    attribute :date_available, :date, public?: true
    attribute :publication_year, :integer, public?: true
    attribute :published_at, :naive_datetime, public?: true

    # ── Embargo ───────────────────────────────────────────────────────────────
    attribute :embargo_open_date, :date, public?: true
    attribute :embargo_close_date, :date, public?: true
    attribute :embargo_reason, :string, public?: true

    # ── Source ────────────────────────────────────────────────────────────────
    attribute :base_url, :string, public?: true

    # ── Type-Specific: Shared ─────────────────────────────────────────────────
    attribute :approval_date, :date, public?: true
    attribute :research_location, :string, public?: true
    attribute :research_period, :string, public?: true

    attribute :funding_source, :atom,
      constraints: [one_of: [:mandiri, :hibah, :sponsor, :mitra, :other]],
      public?: true

    attribute :thesis_type_detail, :atom,
      constraints: [one_of: [:kuantitatif, :kualitatif, :mixed_methods, :rnd, :ptk]],
      public?: true

    attribute :subject_classification, :string, public?: true
    attribute :originality_statement, :boolean, default: false, public?: true

    # ── Type-Specific: Legal (memorandum_hukum) ───────────────────────────────
    attribute :legal_subject_matter, :atom,
      constraints: [
        one_of: [
          :pidana,
          :perdata,
          :tata_negara,
          :internasional,
          :bisnis,
          :adat,
          :agraria,
          :lingkungan
        ]
      ],
      public?: true

    attribute :case_reference, :string, public?: true

    attribute :court_level, :atom,
      constraints: [one_of: [:pn, :pt, :ma, :mk, :ptun, :arbitrase, :bani, :icc]],
      public?: true

    attribute :legal_issue, :string, public?: true

    attribute :jurisdiction, :atom,
      constraints: [one_of: [:indonesia, :internasional, :komparatif]],
      public?: true

    attribute :legal_analysis_method, :atom,
      constraints: [one_of: [:normatif, :empiris, :komparatif, :socio_legal]],
      public?: true

    # ── Type-Specific: Case Study (studi_kasus) ──────────────────────────────
    attribute :case_study_type, :atom,
      constraints: [one_of: [:bisnis, :klinis, :hukum, :psikologi, :pendidikan, :teknik]],
      public?: true

    attribute :case_subject, :string, public?: true
    attribute :case_period, :string, public?: true
    attribute :case_location, :string, public?: true
    attribute :analysis_framework, :string, public?: true
    attribute :subject_anonymized, :boolean, default: false, public?: true
    attribute :informed_consent, :boolean, default: false, public?: true
    attribute :ethics_approval_number, :string, public?: true
    attribute :industry_partner, :string, public?: true

    attribute :data_collection_method, :atom,
      constraints: [one_of: [:wawancara, :observasi, :dokumen_sekunder, :mix]],
      public?: true

    # ── Type-Specific: Project Report (laporan_proyek) ────────────────────────
    attribute :project_title, :string, public?: true

    attribute :project_type, :atom,
      constraints: [
        one_of: [
          :desain,
          :konstruksi,
          :implementasi_software,
          :manufaktur,
          :sistem,
          :perencanaan_wilayah,
          :product,
          :service,
          :policy,
          :research,
          :community
        ]
      ],
      public?: true

    attribute :project_client, :string, public?: true
    attribute :project_period, :string, public?: true
    attribute :project_location, :string, public?: true
    attribute :project_deliverable, :string, public?: true

    attribute :team_role, :atom,
      constraints: [one_of: [:ketua, :anggota, :pic_teknis]],
      public?: true

    attribute :project_budget, :string, public?: true
    attribute :patent_pending, :boolean, default: false, public?: true

    # ── Type-Specific: Creative Work (karya_kreatif) ──────────────────────────
    attribute :creative_work_type, :atom,
      constraints: [
        one_of: [
          :novel,
          :antologi_puisi,
          :film_pendek,
          :komposisi_musik,
          :lukisan,
          :desain_produk,
          :animasi,
          :game,
          :arsitektur,
          :kriya
        ]
      ],
      public?: true

    attribute :medium_material, :string, public?: true
    attribute :dimensions_duration, :string, public?: true
    attribute :creation_period, :string, public?: true
    attribute :artistic_statement, :string, public?: true
    attribute :exhibition_performance, :string, public?: true
    attribute :exhibition_date, :date, public?: true
    attribute :exhibition_venue, :string, public?: true

    attribute :copyright_type, :atom,
      constraints: [one_of: [:all_rights_reserved, :cc_by, :cc_by_sa, :cc_by_nc, :cc_by_nc_sa]],
      public?: true

    attribute :collection_owner, :string, public?: true

    # ── Type-Specific: Technology Work (karya_teknologi) ──────────────────────
    attribute :technology_type, :atom,
      constraints: [
        one_of: [
          :aplikasi_mobile,
          :web_app,
          :embedded_system,
          :perangkat_keras,
          :dataset,
          :model_ai_ml,
          :algoritma,
          :inovasi_proses
        ]
      ],
      public?: true

    attribute :problem_solved, :string, public?: true
    attribute :target_user, :string, public?: true

    attribute :implementation_status, :atom,
      constraints: [one_of: [:prototipe, :mvp, :deployed, :published]],
      public?: true

    attribute :testing_method, :atom,
      constraints: [one_of: [:black_box, :white_box, :user_testing, :benchmark, :usability]],
      public?: true

    attribute :license_type, :atom,
      constraints: [one_of: [:mit, :apache_2, :gpl, :bsd, :proprietary]],
      public?: true

    attribute :patent_status, :atom,
      constraints: [one_of: [:tidak_ada, :dalam_proses, :granted]],
      public?: true

    attribute :hki_number, :string, public?: true
    attribute :industry_tested_at, :string, public?: true

    # ── Type-Specific: National Journal (jurnal_nasional) ─────────────────────
    attribute :journal_name, :string, public?: true
    attribute :sinta_id, :string, public?: true

    attribute :sinta_accreditation, :atom,
      constraints: [one_of: [:s1, :s2, :s3, :s4, :s5, :s6]],
      public?: true

    attribute :issn_print, :string, public?: true
    attribute :issn_online, :string, public?: true
    attribute :volume, :string, public?: true
    attribute :issue, :string, public?: true
    attribute :page_start, :integer, public?: true
    attribute :page_end, :integer, public?: true
    attribute :doi, :string, public?: true
    attribute :publisher, :string, public?: true
    attribute :corresponding_author, :string, public?: true
    attribute :garuda_id, :string, public?: true
    attribute :crossref_registered, :boolean, default: false, public?: true

    attribute :peer_review_type, :atom,
      constraints: [one_of: [:single_blind, :double_blind, :open_review]],
      public?: true

    attribute :submission_date, :date, public?: true
    attribute :acceptance_date, :date, public?: true

    attribute :article_type, :atom,
      constraints: [one_of: [:research_article, :review, :short_communication, :letter]],
      public?: true

    # ── Type-Specific: International Journal (jurnal_internasional) ───────────
    attribute :scopus_id, :string, public?: true
    attribute :wos_id, :string, public?: true
    attribute :sjr_score, :decimal, public?: true
    attribute :impact_factor, :decimal, public?: true

    attribute :quartile, :atom,
      constraints: [one_of: [:q1, :q2, :q3, :q4]],
      public?: true

    attribute :subject_area, :string, public?: true

    attribute :indexed_in, :atom,
      constraints: [one_of: [:scopus, :wos, :both]],
      public?: true

    attribute :altmetric_score, :integer, public?: true
    attribute :special_issue, :string, public?: true
    attribute :conference_origin, :string, public?: true
    attribute :open_access_apc, :string, public?: true

    # ── Type-Specific: Conference Proceedings (prosiding) ─────────────────────
    attribute :conference_name, :string, public?: true
    attribute :conference_acronym, :string, public?: true
    attribute :conference_date, :date, public?: true
    attribute :conference_location, :string, public?: true

    attribute :conference_type, :atom,
      constraints: [one_of: [:onsite, :online, :hybrid]],
      public?: true

    attribute :proceeding_publisher, :string, public?: true
    attribute :proceeding_series, :string, public?: true
    attribute :isbn_proceeding, :string, public?: true
    attribute :issn_proceeding, :string, public?: true

    attribute :presentation_type, :atom,
      constraints: [one_of: [:oral, :poster, :keynote, :workshop_paper]],
      public?: true

    attribute :acceptance_rate, :string, public?: true
    attribute :presentation_date, :date, public?: true
    attribute :session_name, :string, public?: true
    attribute :best_paper_award, :string, public?: true

    # ── Type-Specific: Capstone ───────────────────────────────────────────────
    attribute :capstone_theme, :string, public?: true
    attribute :team_lead, :string, public?: true
    attribute :partner_institution, :string, public?: true
    attribute :problem_statement, :string, public?: true
    attribute :solution_description, :string, public?: true
    attribute :impact_target, :string, public?: true
    attribute :duration_semester, :string, public?: true

    attribute :mbkm_scheme, :atom,
      constraints: [
        one_of: [
          :magang_industri,
          :kkn_tematik,
          :proyek_kemanusiaan,
          :wirausaha,
          :penelitian,
          :asistensi_mengajar,
          :pertukaran
        ]
      ],
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :collection, Kiroku.Repository.Collection, allow_nil?: false, public?: true
    belongs_to :submitter, Kiroku.Accounts.User, allow_nil?: true, public?: true

    has_many :item_keywords, Kiroku.Repository.ItemKeyword, public?: true
    has_many :item_authors, Kiroku.Repository.ItemAuthor, public?: true
    has_many :item_advisors, Kiroku.Repository.ItemAdvisor, public?: true
    has_many :item_examiners, Kiroku.Repository.ItemExaminer, public?: true
    has_many :item_team_members, Kiroku.Repository.ItemTeamMember, public?: true
    has_many :bitstreams, Kiroku.Content.Bitstream, public?: true
    has_many :metadata_extras, Kiroku.Repository.ItemMetadata, public?: true

    has_many :rbac_policies, Kiroku.Access.RbacPolicy,
      destination_attribute: :resource_id,
      public?: true
  end

  identities do
    identity :unique_handle, [:handle]
  end
end
