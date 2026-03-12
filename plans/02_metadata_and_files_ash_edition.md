# Metadata & File Fields by Tugas Akhir Type — Ash Edition
## Indonesian Institutional Repository — Complete Field & Bitstream Reference
### Covers All 10 Item Types · Ash Resource Mapping · Bitstream Storage Rules

---

## 0. How to Read This Document

This document is the single source of truth for **what data to collect** and **what files to store** for each of the 10 tugas akhir types supported by the repository. It is organized for direct use by a coding agent building Ash resources.

For every section, field tiers are defined as:

| Tier | Meaning in Ash |
|------|---------------|
| **Mandatory** | `allow_nil?: false` on the attribute, or validated `present()` in the action |
| **Optional** | `allow_nil?: true` (default in Ash), no `present()` validation |
| **Supplementary** | `allow_nil?: true`, stored in `item_metadata_extras` table as `schema.element.qualifier` row |

Storage location is one of three places:

| Location | When to Use |
|----------|-------------|
| **Column in `items` table** | Single-value, flat scalar field — goes in the `Item` Ash resource attributes |
| **Row in a child table** | Multi-value or repeating fields — goes in its own Ash resource (`ItemAuthor`, `ItemAdvisor`, `ItemExaminer`, `ItemTeamMember`, `ItemKeyword`) |
| **Row in `item_metadata_extras`** | Rare, supplementary, or type-specific fields not worth a dedicated column — stored as `{field_schema}.{field_element}.{field_qualifier}` |

File storage: every file becomes **one row** in the `bitstreams` table via the `Bitstream` Ash resource. Section 2 defines the bundle system and access defaults. Sections 3–12 specify exactly which files each type requires.

---

## 1. Item Type Enum Values

The `item_type` attribute on the `Item` resource uses these atom values:

```elixir
# In Item Ash resource:
attribute :item_type, :atom,
  constraints: [one_of: [
    :skripsi,            # 1 — S1/S2/S3 academic thesis
    :memorandum_hukum,   # 2 — Legal memorandum (FH)
    :studi_kasus,        # 3 — Case study (Bisnis/Kedokteran/Psikologi/Hukum)
    :laporan_proyek,     # 4 — Project report (Teknik/Vokasi/Arsitektur)
    :karya_kreatif,      # 5 — Creative work (Seni/Desain/Sastra/Musik/Film)
    :karya_teknologi,    # 6 — Technological work (Informatika/Teknik Terapan)
    :jurnal_nasional,    # 7 — Sinta-accredited national journal article
    :jurnal_internasional, # 8 — Scopus/WoS international journal article
    :prosiding,          # 9 — International conference proceedings
    :capstone,           # 10 — Capstone / MBKM project
  ]],
  default: :skripsi,
  public?: true
```

---

## 2. Bundle System & Bitstream Access Defaults

Every file uploaded becomes one `Bitstream` row. The `bundle_name` attribute groups files by purpose.

### 2.1 Bundle Name Enum

```elixir
# In Bitstream Ash resource:
attribute :bundle_name, :atom,
  constraints: [one_of: [
    :ORIGINAL,        # Primary documents (full text, published article, main work)
    :THUMBNAIL,       # Cover image — always public
    :CHAPTER,         # Per-chapter PDFs (Skripsi/Tesis)
    :SUPPLEMENTAL,    # Supporting docs (daftar isi, lampiran, bibliography)
    :ADMINISTRATIVE,  # Restricted internal docs (pengesahan, acceptance letter)
    :LICENSE,         # Originality statements, license agreements
    :MEDIA,           # Audio, video, image files (Karya Kreatif/Teknologi)
    :SOURCE,          # Source code archives, datasets, technical drawings
  ]],
  default: :ORIGINAL,
  public?: true
```

### 2.2 Default Access Level per Bundle

This default is applied in the import task and submission wizard when no override is specified.

| Bundle | Default `access_level` | Effective Access |
|--------|----------------------|-----------------|
| `ORIGINAL` | `:inherit` | Follows parent `item.access_level` |
| `THUMBNAIL` | `:open` | **Always public** — never restrict cover images |
| `CHAPTER` | `:inherit` | Follows parent `item.access_level` |
| `SUPPLEMENTAL` | `:inherit` | Follows parent `item.access_level` |
| `ADMINISTRATIVE` | `:restricted` | **Staff / Admin only** — never public |
| `LICENSE` | `:restricted` | Staff / Admin only |
| `MEDIA` | `:inherit` | Follows parent `item.access_level` |
| `SOURCE` | `:inherit` | Follows parent `item.access_level` |

### 2.3 Files That Are Always Restricted (Regardless of Item Access Level)

Set these bitstreams to `access_level: :restricted` unconditionally in your import task and submission wizard:

- `file_approval_letter` — Lembar pengesahan
- `file_originality_statement` — Pernyataan keaslian bermaterai
- `file_acceptance_letter` — Surat accepted dari jurnal
- `file_turnitin_report` — Laporan similarity Turnitin / iThenticate
- `file_ethics_approval` — Surat ethical clearance / Komite Etik
- `file_informed_consent` — Informed consent form
- `file_nda` — NDA / perjanjian kerahasiaan
- `file_hki_certificate` — Sertifikat HKI / DJKI
- `file_scopus_indexing_proof` — Bukti indexing Scopus
- `file_doi_certificate` — Bukti DOI registered
- `file_mbkm_logbook` — Logbook kegiatan MBKM
- `file_financial_report` — Laporan keuangan proyek
- `file_client_authorization` — Surat kuasa dari klien (legal clinic)
- `file_client_acceptance` — Berita acara serah terima proyek
- `file_patent_application` — Dokumen permohonan paten
- `file_conference_registration` — Bukti registrasi konferensi
- `file_partner_endorsement` — Surat endorsement mitra capstone
- `file_minutes_of_meeting` — Berita acara rapat

### 2.4 Files Subject to Embargo

When `item.embargo_open_date` is set, restrict these file bundles until that date. Cover images and abstract pages are **not** embargoed — metadata stays visible.

- `ORIGINAL` (excluding `file_abstract` at sequence 1, and cover)
- `CHAPTER` (all chapter files)
- `SOURCE` (main artifact — for Karya Teknologi)
- `MEDIA` (main work — for Karya Kreatif)

### 2.5 Bitstream Row Fields Reference

When inserting into the `bitstreams` table, populate these fields:

| Ash Attribute | Required | Notes |
|--------------|---------|-------|
| `filename` | Yes | Original filename as uploaded |
| `bundle_name` | Yes | Atom from the enum above |
| `sequence` | Yes | Integer order within the bundle (1 = primary/first) |
| `description` | Recommended | Human-readable label, e.g. `"Full Thesis PDF"`, `"Chapter 1 - Pendahuluan"` |
| `storage_type` | Yes | `:url` / `:s3` / `:local` |
| `storage_url` | If `:url` | Full external URL (e.g. existing S3 link from legacy data) |
| `storage_path` | If `:s3` or `:local` | S3 key or filesystem path |
| `storage_bucket` | If `:s3` | S3 bucket name |
| `mime_type` | Recommended | `application/pdf`, `image/jpeg`, `video/mp4`, etc. |
| `access_level` | Yes | Use bundle default from table above unless overriding |
| `embargo_open_date` | If embargoed | Date from which access opens — `nil` = no embargo |
| `embargo_close_date` | If time-limited | Date after which access closes — `nil` = no close embargo |
| `item_id` | Yes | FK to parent `Item` |

---

## 3. Universal Fields & Files (All 10 Types)

These fields and files apply to **every item regardless of type**. They are defined as columns in the `Item` resource and as mandatory bitstreams in the `Bitstream` resource.

### 3.1 Universal Metadata Fields

All mandatory. Map directly to `Item` resource attributes.

| Field | Ash Attribute | Type | Constraint | Notes |
|-------|--------------|------|------------|-------|
| `title` | `:title` | `:string` | `allow_nil?: false` | Judul dalam bahasa Indonesia |
| `title_alt` | `:title_alt` | `:string` | `allow_nil?: false` | Judul bahasa Inggris — required by Permenristekdikti No. 44/2015 |
| `language` | `:language` | `:atom` | `one_of: [:id, :en]` | ISO 639-1. Default `:id` |
| `abstract` | `:abstract` | `:string` | `allow_nil?: false` | Abstrak bahasa Indonesia |
| `abstract_alt` | `:abstract_alt` | `:string` | `allow_nil?: false` | Abstrak bahasa Inggris |
| `author_name` | `item_authors` row | relational | `present(:author_name)` | Goes into `ItemAuthor` table, not a column on `items` |
| `student_id` | `:student_id` | `:string` | `allow_nil?: false` for thesis types | NIM / NPM |
| `program_study` | `:program_study` | `:string` | — | Program Studi |
| `faculty` | `:faculty` | `:string` | — | Fakultas |
| `institution` | `:institution` | `:string` | default: your university name | Nama institusi |
| `date_submitted` | `:date_submitted` | `:date` | — | Tanggal pengumpulan ke repositori |
| `publication_year` | `:publication_year` | `:integer` | — | Tahun terbit / sidang |
| `access_level` | `:access_level` | `:atom` | `one_of: [:open, :restricted, :closed]` | Default `:open` |
| `status` | `:status` | `:atom` | `one_of: [:draft, :submitted, :under_review, :published, :withdrawn]` | Default `:draft` |
| `item_type` | `:item_type` | `:atom` | `one_of: [10 types]` | Drives field visibility in the UI |

> **Keywords**: `keywords` and `keywords_alt` are **not** columns on `items`. Each keyword becomes one row in `ItemKeyword` with a `language` field (`:id` or `:en`). Minimum 3, maximum 5 keywords per language.

> **`institution`**: Add this attribute to the `Item` resource if not already present. Default it to your university name via a Change in the `create` action.

### 3.2 Universal Mandatory Files

These 4 files are required for every single item regardless of type.

| Field Key | Bundle | Format | `access_level` | Sequence | Description |
|-----------|--------|--------|----------------|----------|-------------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` (always) | 1 | Halaman sampul / cover page. Shown as thumbnail in search results. Never embargo. |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | 1 | Halaman abstrak (bilingual). Sequence 1 = not embargoed even when full text is. |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` (always) | 1 | Lembar pengesahan yang sudah ditandatangani. Never public. |
| `file_originality_statement` | `LICENSE` | PDF | `:restricted` (always) | 1 | Pernyataan keaslian / anti-plagiarisme bermaterai. |

---

## 4. Type 1 — Skripsi / Tesis / Disertasi

Standard academic thesis. S1 = Skripsi, S2 = Tesis, S3 = Disertasi.

### 4.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :s2, :s3]` |
| `department` | `:department` | `:string` | Departemen / Jurusan |
| `date_issued` | `:date_issued` | `:date` | Tanggal sidang / ujian |
| `approval_date` | `:approval_date` | `:date` | Tanggal lembar pengesahan ditandatangani |

#### Mandatory — Relational Tables

| Field | Table | Ash Resource | Notes |
|-------|-------|-------------|-------|
| `main_advisor` | `item_advisors` | `ItemAdvisor` | `advisor_role: :main_advisor` |
| `co_advisor` | `item_advisors` | `ItemAdvisor` | `advisor_role: :co_advisor` — required for S2/S3 |
| `examiner_1` | `item_examiners` | `ItemExaminer` | `role: :examiner`, `sequence: 1` |
| `examiner_2` | `item_examiners` | `ItemExaminer` | `role: :examiner`, `sequence: 2` |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `research_location` | `:research_location` | `:string` | Lokasi penelitian lapangan |
| `research_period` | `:research_period` | `:string` | e.g. "Januari–Maret 2024" |
| `funding_source` | `:funding_source` | `:string` | Sumber pendanaan / hibah |
| `subject_classification` | `:subject_classification` | `:string` | Nomor DDC / UDC |
| `originality_statement` | `:originality_statement` | `:boolean` | Pernyataan keaslian (checked) |
| `thesis_type_detail` | `:thesis_type_detail` | `:atom` | `one_of: [:kuantitatif, :kualitatif, :mixed_methods, :rnd, :ptk]` |
| `embargo_open_date` | `:embargo_open_date` | `:date` | Tanggal embargo berakhir |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `examiner_3` | `item_examiners` | `sequence: 3`, if applicable |
| `external_advisor` | `item_advisors` | `advisor_role: :external` — pembimbing dari industri / lembaga lain |

#### Supplementary — `item_metadata_extras` rows

Store these as `{field_schema}.{field_element}.{field_qualifier}`:

| Field | Key | Value |
|-------|-----|-------|
| `dedication` | `local.description.dedication` | Halaman persembahan text |
| `acknowledgement` | `local.description.acknowledgement` | Kata pengantar text |
| `related_publication` | `dc.relation.uri` | DOI / URL artikel yang terbit dari tesis ini |
| `previous_degree` | `dc.description.degree` | Gelar sebelumnya (S2/S3 relevant) |
| `orcid_id` | `dc.contributor.orcid` | ORCID mahasiswa |
| `scopus_author_id` | `local.identifier.scopusauthor` | Scopus Author ID |

### 4.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Halaman sampul |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Abstrak — sequence 1, not embargoed |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_originality_statement` | `LICENSE` | PDF | `:restricted` | Pernyataan keaslian bermaterai |
| `file_fulltext` **OR** at least `file_bab1` | `ORIGINAL` / `CHAPTER` | PDF | `:inherit` | Full thesis as one PDF OR split by chapter. At least one is required. |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_bab1` | `CHAPTER` | PDF | `:inherit` | Pendahuluan (sequence 1) |
| `file_bab2` | `CHAPTER` | PDF | `:inherit` | Tinjauan Pustaka (sequence 2) |
| `file_bab3` | `CHAPTER` | PDF | `:inherit` | Metodologi Penelitian (sequence 3) |
| `file_bab4` | `CHAPTER` | PDF | `:inherit` | Hasil dan Pembahasan (sequence 4) |
| `file_bab5` | `CHAPTER` | PDF | `:inherit` | Kesimpulan dan Saran (sequence 5) |
| `file_bab6` | `CHAPTER` | PDF | `:inherit` | Bab 6 jika ada — e.g. implementation + evaluation (sequence 6) |
| `file_daftar_isi` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar isi |
| `file_pustaka` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar pustaka / referensi |
| `file_lampiran` | `SUPPLEMENTAL` | PDF | `:inherit` | Lampiran (kuesioner, raw data, dll) |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi sidang |
| `file_turnitin_report` | `ADMINISTRATIVE` | PDF | `:restricted` | Laporan similarity Turnitin / iThenticate |
| `file_ethical_clearance` | `ADMINISTRATIVE` | PDF | `:restricted` | **Mandatory for medical/public health** — surat ethical clearance |

#### Supplementary

| Field Key | Bundle | Format | Notes |
|-----------|--------|--------|-------|
| `file_raw_data` | `SUPPLEMENTAL` | XLSX / CSV / SAV / ZIP | Dataset penelitian mentah |
| `file_instruments` | `SUPPLEMENTAL` | PDF / DOCX | Kuesioner, panduan wawancara |
| `file_transcripts` | `SUPPLEMENTAL` | PDF | Transkrip wawancara (anonymized) |
| `file_publication` | `ORIGINAL` | PDF | Artikel yang terbit dari tesis ini |

---

## 5. Type 2 — Memorandum Hukum (Legal Memorandum)

Specific to Fakultas Hukum. Shares base structure with Skripsi but adds legal-specific fields.

### 5.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :s2]` |
| `legal_subject_matter` | `:legal_subject_matter` | `:atom` | `one_of: [:pidana, :perdata, :tata_negara, :internasional, :bisnis, :adat, :agraria, :lingkungan]` |
| `case_reference` | `:case_reference` | `:string` | Nomor perkara / putusan, e.g. `"Putusan MA No. 123/Pid/2022"` |
| `court_level` | `:court_level` | `:atom` | `one_of: [:pn, :pt, :ma, :mk, :ptun, :arbitrase, :bani, :icc]` |
| `legal_issue` | `:legal_issue` | `:string` | The legal question being analyzed (stored as text) |
| `date_issued` | `:date_issued` | `:date` | Tanggal sidang / pengesahan |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |
| `examiner_1`, `examiner_2` | `item_examiners` | Penguji sidang |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `jurisdiction` | `:jurisdiction` | `:atom` | `one_of: [:indonesia, :internasional, :komparatif]` |
| `legal_analysis_method` | `:legal_analysis_method` | `:atom` | `one_of: [:normatif, :empiris, :komparatif, :socio_legal]` |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `related_legislation` | `item_metadata_extras` | `key: "local.relation.legislation"`, one row per regulation |
| `law_clinic_supervisor` | `item_advisors` | `advisor_role: :law_clinic` |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `verdict` | `local.description.verdict` | Summary of verdict in analyzed case |
| `related_case` | `local.relation.case` | Multi-value: one row per related case |
| `legal_reform_recommendation` | `local.description.recommendation` | |
| `client_type` | `local.description.clienttype` | `individu` / `korporasi` / `negara` |

### 5.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Halaman sampul |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Halaman abstrak |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_originality_statement` | `LICENSE` | PDF | `:restricted` | Pernyataan keaslian |
| `file_fulltext` | `ORIGINAL` | PDF | `:inherit` | Full memorandum hukum |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_court_decision` | `SUPPLEMENTAL` | PDF | `:inherit` | Salinan putusan pengadilan yang dikaji |
| `file_legislation_copies` | `SUPPLEMENTAL` | PDF | `:inherit` | Salinan peraturan perundangan |
| `file_daftar_isi` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar isi |
| `file_pustaka` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar pustaka |
| `file_lampiran` | `SUPPLEMENTAL` | PDF | `:inherit` | Lampiran (surat kuasa, dokumen pendukung) |
| `file_client_authorization` | `ADMINISTRATIVE` | PDF | `:restricted` | Surat kuasa dari klien (jika dari klinik hukum) |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi sidang |

---

## 6. Type 3 — Studi Kasus (Case Study)

Common in Ekonomi/Bisnis, Kedokteran/Kesehatan, Psikologi, and Hukum. Access restrictions are especially important here due to privacy and ethics requirements.

### 6.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :s2, :s3]` |
| `case_study_type` | `:case_study_type` | `:atom` | `one_of: [:bisnis, :klinis, :hukum, :psikologi, :pendidikan, :teknik]` |
| `case_subject` | `:case_subject` | `:string` | Subjek/objek kasus — nama org, anonymized patient ID, dll |
| `case_period` | `:case_period` | `:string` | Periode kasus yang dikaji |
| `case_location` | `:case_location` | `:string` | Lokasi/setting kasus, or `"anonim"` |
| `analysis_framework` | `:analysis_framework` | `:string` | SWOT, BCG Matrix, DSM-5, dll |
| `date_issued` | `:date_issued` | `:date` | Tanggal sidang / pengesahan |
| `subject_anonymized` | `:subject_anonymized` | `:boolean` | Default `false` |
| `informed_consent` | `:informed_consent` | `:boolean` | Default `false` |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `ethics_approval_number` | `:ethics_approval_number` | `:string` | **CRITICAL for medical/psychology** — Nomor persetujuan Komite Etik |
| `industry_partner` | `:industry_partner` | `:string` | Nama perusahaan (if not anonymized) |
| `data_collection_method` | `:data_collection_method` | `:atom` | `one_of: [:wawancara, :observasi, :dokumen_sekunder, :mix]` |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `industry_supervisor` | `item_advisors` | `advisor_role: :industry` — nama + jabatan mitra |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `case_outcome` | `local.description.outcome` | Hasil / rekomendasi kasus |
| `sic_kbli_code` | `local.identifier.kbli` | KBLI code for business cases |
| `company_size` | `local.description.companysize` | `umkm` / `menengah` / `besar` |
| `icd_code` | `local.subject.icd` | ICD-10/11 code for medical studies |
| `dsm_code` | `local.subject.dsm` | DSM code for psychology studies |
| `nda_status` | `local.rights.nda` | Boolean |

### 6.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Halaman sampul |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Halaman abstrak |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_originality_statement` | `LICENSE` | PDF | `:restricted` | Pernyataan keaslian |
| `file_fulltext` | `ORIGINAL` | PDF | `:inherit` | Full case study document |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_ethics_approval` | `ADMINISTRATIVE` | PDF | `:restricted` | **Mandatory for medical/psychology** — Surat Komite Etik |
| `file_informed_consent` | `ADMINISTRATIVE` | PDF | `:restricted` | Informed consent form — always restricted |
| `file_interview_transcript` | `SUPPLEMENTAL` | PDF | `:inherit` | Transkrip wawancara — **must be anonymized before upload** |
| `file_observation_notes` | `SUPPLEMENTAL` | PDF | `:inherit` | Catatan observasi lapangan |
| `file_company_documents` | `SUPPLEMENTAL` | PDF | `:inherit` | Annual report, SOP, dokumen perusahaan |
| `file_nda` | `ADMINISTRATIVE` | PDF | `:restricted` | NDA dengan mitra |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi |
| `file_daftar_isi` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar isi |
| `file_lampiran` | `SUPPLEMENTAL` | PDF | `:inherit` | Lampiran |

---

## 7. Type 4 — Laporan Proyek (Project Report)

Common in Teknik, Vokasi (D3/D4/Sarjana Terapan), and Arsitektur. Often the most file-heavy type outside of thesis.

### 7.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:d3, :d4, :s1_terapan, :s1]` |
| `project_title` | `:project_title` | `:string` | Nama resmi proyek (may differ from item title) |
| `project_type` | `:project_type` | `:atom` | `one_of: [:desain, :konstruksi, :implementasi_software, :manufaktur, :sistem, :perencanaan_wilayah]` |
| `project_client` | `:project_client` | `:string` | Nama klien / mitra |
| `project_period` | `:project_period` | `:string` | Tanggal mulai dan selesai proyek |
| `project_location` | `:project_location` | `:string` | Lokasi pelaksanaan |
| `project_deliverable` | `:project_deliverable` | `:string` | Apa yang diserahkan: prototipe / software / desain / dokumen teknis |
| `date_issued` | `:date_issued` | `:date` | Tanggal pengesahan laporan |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `team_role` | `:team_role` | `:atom` | `one_of: [:ketua, :anggota, :pic_teknis]` — peran mahasiswa yang submit |
| `project_budget` | `:project_budget` | `:string` | Anggaran proyek (if publishable) |
| `patent_pending` | `:patent_pending` | `:boolean` | Sedang dalam proses paten |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `team_members` | `item_team_members` | Anggota tim lain (nama + NIM + peran) |
| `industry_supervisor` | `item_advisors` | `advisor_role: :industry` — nama + jabatan + perusahaan |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `technology_stack` | `local.description.techstack` | Multi-value: one row per technology/tool |
| `standard_reference` | `local.relation.standard` | Multi-value: SNI, ISO, IEEE codes |
| `project_scale` | `local.description.scale` | `pilot` / `production` / `prototype` |
| `source_code_url` | `dc.relation.uri` | GitHub / GitLab link |
| `deployment_url` | `local.identifier.deploymenturl` | Live URL |
| `carbon_footprint` | `local.description.sustainability` | |

### 7.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Halaman sampul |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Ringkasan eksekutif / abstrak |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_originality_statement` | `LICENSE` | PDF | `:restricted` | Pernyataan keaslian |
| `file_fulltext` | `ORIGINAL` | PDF | `:inherit` | Laporan proyek lengkap |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_technical_drawing` | `SOURCE` | PDF / DWG / DXF | `:inherit` | Gambar teknik / blueprint / CAD output |
| `file_prototype_photo` | `MEDIA` | JPG / PNG / ZIP | `:inherit` | Foto prototipe / hasil proyek |
| `file_test_result` | `SUPPLEMENTAL` | PDF | `:inherit` | Laporan hasil pengujian |
| `file_user_manual` | `SUPPLEMENTAL` | PDF | `:inherit` | Manual pengguna / SOP |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi |
| `file_project_charter` | `SUPPLEMENTAL` | PDF | `:inherit` | Dokumen project charter / proposal awal |
| `file_minutes_of_meeting` | `ADMINISTRATIVE` | PDF | `:restricted` | Berita acara rapat |
| `file_client_acceptance` | `ADMINISTRATIVE` | PDF | `:restricted` | Berita acara serah terima proyek |
| `file_daftar_isi` | `SUPPLEMENTAL` | PDF | `:inherit` | Daftar isi |
| `file_lampiran` | `SUPPLEMENTAL` | PDF | `:inherit` | Lampiran |
| `file_source_code` | `SOURCE` | ZIP / TAR.GZ | `:inherit` | Source code archive |
| `file_pcb_schematic` | `SOURCE` | PDF / Gerber | `:inherit` | Skematik PCB / circuit diagram (hardware projects) |
| `file_bom` | `SUPPLEMENTAL` | PDF / XLSX | `:inherit` | Bill of Materials |

---

## 8. Type 5 — Karya Kreatif (Creative Work)

Seni Rupa, Desain, Sastra, Musik, Film, Arsitektur, Kriya. Most varied file formats of all 10 types.

### 8.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :s2, :s3]` |
| `creative_work_type` | `:creative_work_type` | `:atom` | `one_of: [:novel, :antologi_puisi, :film_pendek, :komposisi_musik, :lukisan, :desain_produk, :animasi, :game, :arsitektur, :kriya]` |
| `medium_material` | `:medium_material` | `:string` | Media/bahan: cat minyak / digital / kayu / video / audio |
| `dimensions_duration` | `:dimensions_duration` | `:string` | Ukuran (cm × cm) atau durasi (mm:ss) |
| `creation_period` | `:creation_period` | `:string` | Periode penciptaan karya |
| `artistic_statement` | `:artistic_statement` | `:string` | Pernyataan artistik / konsep (the "abstract" for creative works) |
| `date_issued` | `:date_issued` | `:date` | Tanggal ujian / pameran |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` — Pembimbing / Promotor |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `exhibition_performance` | `:exhibition_performance` | `:string` | Nama pameran / pertunjukan |
| `exhibition_date` | `:exhibition_date` | `:date` | Tanggal pameran / pertunjukan |
| `exhibition_venue` | `:exhibition_venue` | `:string` | Tempat pameran |
| `copyright_type` | `:copyright_type` | `:atom` | `one_of: [:all_rights_reserved, :cc_by, :cc_by_sa, :cc_by_nc, :cc_by_nc_sa]` |
| `collection_owner` | `:collection_owner` | `:string` | Siapa yang menyimpan karya fisik saat ini |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `curator_director` | `item_advisors` | `advisor_role: :curator` |
| `collaborators` | `item_team_members` | Penari, musisi, aktor, dll |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `inspiration_source` | `local.description.inspiration` | Referensi / inspirasi utama |
| `audience_reception` | `local.description.reception` | Review / catatan respons audiens |
| `iswc` | `local.identifier.iswc` | International Standard Musical Work Code |
| `isrc` | `local.identifier.isrc` | International Standard Recording Code |
| `isbn` | `dc.identifier.isbn` | ISBN (if published as book) |
| `hak_cipta_number` | `local.identifier.hki` | Nomor pendaftaran HKI di DJKI |
| `color_palette` | `local.description.colorpalette` | Palet warna utama |

### 8.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Cover / representasi visual karya |
| `file_artistic_statement` | `ORIGINAL` | PDF | `:inherit` | Pernyataan artistik / konsep karya (sequence 1) |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_main_work` | `ORIGINAL` | **Varies** | `:inherit` | **File utama karya itu sendiri** |

**`file_main_work` accepted formats by creative type:**

| Creative Type | Accepted Formats |
|--------------|-----------------|
| Novel / Antologi Puisi / Naskah Drama | PDF |
| Komposisi Musik (partitur) | PDF / MusicXML |
| Rekaman Musik | MP3 / FLAC / WAV |
| Film Pendek / Animasi | MP4 / MOV (or external URL stored as `storage_type: :url`) |
| Lukisan / Karya Seni Rupa 2D | JPG / PNG / TIFF (min 300 DPI) |
| Karya 3D / Patung / Kriya | JPG / PNG (multiple angles) + PDF documentation |
| Desain Produk | PDF / JPG (renders) + technical drawing |
| Game | ZIP (playable build) or external URL |
| Arsitektur | PDF (full drawing set) + JPG renders |
| Fotografi | JPG / TIFF + PDF catalog |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_process_documentation` | `SUPPLEMENTAL` | PDF / ZIP of JPG | `:inherit` | Dokumentasi proses: sketsa awal, foto proses |
| `file_exhibition_documentation` | `MEDIA` | JPG / MP4 / PDF | `:inherit` | Foto / video saat dipamerkan |
| `file_program_booklet` | `SUPPLEMENTAL` | PDF | `:inherit` | Program book pameran / pertunjukan |
| `file_score_parts` | `SOURCE` | PDF | `:inherit` | Bagian instrumen terpisah (ensemble music) |
| `file_screenplay` | `SUPPLEMENTAL` | PDF | `:inherit` | Naskah skenario (for film) |
| `file_storyboard` | `SUPPLEMENTAL` | PDF | `:inherit` | Storyboard (film / animation / game) |
| `file_technical_rider` | `SUPPLEMENTAL` | PDF | `:inherit` | Technical rider pementasan |
| `file_hki_certificate` | `ADMINISTRATIVE` | PDF | `:restricted` | Sertifikat HKI / DJKI |
| `file_artist_statement_video` | `MEDIA` | MP4 | `:inherit` | Video pernyataan artistik oleh mahasiswa |
| `file_review_documentation` | `SUPPLEMENTAL` | PDF | `:inherit` | Review / kritik dari kurator / juri |

---

## 9. Type 6 — Karya Teknologi (Technological Work)

Software, hardware, apps, AI/ML models, datasets. Common in Informatika, Teknik Terapan.

### 9.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :s2, :s3]` |
| `technology_type` | `:technology_type` | `:atom` | `one_of: [:aplikasi_mobile, :web_app, :embedded_system, :perangkat_keras, :dataset, :model_ai_ml, :algoritma, :inovasi_proses]` |
| `problem_solved` | `:problem_solved` | `:string` | Masalah yang diselesaikan (the "abstract" for tech works) |
| `target_user` | `:target_user` | `:string` | Pengguna yang dituju / beneficiary |
| `implementation_status` | `:implementation_status` | `:atom` | `one_of: [:prototipe, :mvp, :deployed, :published]` |
| `testing_method` | `:testing_method` | `:atom` | `one_of: [:black_box, :white_box, :user_testing, :benchmark, :usability]` |
| `date_issued` | `:date_issued` | `:date` | Tanggal pengesahan |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `license_type` | `:license_type` | `:atom` | `one_of: [:mit, :apache_2, :gpl, :bsd, :proprietary]` |
| `patent_status` | `:patent_status` | `:atom` | `one_of: [:tidak_ada, :dalam_proses, :granted]` |
| `hki_number` | `:hki_number` | `:string` | Nomor HKI / DJKI |
| `industry_tested_at` | `:industry_tested_at` | `:string` | Nama institusi/perusahaan tempat uji coba |

#### Optional — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `co_developers` | `item_team_members` | Rekan pengembang (nama + NIM + role) |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `technology_stack` | `local.description.techstack` | Multi-value: one row per language/framework/tool |
| `platform_os` | `local.description.platform` | Multi-value: Android / iOS / Web / Linux / Arduino |
| `performance_metrics` | `local.description.metrics` | Accuracy %, response time, throughput |
| `test_cases_count` | `local.description.testcases` | Integer as string |
| `source_code_url` | `dc.relation.uri` | GitHub / GitLab URL |
| `deployment_url` | `local.identifier.deploymenturl` | Live URL |
| `dataset_url` | `local.identifier.dataseturl` | Mendeley Data, Zenodo, Kaggle |
| `api_documentation_url` | `local.identifier.apidocs` | API docs URL |
| `model_architecture` | `local.description.modelarch` | ResNet-50, BERT, Transformer, etc. |
| `training_dataset` | `local.description.trainingdata` | Dataset used for training |
| `hardware_spec` | `local.description.hardwarespec` | Minimum hardware specification |
| `doi_zenodo` | `dc.identifier.doi` | DOI from Zenodo or data repository |
| `acm_classification` | `local.subject.acm` | ACM CCS code |
| `energy_consumption` | `local.description.energy` | For hardware/IoT |

### 9.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Cover laporan / screenshot UI |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Abstrak karya teknologi (sequence 1) |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_technical_report` | `ORIGINAL` | PDF | `:inherit` | Laporan teknis lengkap (methodology, design, testing) |
| `file_main_artifact` | `SOURCE` | **Varies** | `:inherit` | **Artefak utama teknologi** |

**`file_main_artifact` accepted formats by technology type:**

| Technology Type | Accepted Formats |
|----------------|-----------------|
| Aplikasi Mobile | APK / IPA + PDF documentation |
| Web Application | ZIP (deployable) or URL link |
| Embedded System / Hardware | ZIP (firmware + schematics) |
| Model AI / ML | Pickle / H5 / ONNX / ZIP + Python notebook |
| Dataset | CSV / JSON / XLSX / ZIP + README |
| Algoritma | PDF (pseudocode + proof) + source code |
| Perangkat Keras | PDF (circuit diagrams, specifications) |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_source_code` | `SOURCE` | ZIP / TAR.GZ | `:inherit` | Source code archive (if not using URL) |
| `file_test_report` | `SUPPLEMENTAL` | PDF | `:inherit` | Laporan pengujian: unit test, integration test, user testing |
| `file_user_manual` | `SUPPLEMENTAL` | PDF | `:inherit` | Manual pengguna |
| `file_api_documentation` | `SUPPLEMENTAL` | PDF / HTML | `:inherit` | Dokumentasi API |
| `file_demo_video` | `MEDIA` | MP4 | `:inherit` | Video demo / walkthrough |
| `file_prototype_photo` | `MEDIA` | JPG / PNG | `:inherit` | Foto prototipe hardware |
| `file_dataset` | `SOURCE` | CSV / JSON / ZIP | `:inherit` | Dataset yang digunakan / dihasilkan |
| `file_jupyter_notebook` | `SOURCE` | IPYNB / PDF | `:inherit` | Jupyter notebook (for ML/data projects) |
| `file_hki_certificate` | `ADMINISTRATIVE` | PDF | `:restricted` | Sertifikat HKI / DJKI |
| `file_patent_application` | `ADMINISTRATIVE` | PDF | `:restricted` | Dokumen permohonan paten |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi |

---

## 10. Type 7 — Artikel Jurnal Nasional Terakreditasi (Sinta)

### 10.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `journal_name` | `:journal_name` | `:string` | Nama jurnal — exact name as registered at Sinta |
| `sinta_id` | `:sinta_id` | `:string` | ID jurnal di portal Sinta |
| `sinta_accreditation` | `:sinta_accreditation` | `:atom` | `one_of: [:s1, :s2, :s3, :s4, :s5, :s6]` |
| `issn_print` | `:issn_print` | `:string` | ISSN cetak |
| `issn_online` | `:issn_online` | `:string` | ISSN online (E-ISSN) |
| `volume` | `:volume` | `:string` | Volume jurnal |
| `issue` | `:issue` | `:string` | Nomor / issue |
| `page_start` | `:page_start` | `:integer` | Halaman awal |
| `page_end` | `:page_end` | `:integer` | Halaman akhir |
| `doi` | `:doi` | `:string` | DOI artikel — mandatory for Sinta-accredited journals |
| `date_issued` | `:date_issued` | `:date` | Tanggal publikasi artikel |
| `publisher` | `:publisher` | `:string` | Penerbit jurnal |
| `corresponding_author` | `:corresponding_author` | `:string` | Nama + email corresponding author |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |
| `co_authors` | `item_authors` | Multi-value: nama, afiliasi, email, ORCID |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `garuda_id` | `:garuda_id` | `:string` | ID di portal Garuda |
| `crossref_registered` | `:crossref_registered` | `:boolean` | DOI sudah terdaftar di Crossref |
| `peer_review_type` | `:peer_review_type` | `:atom` | `one_of: [:single_blind, :double_blind, :open_review]` |
| `submission_date` | `:submission_date` | `:date` | Tanggal submit ke jurnal |
| `acceptance_date` | `:acceptance_date` | `:date` | Tanggal accepted |
| `article_type` | `:article_type` | `:atom` | `one_of: [:research_article, :review, :short_communication, :letter]` |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `conflict_of_interest` | `local.rights.conflict` | Pernyataan conflict of interest |
| `funding_statement` | `local.description.funding` | Pernyataan pendanaan |
| `citation_count` | `local.description.citationcount` | Jumlah sitasi |
| `open_access_status` | `local.rights.oastatus` | `gold` / `green` / `closed` |
| `preprint_url` | `dc.relation.uri` | OSF, arXiv, SSRN URL |
| `data_availability` | `local.identifier.dataurl` | Link ke dataset pendukung |

### 10.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Screenshot halaman depan artikel yang sudah terbit |
| `file_published_article` | `ORIGINAL` | PDF | `:inherit` | PDF artikel yang sudah diterbitkan (as published, with journal header) |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan dari institusi |
| `file_acceptance_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Surat accepted dari jurnal |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_manuscript_submitted` | `SUPPLEMENTAL` | PDF / DOCX | `:inherit` | Versi manuskrip sebelum accepted (author's copy) |
| `file_review_response` | `SUPPLEMENTAL` | PDF / DOCX | `:inherit` | Response to reviewers letter |
| `file_turnitin_report` | `ADMINISTRATIVE` | PDF | `:restricted` | Laporan similarity |
| `file_raw_data` | `SOURCE` | CSV / XLSX / ZIP | `:inherit` | Dataset penelitian pendukung |
| `file_supplementary_material` | `SUPPLEMENTAL` | PDF / ZIP | `:inherit` | Supplementary material dari jurnal |
| `file_postprint` | `SUPPLEMENTAL` | PDF | `:inherit` | Postprint / author-accepted manuscript (for Green OA deposit) |

---

## 11. Type 8 — Artikel Jurnal Internasional Bereputasi (Scopus / WoS)

Highest rigor level. Required for Laporan Kinerja Penelitian Dikti, BKD Dosen, NIDK reporting. Inherits all Type 7 fields, plus:

### 11.1 Metadata Fields

#### Mandatory — Additional Columns (beyond Type 7)

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `scopus_id` | `:scopus_id` | `:string` | Scopus Article ID / EID |
| `wos_id` | `:wos_id` | `:string` | Web of Science Accession Number |
| `sjr_score` | `:sjr_score` | `:decimal` | SCImago Journal Rank at time of publication |
| `impact_factor` | `:impact_factor` | `:decimal` | Journal Impact Factor / JIF (Clarivate, if WoS) |
| `quartile` | `:quartile` | `:atom` | `one_of: [:q1, :q2, :q3, :q4]` — **CRITICAL for Dikti reporting** |
| `subject_area` | `:subject_area` | `:string` | Scopus subject area / WoS category |
| `indexed_in` | `:indexed_in` | `:atom` | `one_of: [:scopus, :wos, :both]` |

#### Mandatory — Additional Relational

| Field | Table | Notes |
|-------|-------|-------|
| `all_co_authors_affiliation` | `item_authors` | Full affiliation of ALL co-authors — required for international collaboration tracking |

#### Optional — Additional Columns

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `altmetric_score` | `:altmetric_score` | `:integer` | Altmetric attention score |
| `special_issue` | `:special_issue` | `:string` | Nama special issue |
| `conference_origin` | `:conference_origin` | `:string` | Nama konferensi asal (if extended from proceedings) |
| `open_access_apc` | `:open_access_apc` | `:string` | APC value + currency |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `citation_count_scopus` | `local.description.citationscopus` | |
| `citation_count_wos` | `local.description.citationwos` | |
| `orcid_all_authors` | `dc.contributor.orcid` | Multi-value: one per author |
| `mendeley_readers` | `local.description.mendeley` | |
| `retraction_status` | `local.description.retraction` | Boolean |
| `pubmed_id` | `local.identifier.pubmed` | For medical/health journals |
| `lens_id` | `local.identifier.lens` | The Lens.org ID |

### 11.2 File Fields

#### Mandatory (all of Type 7, plus)

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_scopus_indexing_proof` | `ADMINISTRATIVE` | PDF / PNG | `:restricted` | Screenshot / bukti terindeks di Scopus atau WoS — required for BKD reporting |
| `file_doi_certificate` | `ADMINISTRATIVE` | PDF / PNG | `:restricted` | Bukti DOI registered (Crossref record screenshot) |

#### Optional (additional beyond Type 7)

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_wos_indexing_proof` | `ADMINISTRATIVE` | PDF / PNG | `:restricted` | Screenshot bukti indexing di WoS |
| `file_citation_screenshot` | `SUPPLEMENTAL` | PDF / PNG | `:inherit` | Screenshot jumlah sitasi (for tracking record) |
| `file_altmetric_screenshot` | `SUPPLEMENTAL` | PNG | `:inherit` | Screenshot Altmetric score |
| `file_raw_data_zenodo` | `SOURCE` | ZIP | `:inherit` | Dataset pendukung (local copy of Zenodo deposit) |
| `file_preprint` | `SUPPLEMENTAL` | PDF | `:inherit` | Preprint version (arXiv, OSF, SSRN) |
| `file_open_access_proof` | `ADMINISTRATIVE` | PDF / PNG | `:restricted` | Bukti pembayaran APC atau konfirmasi OA |

---

## 12. Type 9 — Artikel Prosiding Konferensi Internasional

### 12.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `conference_name` | `:conference_name` | `:string` | Nama konferensi (full official name) |
| `conference_acronym` | `:conference_acronym` | `:string` | e.g. "ICCV 2024", "ICSE 2024" |
| `conference_date` | `:conference_date` | `:date` | Tanggal penyelenggaraan |
| `conference_location` | `:conference_location` | `:string` | Kota, negara |
| `conference_type` | `:conference_type` | `:atom` | `one_of: [:onsite, :online, :hybrid]` |
| `proceeding_publisher` | `:proceeding_publisher` | `:string` | IEEE / ACM / Springer / Elsevier / dll |
| `proceeding_series` | `:proceeding_series` | `:string` | e.g. "Lecture Notes in Computer Science" |
| `doi` | `:doi` | `:string` | DOI artikel |
| `isbn_proceeding` | `:isbn_proceeding` | `:string` | ISBN prosiding (if published as book) |
| `issn_proceeding` | `:issn_proceeding` | `:string` | ISSN (if published as journal-like proceedings) |
| `presentation_type` | `:presentation_type` | `:atom` | `one_of: [:oral, :poster, :keynote, :workshop_paper]` |
| `page_start` | `:page_start` | `:integer` | Halaman awal |
| `page_end` | `:page_end` | `:integer` | Halaman akhir |
| `date_issued` | `:date_issued` | `:date` | Tanggal publikasi prosiding |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |
| `co_authors` | `item_authors` | nama, afiliasi, email — multi-value |
| `indexed_in` | `item_metadata_extras` | `key: "local.subject.indexed"` — multi-value: Scopus / IEEE Xplore / ACM DL |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `acceptance_rate` | `:acceptance_rate` | `:string` | Tingkat penerimaan konferensi |
| `presentation_date` | `:presentation_date` | `:date` | Tanggal presentasi aktual |
| `session_name` | `:session_name` | `:string` | Nama sesi / track di konferensi |
| `best_paper_award` | `:best_paper_award` | `:string` | Nama award (if received) |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `extended_to_journal` | `dc.relation.uri` | URL jurnal extension (if applicable) |
| `sponsor_conference` | `local.description.sponsor` | Sponsor / penyelenggara teknis |
| `core_rank` | `local.subject.corerank` | `A*` / `A` / `B` / `C` — CORE Conference Ranking |
| `virtual_presentation_url` | `local.identifier.presentationurl` | URL rekaman presentasi online |

### 12.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Screenshot halaman depan artikel dalam prosiding |
| `file_published_paper` | `ORIGINAL` | PDF | `:inherit` | PDF artikel dari prosiding yang sudah diterbitkan (as published) |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan |
| `file_acceptance_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Surat acceptance dari konferensi |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_presentation_slides` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi di konferensi |
| `file_poster` | `MEDIA` | PDF / JPG | `:inherit` | File poster (min A0 size) |
| `file_presentation_video` | `MEDIA` | MP4 / URL | `:inherit` | Rekaman presentasi (online/hybrid conferences) |
| `file_indexing_proof` | `ADMINISTRATIVE` | PDF / PNG | `:restricted` | Bukti artikel terindeks di Scopus / IEEE Xplore / ACM DL |
| `file_conference_registration` | `ADMINISTRATIVE` | PDF | `:restricted` | Bukti registrasi / pembayaran ke konferensi |
| `file_manuscript_submitted` | `SUPPLEMENTAL` | PDF | `:inherit` | Versi manuskrip awal yang disubmit |
| `file_raw_data` | `SOURCE` | CSV / XLSX / ZIP | `:inherit` | Dataset pendukung |

---

## 13. Type 10 — Capstone Project

Multidisciplinary, integrative, team-based. Aligned with MBKM (Merdeka Belajar Kampus Merdeka) schemes. Most varied combination of document and evidence files.

### 13.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `degree_level` | `:degree_level` | `:atom` | `one_of: [:s1, :d4]` |
| `capstone_theme` | `:capstone_theme` | `:string` | Tema besar, e.g. SDGs, Smart City, Ketahanan Pangan |
| `project_type` | `:project_type` | `:atom` | `one_of: [:product, :service, :policy, :research, :community]` |
| `team_lead` | `:team_lead` | `:string` | Nama ketua tim |
| `partner_institution` | `:partner_institution` | `:string` | Institusi mitra (DUDI / NGO / Pemda) |
| `problem_statement` | `:problem_statement` | `:string` | Rumusan masalah yang dihadapi mitra |
| `solution_description` | `:solution_description` | `:string` | Solusi yang dikembangkan tim |
| `impact_target` | `:impact_target` | `:string` | Target dampak yang terukur |
| `duration_semester` | `:duration_semester` | `:string` | Berapa SKS / semester |
| `date_issued` | `:date_issued` | `:date` | Tanggal pengesahan |

#### Mandatory — Relational Tables

| Field | Table | Notes |
|-------|-------|-------|
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |
| `partner_supervisor` | `item_advisors` | `advisor_role: :industry` — Pembimbing dari mitra (nama + jabatan) |
| `team_members` | `item_team_members` | Semua anggota tim (nama + NIM + program studi + peran) |

#### Optional — Columns on `items`

| Field | Ash Attribute | Type | Notes |
|-------|--------------|------|-------|
| `mbkm_scheme` | `:mbkm_scheme` | `:atom` | `one_of: [:magang_industri, :kkn_tematik, :proyek_kemanusiaan, :wirausaha, :penelitian, :asistensi_mengajar, :pertukaran]` |
| `project_budget` | `:project_budget` | `:string` | Anggaran proyek |
| `funding_source` | `:funding_source` | `:atom` | `one_of: [:mandiri, :hibah, :sponsor, :mitra]` |

#### Optional — Relational / Extras

| Field | Table | Notes |
|-------|-------|-------|
| `sdg_goals` | `item_metadata_extras` | `key: "local.subject.sdg"` — multi-value: one row per SDG number |
| `deliverable_list` | `item_metadata_extras` | `key: "local.description.deliverable"` — multi-value |
| `cross_disciplinary_fields` | `item_metadata_extras` | `key: "local.subject.discipline"` — multi-value |
| `impact_achieved` | `item_metadata_extras` | `key: "local.description.impactachieved"` |

#### Supplementary — `item_metadata_extras`

| Field | Key | Notes |
|-------|-----|-------|
| `student_reflection` | `local.description.reflection` | Refleksi pembelajaran (required by some MBKM schemes) |
| `knowledge_transfer_plan` | `local.description.ktplan` | Rencana keberlanjutan |
| `press_coverage` | `local.relation.media` | Multi-value: one row per news link |
| `incubation_status` | `local.description.incubation` | Boolean |
| `community_testimonial` | `local.description.testimonial` | Testimoni dari mitra / komunitas |

### 13.2 File Fields

#### Mandatory

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_cover` | `THUMBNAIL` | JPG / PNG | `:open` | Cover laporan / foto tim dengan mitra |
| `file_abstract` | `ORIGINAL` | PDF | `:inherit` | Ringkasan eksekutif proyek |
| `file_approval_letter` | `ADMINISTRATIVE` | PDF | `:restricted` | Lembar pengesahan dari dosen + mitra |
| `file_final_report` | `ORIGINAL` | PDF | `:inherit` | Laporan akhir capstone project lengkap |
| `file_partner_endorsement` | `ADMINISTRATIVE` | PDF | `:restricted` | Surat keterangan / endorsement dari institusi mitra |

#### Optional

| Field Key | Bundle | Format | `access_level` | Notes |
|-----------|--------|--------|----------------|-------|
| `file_project_charter` | `SUPPLEMENTAL` | PDF | `:inherit` | Project charter / project brief awal |
| `file_deliverable_evidence` | `MEDIA` | PDF / JPG / ZIP | `:inherit` | Bukti deliverable: foto, screenshot, sertifikat |
| `file_prototype_demo` | `MEDIA` | MP4 / ZIP / URL | `:inherit` | Demo produk / prototipe |
| `file_community_testimonial` | `SUPPLEMENTAL` | PDF / MP4 | `:inherit` | Testimoni dari mitra / komunitas |
| `file_presentation` | `SUPPLEMENTAL` | PDF / PPTX | `:inherit` | Slide presentasi akhir |
| `file_mbkm_logbook` | `ADMINISTRATIVE` | PDF | `:restricted` | Logbook kegiatan MBKM |
| `file_student_reflection` | `SUPPLEMENTAL` | PDF | `:inherit` | Refleksi pembelajaran mahasiswa |
| `file_press_documentation` | `SUPPLEMENTAL` | PDF / JPG | `:inherit` | Kliping berita / liputan media |
| `file_source_code` | `SOURCE` | ZIP | `:inherit` | Source code (if project produces software) |
| `file_technical_report` | `SUPPLEMENTAL` | PDF | `:inherit` | Laporan teknis (if engineering/technology involved) |
| `file_financial_report` | `ADMINISTRATIVE` | PDF | `:restricted` | Laporan keuangan proyek |

---

## 14. Schema Placement Guide for Ash

### 14.1 Add These Attributes to the `Item` Resource

Copy all of the following into the `attributes do ... end` block of the `Item` Ash resource. All are `allow_nil?: true` unless marked.

```elixir
# ── Type-Specific Scalar Fields ──────────────────────────────────────────────

# Shared across multiple types
attribute :approval_date,          :date
attribute :research_location,      :string
attribute :research_period,        :string
attribute :funding_source,         :atom,
  constraints: [one_of: [:mandiri, :hibah, :sponsor, :mitra, :other]]
attribute :thesis_type_detail,     :atom,
  constraints: [one_of: [:kuantitatif, :kualitatif, :mixed_methods, :rnd, :ptk]]
attribute :subject_classification, :string
attribute :originality_statement,  :boolean, default: false
attribute :institution,            :string

# Hukum / Legal
attribute :legal_subject_matter,   :atom,
  constraints: [one_of: [:pidana, :perdata, :tata_negara, :internasional,
                          :bisnis, :adat, :agraria, :lingkungan]]
attribute :case_reference,         :string
attribute :court_level,            :atom,
  constraints: [one_of: [:pn, :pt, :ma, :mk, :ptun, :arbitrase, :bani, :icc]]
attribute :legal_issue,            :string
attribute :jurisdiction,           :atom,
  constraints: [one_of: [:indonesia, :internasional, :komparatif]]
attribute :legal_analysis_method,  :atom,
  constraints: [one_of: [:normatif, :empiris, :komparatif, :socio_legal]]

# Studi Kasus
attribute :case_study_type,        :atom,
  constraints: [one_of: [:bisnis, :klinis, :hukum, :psikologi, :pendidikan, :teknik]]
attribute :case_subject,           :string
attribute :case_period,            :string
attribute :case_location,          :string
attribute :analysis_framework,     :string
attribute :subject_anonymized,     :boolean, default: false
attribute :informed_consent,       :boolean, default: false
attribute :ethics_approval_number, :string
attribute :industry_partner,       :string
attribute :data_collection_method, :atom,
  constraints: [one_of: [:wawancara, :observasi, :dokumen_sekunder, :mix]]

# Laporan Proyek
attribute :project_title,          :string
attribute :project_type,           :atom,
  constraints: [one_of: [:desain, :konstruksi, :implementasi_software,
                          :manufaktur, :sistem, :perencanaan_wilayah,
                          :product, :service, :policy, :research, :community]]
attribute :project_client,         :string
attribute :project_period,         :string
attribute :project_location,       :string
attribute :project_deliverable,    :string
attribute :team_role,              :atom,
  constraints: [one_of: [:ketua, :anggota, :pic_teknis]]
attribute :project_budget,         :string
attribute :patent_pending,         :boolean, default: false

# Karya Kreatif
attribute :creative_work_type,     :atom,
  constraints: [one_of: [:novel, :antologi_puisi, :film_pendek, :komposisi_musik,
                          :lukisan, :desain_produk, :animasi, :game, :arsitektur, :kriya]]
attribute :medium_material,        :string
attribute :dimensions_duration,    :string
attribute :creation_period,        :string
attribute :artistic_statement,     :string
attribute :exhibition_performance, :string
attribute :exhibition_date,        :date
attribute :exhibition_venue,       :string
attribute :copyright_type,         :atom,
  constraints: [one_of: [:all_rights_reserved, :cc_by, :cc_by_sa, :cc_by_nc, :cc_by_nc_sa]]
attribute :collection_owner,       :string

# Karya Teknologi
attribute :technology_type,        :atom,
  constraints: [one_of: [:aplikasi_mobile, :web_app, :embedded_system, :perangkat_keras,
                          :dataset, :model_ai_ml, :algoritma, :inovasi_proses]]
attribute :problem_solved,         :string
attribute :target_user,            :string
attribute :implementation_status,  :atom,
  constraints: [one_of: [:prototipe, :mvp, :deployed, :published]]
attribute :testing_method,         :atom,
  constraints: [one_of: [:black_box, :white_box, :user_testing, :benchmark, :usability]]
attribute :license_type,           :atom,
  constraints: [one_of: [:mit, :apache_2, :gpl, :bsd, :proprietary]]
attribute :patent_status,          :atom,
  constraints: [one_of: [:tidak_ada, :dalam_proses, :granted]]
attribute :hki_number,             :string
attribute :industry_tested_at,     :string

# Jurnal Nasional (Type 7)
attribute :journal_name,           :string
attribute :sinta_id,               :string
attribute :sinta_accreditation,    :atom,
  constraints: [one_of: [:s1, :s2, :s3, :s4, :s5, :s6]]
attribute :issn_print,             :string
attribute :issn_online,            :string
attribute :volume,                 :string
attribute :issue,                  :string
attribute :page_start,             :integer
attribute :page_end,               :integer
attribute :doi,                    :string
attribute :publisher,              :string
attribute :corresponding_author,   :string
attribute :garuda_id,              :string
attribute :crossref_registered,    :boolean, default: false
attribute :peer_review_type,       :atom,
  constraints: [one_of: [:single_blind, :double_blind, :open_review]]
attribute :submission_date,        :date
attribute :acceptance_date,        :date
attribute :article_type,           :atom,
  constraints: [one_of: [:research_article, :review, :short_communication, :letter]]

# Jurnal Internasional (Type 8, extends Type 7)
attribute :scopus_id,              :string
attribute :wos_id,                 :string
attribute :sjr_score,              :decimal
attribute :impact_factor,          :decimal
attribute :quartile,               :atom,
  constraints: [one_of: [:q1, :q2, :q3, :q4]]
attribute :subject_area,           :string
attribute :indexed_in,             :atom,
  constraints: [one_of: [:scopus, :wos, :both]]
attribute :altmetric_score,        :integer
attribute :special_issue,          :string
attribute :conference_origin,      :string
attribute :open_access_apc,        :string

# Prosiding (Type 9)
attribute :conference_name,        :string
attribute :conference_acronym,     :string
attribute :conference_date,        :date
attribute :conference_location,    :string
attribute :conference_type,        :atom,
  constraints: [one_of: [:onsite, :online, :hybrid]]
attribute :proceeding_publisher,   :string
attribute :proceeding_series,      :string
attribute :isbn_proceeding,        :string
attribute :issn_proceeding,        :string
attribute :presentation_type,      :atom,
  constraints: [one_of: [:oral, :poster, :keynote, :workshop_paper]]
attribute :acceptance_rate,        :string
attribute :presentation_date,      :date
attribute :session_name,           :string
attribute :best_paper_award,       :string

# Capstone (Type 10)
attribute :capstone_theme,         :string
attribute :team_lead,              :string
attribute :partner_institution,    :string
attribute :problem_statement,      :string
attribute :solution_description,   :string
attribute :impact_target,          :string
attribute :duration_semester,      :string
attribute :mbkm_scheme,            :atom,
  constraints: [one_of: [:magang_industri, :kkn_tematik, :proyek_kemanusiaan,
                          :wirausaha, :penelitian, :asistensi_mengajar, :pertukaran]]
```

### 14.2 Child Relational Tables

These are separate Ash resources each with their own `domain: InstitutionalRepository.Repository`.

| Table | Ash Resource | Key Attributes | Notes |
|-------|-------------|----------------|-------|
| `item_keywords` | `ItemKeyword` | `keyword`, `language` (`:id`/`:en`) | 3–5 per language |
| `item_authors` | `ItemAuthor` | `author_name`, `author_email`, `author_affiliation`, `orcid_id`, `sequence` | Co-authors + all international co-authors |
| `item_advisors` | `ItemAdvisor` | `advisor_name`, `advisor_role`, `advisor_nip`, `sequence` | Roles: `:main_advisor`, `:co_advisor`, `:external`, `:industry`, `:law_clinic`, `:curator`, `:promotor` |
| `item_examiners` | `ItemExaminer` | `examiner_name`, `examiner_nip`, `sequence` | Penguji sidang — **new resource** not in original doc |
| `item_team_members` | `ItemTeamMember` | `member_name`, `member_nim`, `program_study`, `role` | Capstone / project report teams — **new resource** |
| `item_metadata_extras` | `ItemMetadata` | `field_schema`, `field_element`, `field_qualifier`, `field_value`, `language` | EAV for supplementary fields |

### 14.3 `ItemExaminer` Resource (New — Add to Codebase)

```elixir
defmodule InstitutionalRepository.Repository.ItemExaminer do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_examiners"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :examiner_name, :string, allow_nil?: false, public?: true
    attribute :examiner_nip,  :string, public?: true
    attribute :sequence,      :integer, default: 1, public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]
    create :create do
      accept [:examiner_name, :examiner_nip, :sequence, :item_id]
      validate present(:examiner_name)
    end
    create :import do
      accept [:examiner_name, :examiner_nip, :sequence, :item_id]
    end
  end
end
```

### 14.4 `ItemTeamMember` Resource (New — Add to Codebase)

```elixir
defmodule InstitutionalRepository.Repository.ItemTeamMember do
  use Ash.Resource,
    domain: InstitutionalRepository.Repository,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_team_members"
    repo InstitutionalRepository.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :member_name,    :string, allow_nil?: false, public?: true
    attribute :member_nim,     :string, public?: true
    attribute :program_study,  :string, public?: true
    attribute :role,           :string, public?: true  # free text: Ketua, Anggota, PIC Teknis, dll
    attribute :sequence,       :integer, default: 1, public?: true
    timestamps()
  end

  relationships do
    belongs_to :item, InstitutionalRepository.Repository.Item,
      allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]
    create :create do
      accept [:member_name, :member_nim, :program_study, :role, :sequence, :item_id]
      validate present(:member_name)
    end
    create :import do
      accept [:member_name, :member_nim, :program_study, :role, :sequence, :item_id]
    end
  end
end
```

Also add these two resources to the `Repository` domain:

```elixir
# In lib/institutional_repository/repository.ex
resources do
  resource InstitutionalRepository.Repository.Community
  resource InstitutionalRepository.Repository.Collection
  resource InstitutionalRepository.Repository.Item
  resource InstitutionalRepository.Repository.ItemKeyword
  resource InstitutionalRepository.Repository.ItemAuthor
  resource InstitutionalRepository.Repository.ItemAdvisor
  resource InstitutionalRepository.Repository.ItemExaminer   # ← add
  resource InstitutionalRepository.Repository.ItemTeamMember # ← add
  resource InstitutionalRepository.Repository.ItemMetadata
end
```

And add relationships to the `Item` resource:

```elixir
# In Item resource relationships block:
has_many :item_examiners,    InstitutionalRepository.Repository.ItemExaminer,    public?: true
has_many :item_team_members, InstitutionalRepository.Repository.ItemTeamMember,  public?: true
```

---

## 15. UI Field Visibility Matrix

Your submission wizard and admin edit form should show/hide field groups based on `item_type`. Use this matrix to drive your LiveView assigns.

| Field Group | 1 Skripsi | 2 Hukum | 3 Studi Kasus | 4 Proyek | 5 Kreatif | 6 Teknologi | 7 Jurnal Nas | 8 Jurnal Int | 9 Prosiding | 10 Capstone |
|-------------|:---------:|:-------:|:-------------:|:--------:|:---------:|:-----------:|:------------:|:------------:|:-----------:|:-----------:|
| `degree_level` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | ✅ |
| Advisor / Pembimbing | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Examiners / Penguji | ✅ | ✅ | ✅ | — | — | — | — | — | — | — |
| `date_issued` (sidang) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | ✅ |
| Legal fields | — | ✅ | — | — | — | — | — | — | — | — |
| Ethics / Informed Consent | — | — | ✅ | — | — | — | — | — | — | — |
| Project client / period | — | — | — | ✅ | — | — | — | — | — | ✅ |
| Team members | — | — | — | ✅ | ✅ | ✅ | — | — | — | ✅ |
| Creative work fields | — | — | — | — | ✅ | — | — | — | — | — |
| Technology stack / artifact | — | — | — | — | — | ✅ | — | — | — | — |
| Journal / DOI / ISSN | — | — | — | — | — | — | ✅ | ✅ | ✅ | — |
| Sinta accreditation | — | — | — | — | — | — | ✅ | — | — | — |
| Scopus / WoS / Quartile | — | — | — | — | — | — | — | ✅ | — | — |
| Conference details | — | — | — | — | — | — | — | — | ✅ | — |
| MBKM scheme / SDG goals | — | — | — | — | — | — | — | — | — | ✅ |

Implement this in LiveView as a helper:

```elixir
# lib/institutional_repository_web/live/helpers/field_visibility.ex
defmodule InstitutionalRepositoryWeb.Live.Helpers.FieldVisibility do
  @legal_types        [:memorandum_hukum]
  @ethics_types       [:studi_kasus]
  @project_types      [:laporan_proyek, :capstone]
  @creative_types     [:karya_kreatif]
  @tech_types         [:karya_teknologi]
  @journal_types      [:jurnal_nasional, :jurnal_internasional]
  @intl_journal_types [:jurnal_internasional]
  @conf_types         [:prosiding]
  @capstone_types     [:capstone]
  @has_examiners      [:skripsi, :memorandum_hukum, :studi_kasus]

  def show_field_group?(item_type, :legal),           do: item_type in @legal_types
  def show_field_group?(item_type, :ethics),          do: item_type in @ethics_types
  def show_field_group?(item_type, :project_client),  do: item_type in @project_types
  def show_field_group?(item_type, :team_members),    do: item_type in @project_types ++ @creative_types ++ @tech_types
  def show_field_group?(item_type, :creative),        do: item_type in @creative_types
  def show_field_group?(item_type, :technology),      do: item_type in @tech_types
  def show_field_group?(item_type, :journal),         do: item_type in @journal_types
  def show_field_group?(item_type, :scopus_wos),      do: item_type in @intl_journal_types
  def show_field_group?(item_type, :conference),      do: item_type in @conf_types
  def show_field_group?(item_type, :mbkm),            do: item_type in @capstone_types
  def show_field_group?(item_type, :examiners),       do: item_type in @has_examiners
  def show_field_group?(_item_type, _group),          do: false
end
```

---

## 16. Validation Rules per Type

Wire these into the Ash `Item` resource's `:create` and `:update` actions using `validate` blocks and `change` hooks. These run only when the relevant `item_type` is set.

```elixir
# In Item resource create action:
create :create do
  accept [...]

  # Universal mandatory
  validate present(:title)
  validate present(:title_alt)
  validate present(:abstract)
  validate present(:abstract_alt)
  validate present(:collection_id)

  # Type-specific: run a custom validation module
  validate InstitutionalRepository.Repository.Item.Validations.TypeSpecificRequired
end
```

```elixir
# lib/institutional_repository/repository/item/validations/type_specific_required.ex
defmodule InstitutionalRepository.Repository.Item.Validations.TypeSpecificRequired do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    item_type = Ash.Changeset.get_attribute(changeset, :item_type)
    run_type_rules(changeset, item_type)
  end

  # Skripsi / Tesis / Disertasi
  defp run_type_rules(changeset, :skripsi),
    do: require_fields(changeset, [:degree_level, :date_issued])

  # Legal Memorandum
  defp run_type_rules(changeset, :memorandum_hukum),
    do: require_fields(changeset, [:degree_level, :legal_subject_matter,
                                   :case_reference, :court_level, :legal_issue, :date_issued])

  # Case Study
  defp run_type_rules(changeset, :studi_kasus),
    do: require_fields(changeset, [:degree_level, :case_study_type, :case_subject,
                                   :case_period, :case_location, :analysis_framework, :date_issued])

  # Project Report
  defp run_type_rules(changeset, :laporan_proyek),
    do: require_fields(changeset, [:degree_level, :project_title, :project_type,
                                   :project_client, :project_period, :project_location,
                                   :project_deliverable, :date_issued])

  # Creative Work
  defp run_type_rules(changeset, :karya_kreatif),
    do: require_fields(changeset, [:degree_level, :creative_work_type, :medium_material,
                                   :dimensions_duration, :creation_period,
                                   :artistic_statement, :date_issued])

  # Technological Work
  defp run_type_rules(changeset, :karya_teknologi),
    do: require_fields(changeset, [:degree_level, :technology_type, :problem_solved,
                                   :target_user, :implementation_status,
                                   :testing_method, :date_issued])

  # National Journal
  defp run_type_rules(changeset, :jurnal_nasional),
    do: require_fields(changeset, [:journal_name, :sinta_id, :sinta_accreditation,
                                   :issn_print, :volume, :issue,
                                   :page_start, :page_end, :doi, :date_issued])

  # International Journal
  defp run_type_rules(changeset, :jurnal_internasional),
    do: require_fields(changeset, [:journal_name, :doi, :date_issued,
                                   :scopus_id, :quartile, :indexed_in])

  # Conference Proceedings
  defp run_type_rules(changeset, :prosiding),
    do: require_fields(changeset, [:conference_name, :conference_acronym, :conference_date,
                                   :conference_location, :conference_type,
                                   :proceeding_publisher, :doi, :presentation_type,
                                   :page_start, :page_end, :date_issued])

  # Capstone
  defp run_type_rules(changeset, :capstone),
    do: require_fields(changeset, [:degree_level, :capstone_theme, :project_type,
                                   :team_lead, :partner_institution, :problem_statement,
                                   :solution_description, :impact_target,
                                   :duration_semester, :date_issued])

  # No additional rules for unknown type
  defp run_type_rules(changeset, _), do: :ok

  defp require_fields(changeset, fields) do
    Enum.find_value(fields, :ok, fn field ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil -> {:error, field: field, message: "is required for #{Ash.Changeset.get_attribute(changeset, :item_type)}"}
        _   -> nil
      end
    end)
  end
end
```

---

## 17. `item_metadata_extras` Key Reference (All Types)

Complete list of `schema.element.qualifier` keys used across all types for the `ItemMetadata` resource.

| Key | Used By Type(s) | Notes |
|-----|----------------|-------|
| `dc.identifier.isbn` | Karya Kreatif | ISBN if published as book |
| `dc.identifier.doi` | Karya Teknologi | DOI from Zenodo |
| `dc.contributor.orcid` | Skripsi, Jurnal Int | ORCID — multi-value |
| `dc.relation.uri` | Skripsi, Jurnal Nas, Prosiding | Related URLs |
| `dc.description.degree` | Skripsi | Previous degree |
| `dc.subject.icd` | Studi Kasus (medical) | ICD-10/11 code |
| `local.identifier.scopusauthor` | Skripsi (S3) | Scopus Author ID |
| `local.identifier.hki` | Kreatif, Teknologi | Nomor HKI / DJKI |
| `local.identifier.deploymenturl` | Teknologi, Proyek | Live URL |
| `local.identifier.dataseturl` | Teknologi | Dataset URL |
| `local.identifier.apidocs` | Teknologi | API docs URL |
| `local.identifier.pubmed` | Jurnal Int (medical) | PubMed ID |
| `local.identifier.lens` | Jurnal Int | Lens.org ID |
| `local.identifier.presentationurl` | Prosiding | URL rekaman presentasi |
| `local.identifier.kbli` | Studi Kasus (bisnis) | KBLI code |
| `local.description.dedication` | Skripsi | Halaman persembahan |
| `local.description.acknowledgement` | Skripsi | Kata pengantar |
| `local.description.verdict` | Hukum | Summary of verdict |
| `local.description.outcome` | Studi Kasus | Case outcome |
| `local.description.companysize` | Studi Kasus | UMKM/Menengah/Besar |
| `local.description.techstack` | Teknologi, Proyek | Multi-value |
| `local.description.platform` | Teknologi | Multi-value OS/platform |
| `local.description.metrics` | Teknologi | Performance metrics |
| `local.description.testcases` | Teknologi | Test case count |
| `local.description.modelarch` | Teknologi | ML model architecture |
| `local.description.trainingdata` | Teknologi | Training dataset |
| `local.description.hardwarespec` | Teknologi | Hardware minimum spec |
| `local.description.energy` | Teknologi | Energy consumption |
| `local.description.scale` | Proyek | pilot/production/prototype |
| `local.description.sustainability` | Proyek | Carbon footprint |
| `local.description.citationcount` | Jurnal Nas | Total citation count |
| `local.description.citationscopus` | Jurnal Int | Scopus citation count |
| `local.description.citationwos` | Jurnal Int | WoS citation count |
| `local.description.mendeley` | Jurnal Int | Mendeley readers |
| `local.description.retraction` | Jurnal Int | Retraction status |
| `local.description.funding` | Jurnal Nas/Int | Funding statement |
| `local.description.sponsor` | Prosiding | Sponsor konferensi |
| `local.description.reflection` | Capstone | Student reflection |
| `local.description.ktplan` | Capstone | Knowledge transfer plan |
| `local.description.impactachieved` | Capstone | Actual impact achieved |
| `local.description.deliverable` | Capstone | Multi-value deliverable list |
| `local.description.incubation` | Capstone | Incubation status |
| `local.description.testimonial` | Capstone | Community testimonial |
| `local.relation.legislation` | Hukum | Multi-value: regulations |
| `local.relation.case` | Hukum | Multi-value: related cases |
| `local.relation.standard` | Proyek | Multi-value: SNI/ISO codes |
| `local.relation.media` | Capstone | Multi-value: press coverage |
| `local.rights.conflict` | Jurnal | Conflict of interest |
| `local.rights.oastatus` | Jurnal | gold/green/closed |
| `local.rights.nda` | Studi Kasus | NDA status |
| `local.subject.acm` | Teknologi | ACM CCS code |
| `local.subject.iswc` | Kreatif | Musical work code |
| `local.subject.isrc` | Kreatif | Recording code |
| `local.subject.indexed` | Prosiding | Multi-value: Scopus/IEEE/ACM |
| `local.subject.corerank` | Prosiding | CORE ranking |
| `local.subject.sdg` | Capstone | Multi-value: SDG 1–17 |
| `local.subject.discipline` | Capstone | Multi-value: cross-disciplinary |
| `local.description.clienttype` | Hukum | individu/korporasi/negara |
| `local.description.recommendation` | Hukum | Legal reform recommendation |
| `local.description.reception` | Kreatif | Audience reception |
| `local.description.inspiration` | Kreatif | Inspiration source |
| `local.description.colorpalette` | Kreatif | Color palette |
| `local.description.preprint` | Jurnal | Preprint URL |
| `local.description.dataurl` | Jurnal | Data availability URL |
