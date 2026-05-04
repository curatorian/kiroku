defmodule Kiroku.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string
      add :legacy_id, :string
      add :idpustaka, :string

      # Bibliographic
      add :title, :string, null: false
      add :title_alt, :string
      add :abstract, :text
      add :abstract_alt, :text
      add :language, :string, default: "id"

      # Classification
      add :item_type, :string, default: "skripsi"
      add :degree_level, :string
      add :department, :string
      add :faculty, :string
      add :program_study, :string
      add :institution, :string

      # Student / contributor
      add :student_id, :string
      add :student_name, :string

      # Lifecycle
      add :status, :string, null: false, default: "draft"
      add :access_level, :string, null: false, default: "open"
      add :discoverable, :boolean, default: true, null: false
      add :withdrawn, :boolean, default: false, null: false

      # Dates
      add :date_submitted, :date
      add :date_issued, :date
      add :date_available, :date
      add :publication_year, :integer
      add :published_at, :naive_datetime

      # Embargo
      add :embargo_open_date, :date
      add :embargo_close_date, :date
      add :embargo_reason, :string

      # ── Legal / Hukum ────────────────────────────────────────────────────────
      add :legal_subject_matter, :string
      add :case_reference, :string
      add :court_level, :string
      add :legal_issue, :text
      add :jurisdiction, :string
      add :legal_analysis_method, :string

      # ── Studi Kasus ──────────────────────────────────────────────────────────
      add :case_study_type, :string
      add :case_subject, :string
      add :case_period, :string
      add :case_location, :string
      add :analysis_framework, :string
      add :subject_anonymized, :boolean, default: false
      add :informed_consent, :boolean, default: false
      add :ethics_approval_number, :string
      add :industry_partner, :string
      add :data_collection_method, :string

      # ── Laporan Proyek / Capstone ─────────────────────────────────────────────
      add :project_title, :string
      add :project_type, :string
      add :project_client, :string
      add :project_period, :string
      add :project_location, :string
      add :project_deliverable, :string
      add :project_budget, :string
      add :team_role, :string
      add :patent_pending, :boolean, default: false
      add :partner_institution, :string
      add :problem_statement, :text
      add :solution_description, :text
      add :capstone_theme, :string
      add :capstone_partner, :string
      add :mbkm_scheme, :string

      # ── Karya Kreatif ─────────────────────────────────────────────────────────
      add :creative_work_type, :string
      add :medium_material, :string
      add :dimensions_duration, :string
      add :creation_period, :string
      add :artistic_statement, :text
      add :exhibition_performance, :string
      add :exhibition_date, :date
      add :exhibition_venue, :string
      add :copyright_type, :string
      add :collection_owner, :string

      # ── Karya Teknologi ───────────────────────────────────────────────────────
      add :technology_type, :string
      add :problem_solved, :text
      add :target_user, :string
      add :implementation_status, :string
      add :testing_method, :string
      add :license_type, :string
      add :patent_status, :string
      add :hki_number, :string
      add :industry_tested_at, :string

      # ── Journal ───────────────────────────────────────────────────────────────
      add :journal_name, :string
      add :issn, :string
      add :eissn, :string
      add :doi, :string
      add :volume, :string
      add :issue, :string
      add :page_start, :integer
      add :page_end, :integer
      add :publisher, :string
      add :place_of_publication, :string
      add :isbn, :string
      add :sinta_accreditation, :string
      add :scopus_indexed, :boolean, default: false
      add :wos_indexed, :boolean, default: false
      add :quartile, :string
      add :peer_review_type, :string
      add :article_type, :string

      # ── Prosiding ─────────────────────────────────────────────────────────────
      add :conference_name, :string
      add :conference_location, :string
      add :conference_date, :string
      add :best_paper_award, :string

      # ── Shared across thesis types ────────────────────────────────────────────
      add :research_location, :string
      add :research_period, :string
      add :funding_source, :string
      add :subject_classification, :string
      add :originality_statement, :boolean, default: false
      add :thesis_type_detail, :string

      # Legacy
      add :base_url, :string

      # Associations
      add :collection_id,
          references(:collections, type: :binary_id, on_delete: :restrict)

      add :submitter_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:items, [:handle])
    create unique_index(:items, [:legacy_id])
    create index(:items, [:collection_id])
    create index(:items, [:submitter_id])
    create index(:items, [:status])
    create index(:items, [:item_type])
    create index(:items, [:faculty])
    create index(:items, [:department])
    create index(:items, [:publication_year])
    create index(:items, [:published_at])
  end
end
