defmodule KirokuWeb.Live.Helpers.FieldVisibility do
  @moduledoc """
  Centralized field visibility rules for item submission and editing forms.

  Drives which `Item` fields are shown, hidden, or required based on the
  selected `item_type`. Used by the submission wizard (`SubmissionLive.New`,
  `SubmissionLive.Edit`) and the admin item editor (`Admin.ItemLive.Index`).

  All functions accept the `item_type` as an atom (matching the `Item` schema's
  `Ecto.Enum`) and return booleans or lists.
  """

  @thesis_types ~w(skripsi tesis disertasi tugas_akhir
                   memorandum_hukum studi_kasus laporan_proyek
                   karya_kreatif karya_teknologi capstone)a

  @journal_types ~w(jurnal_nasional jurnal_internasional)a

  @academic_contributor_types ~w(skripsi tesis disertasi tugas_akhir
                                 memorandum_hukum studi_kasus laporan_proyek capstone)a

  @journal_like_types ~w(jurnal_nasional jurnal_internasional prosiding)a

  # ── Section visibility ─────────────────────────────────────────────────────

  @doc """
  Returns true if the academic contributor section (student name, NIM,
  faculty, department, degree) should be shown for the given type.
  """
  def academic_contributor?(type), do: type in @academic_contributor_types

  # ── Field visibility ───────────────────────────────────────────────────────

  def show_field?(:degree_level, type), do: type in @thesis_types
  def show_field?(:student_id, type), do: type in @thesis_types
  def show_field?(:student_name, type), do: type in @thesis_types

  # Journal fields
  def show_field?(:journal_name, type), do: type in @journal_types
  def show_field?(:issn, type), do: type in @journal_types
  def show_field?(:eissn, type), do: type in @journal_types
  def show_field?(:doi, type), do: type in @journal_like_types
  def show_field?(:volume, type), do: type in @journal_types
  def show_field?(:issue, type), do: type in @journal_types
  def show_field?(:page_start, type), do: type in @journal_types
  def show_field?(:page_end, type), do: type in @journal_types
  def show_field?(:publisher, type), do: type in @journal_like_types
  def show_field?(:article_type, type), do: type in @journal_types
  def show_field?(:peer_review_type, type), do: type in @journal_types
  def show_field?(:sinta_accreditation, type), do: type == :jurnal_nasional
  def show_field?(:scopus_indexed, type), do: type == :jurnal_internasional
  def show_field?(:wos_indexed, type), do: type == :jurnal_internasional
  def show_field?(:quartile, type), do: type == :jurnal_internasional

  # Prosiding fields
  def show_field?(:conference_name, type), do: type == :prosiding
  def show_field?(:conference_location, type), do: type == :prosiding
  def show_field?(:conference_date, type), do: type == :prosiding
  def show_field?(:isbn, type), do: type == :prosiding
  def show_field?(:best_paper_award, type), do: type == :prosiding

  # Hukum / Legal
  def show_field?(:legal_subject_matter, type), do: type == :memorandum_hukum
  def show_field?(:case_reference, type), do: type == :memorandum_hukum
  def show_field?(:court_level, type), do: type == :memorandum_hukum
  def show_field?(:legal_issue, type), do: type == :memorandum_hukum
  def show_field?(:jurisdiction, type), do: type == :memorandum_hukum
  def show_field?(:legal_analysis_method, type), do: type == :memorandum_hukum

  # Studi Kasus
  def show_field?(:case_study_type, type), do: type == :studi_kasus
  def show_field?(:case_subject, type), do: type == :studi_kasus
  def show_field?(:case_period, type), do: type == :studi_kasus
  def show_field?(:case_location, type), do: type == :studi_kasus
  def show_field?(:analysis_framework, type), do: type == :studi_kasus
  def show_field?(:subject_anonymized, type), do: type == :studi_kasus
  def show_field?(:informed_consent, type), do: type == :studi_kasus
  def show_field?(:ethics_approval_number, type), do: type == :studi_kasus
  def show_field?(:industry_partner, type), do: type == :studi_kasus
  def show_field?(:data_collection_method, type), do: type == :studi_kasus

  # Laporan Proyek
  def show_field?(:project_title, type), do: type == :laporan_proyek
  def show_field?(:project_type, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:project_client, type), do: type == :laporan_proyek
  def show_field?(:project_period, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:project_location, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:project_deliverable, type), do: type == :laporan_proyek
  def show_field?(:project_budget, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:team_role, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:patent_pending, type), do: type == :laporan_proyek
  def show_field?(:problem_statement, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:solution_description, type), do: type in [:laporan_proyek, :capstone]

  # Capstone / MBKM
  def show_field?(:partner_institution, type), do: type == :capstone
  def show_field?(:capstone_theme, type), do: type == :capstone
  def show_field?(:capstone_partner, type), do: type == :capstone
  def show_field?(:mbkm_scheme, type), do: type == :capstone

  # Karya Kreatif
  def show_field?(:creative_work_type, type), do: type == :karya_kreatif
  def show_field?(:medium_material, type), do: type == :karya_kreatif
  def show_field?(:dimensions_duration, type), do: type == :karya_kreatif
  def show_field?(:creation_period, type), do: type == :karya_kreatif
  def show_field?(:artistic_statement, type), do: type == :karya_kreatif
  def show_field?(:exhibition_performance, type), do: type == :karya_kreatif
  def show_field?(:exhibition_date, type), do: type == :karya_kreatif
  def show_field?(:exhibition_venue, type), do: type == :karya_kreatif
  def show_field?(:copyright_type, type), do: type == :karya_kreatif
  def show_field?(:collection_owner, type), do: type == :karya_kreatif

  # Karya Teknologi
  def show_field?(:technology_type, type), do: type == :karya_teknologi
  def show_field?(:problem_solved, type), do: type == :karya_teknologi
  def show_field?(:target_user, type), do: type == :karya_teknologi
  def show_field?(:implementation_status, type), do: type == :karya_teknologi
  def show_field?(:testing_method, type), do: type == :karya_teknologi
  def show_field?(:license_type, type), do: type == :karya_teknologi
  def show_field?(:patent_status, type), do: type == :karya_teknologi
  def show_field?(:hki_number, type), do: type in [:karya_teknologi, :karya_kreatif]
  def show_field?(:industry_tested_at, type), do: type == :karya_teknologi

  # Shared thesis fields (research metadata)
  def show_field?(:thesis_type_detail, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  def show_field?(:research_location, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  def show_field?(:research_period, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  def show_field?(:funding_source, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  def show_field?(:subject_classification, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  def show_field?(:originality_statement, type),
    do: type in [:skripsi, :tesis, :disertasi, :tugas_akhir]

  # Universal fields — always visible
  def show_field?(:title, _), do: true
  def show_field?(:title_alt, _), do: true
  def show_field?(:abstract, _), do: true
  def show_field?(:abstract_alt, _), do: true
  def show_field?(:language, _), do: true
  def show_field?(:faculty, _), do: true
  def show_field?(:department, _), do: true
  def show_field?(:program_study, _), do: true
  def show_field?(:institution, _), do: true
  def show_field?(:publication_year, _), do: true
  def show_field?(:date_issued, _), do: true
  def show_field?(:place_of_publication, type), do: type in @journal_like_types

  # Catch-all: hidden by default
  def show_field?(_field, _type), do: false

  # ── Labels ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the display label to use for the abstract field based on item type.
  """
  def abstract_label(:karya_kreatif), do: "Pernyataan Artistik"
  def abstract_label(:karya_teknologi), do: "Deskripsi Masalah dan Solusi"
  def abstract_label(:capstone), do: "Ringkasan Eksekutif"
  def abstract_label(_), do: "Abstrak"

  # ── Required roles ─────────────────────────────────────────────────────────

  @doc """
  Returns the required advisor/examiner roles for a given item type.
  Thesis types (skripsi/tesis/disertasi/tugas_akhir) and memorandum hukum
  require examiners; capstone requires an industry partner.
  """
  def required_roles(type) when type in [:skripsi, :tesis, :disertasi, :tugas_akhir],
    do: [:main_advisor, :examiner]

  def required_roles(:memorandum_hukum), do: [:main_advisor, :examiner]
  def required_roles(:studi_kasus), do: [:main_advisor]
  def required_roles(:laporan_proyek), do: [:main_advisor]
  def required_roles(:karya_kreatif), do: [:main_advisor]
  def required_roles(:karya_teknologi), do: [:main_advisor]
  def required_roles(:jurnal_nasional), do: [:main_advisor]
  def required_roles(:jurnal_internasional), do: [:main_advisor]
  def required_roles(:prosiding), do: [:main_advisor]
  def required_roles(:capstone), do: [:main_advisor, :industry]
  def required_roles(_), do: [:main_advisor]

  # ── Type display names ─────────────────────────────────────────────────────

  @type_labels %{
    skripsi: "Skripsi",
    tesis: "Tesis",
    disertasi: "Disertasi",
    tugas_akhir: "Tugas Akhir",
    memorandum_hukum: "Memorandum Hukum",
    studi_kasus: "Studi Kasus",
    laporan_proyek: "Laporan Proyek",
    karya_kreatif: "Karya Kreatif",
    karya_teknologi: "Karya Teknologi",
    jurnal_nasional: "Jurnal Nasional",
    jurnal_internasional: "Jurnal Internasional",
    prosiding: "Prosiding",
    capstone: "Capstone"
  }

  @doc """
  Returns the human-readable display name for an item type atom.
  """
  def type_label(type) when is_atom(type) do
    Map.get(@type_labels, type, type |> to_string() |> String.replace("_", " "))
  end

  @doc """
  Returns the list of all supported item types as atoms.
  """
  def all_types, do: Map.keys(@type_labels)
end
