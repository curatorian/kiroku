# Metadata & File Fields by Tugas Akhir Type

## Indonesian Institutional Repository — Complete Field & Bitstream Reference

### Covers All 13 Item Types · Ecto Schema Mapping · Bitstream Storage Rules

---

## 0. How to Read This Document

This document is the single source of truth for **what data to collect** and **what files to store** for each of the 13 item types supported by the repository. It is organized for direct use by a coding agent building Ecto schemas and Phoenix context functions.

For every section, field tiers are defined as:

| Tier              | Meaning in Ecto                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------- |
| **Mandatory**     | `validate_required/2` in the changeset, or `NOT NULL` constraint in the migration                                   |
| **Optional**      | No `validate_required` — field may be `nil`                                                                         |
| **Supplementary** | `allow_nil: true`, stored in `item_metadata_extras` table as `{field_schema}.{field_element}.{field_qualifier}` row |

Storage location is one of three places:

| Location                          | When to Use                                                                                                                                  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Column in `items` table**       | Single-value, flat scalar field — goes in the `Item` Ecto schema                                                                             |
| **Row in a child table**          | Multi-value or repeating fields — goes in its own Ecto schema (`ItemAuthor`, `ItemAdvisor`, `ItemExaminer`, `ItemTeamMember`, `ItemKeyword`) |
| **Row in `item_metadata_extras`** | Rare, supplementary, or type-specific fields not worth a dedicated column — stored as `{field_schema}.{field_element}.{field_qualifier}`     |

File storage: every file becomes **one row** in the `bitstreams` table. Section 2 defines the bundle system and access defaults. Sections 3–12 specify exactly which files each type requires.

---

## 1. Item Type Enum Values

The `item_type` field on the `Item` schema uses `Ecto.Enum` with these values.

> **Design decision:** Thesis-like works are split into four distinct types
> (`skripsi`, `tesis`, `disertasi`, `tugas_akhir`) instead of a single
> `skripsi` type with `degree_level` distinguishing them. This lets end users
> identify the exact work type from the `item_type` value alone. `degree_level`
> is **kept** as an independent field for finer-grained classification and reporting.

```elixir
# In Item Ecto schema:
field :item_type, Ecto.Enum,
  values: [
    :skripsi,              # 1 — S1 academic thesis
    :tesis,                # 2 — S2 academic thesis (magister)
    :disertasi,            # 3 — S3 academic thesis (doctoral)
    :tugas_akhir,          # 4 — Diploma / general final project (D3/D4/vocation)
    :memorandum_hukum,     # 5 — Legal memorandum (FH)
    :studi_kasus,          # 6 — Case study (Bisnis/Kedokteran/Psikologi/Hukum)
    :laporan_proyek,       # 7 — Project report (Teknik/Vokasi/Arsitektur)
    :karya_kreatif,        # 8 — Creative work (Seni/Desain/Sastra/Musik/Film)
    :karya_teknologi,      # 9 — Technological work (Informatika/Teknik Terapan)
    :jurnal_nasional,      # 10 — Sinta-accredited national journal article
    :jurnal_internasional, # 11 — Scopus/WoS international journal article
    :prosiding,            # 12 — International conference proceedings
    :capstone,             # 13 — Capstone / MBKM project
  ],
  default: :skripsi
```

---

## 2. Bundle System & Bitstream Access Defaults

Every file uploaded becomes one `Bitstream` row. The `bundle_name` field groups files by purpose.

### 2.1 Bundle Name Enum

```elixir
# In Bitstream Ecto schema:
field :bundle_name, Ecto.Enum,
  values: [
    :ORIGINAL,        # Primary documents (full text, published article, main work)
    :THUMBNAIL,       # Cover image — always public
    :CHAPTER,         # Per-chapter PDFs (Skripsi/Tesis)
    :SUPPLEMENTAL,    # Supporting docs (daftar isi, lampiran, bibliography)
    :ADMINISTRATIVE,  # Restricted internal docs (pengesahan, acceptance letter)
    :LICENSE,         # Originality statements, license agreements
    :MEDIA,           # Audio, video, image files (Karya Kreatif/Teknologi)
    :SOURCE,          # Source code archives, datasets, technical drawings
  ],
  default: :ORIGINAL
```

### 2.2 Default Access Level per Bundle

This default is applied in the `Bitstream.changeset/2` and in the import task when no override is specified.

| Bundle           | Default `access_level` | Effective Access                                |
| ---------------- | ---------------------- | ----------------------------------------------- |
| `ORIGINAL`       | `:inherit`             | Follows parent `item.access_level`              |
| `THUMBNAIL`      | `:open`                | **Always public** — never restrict cover images |
| `CHAPTER`        | `:inherit`             | Follows parent `item.access_level`              |
| `SUPPLEMENTAL`   | `:inherit`             | Follows parent `item.access_level`              |
| `ADMINISTRATIVE` | `:restricted`          | **Staff / Admin only** — never public           |
| `LICENSE`        | `:restricted`          | Staff / Admin only                              |
| `MEDIA`          | `:inherit`             | Follows parent `item.access_level`              |
| `SOURCE`         | `:inherit`             | Follows parent `item.access_level`              |

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

| Ecto Field           | Required             | Notes                                                                       |
| -------------------- | -------------------- | --------------------------------------------------------------------------- |
| `filename`           | Yes                  | Original filename as uploaded                                               |
| `bundle_name`        | Yes                  | Atom from the enum above                                                    |
| `sequence`           | Yes                  | Integer order within the bundle (1 = primary/first)                         |
| `description`        | Recommended          | Human-readable label, e.g. `"Full Thesis PDF"`, `"Chapter 1 - Pendahuluan"` |
| `storage_type`       | Yes                  | `:url` / `:s3` / `:local`                                                   |
| `storage_url`        | If `:url`            | Full external URL (e.g. existing S3 link from legacy data)                  |
| `storage_path`       | If `:s3` or `:local` | S3 key or filesystem path                                                   |
| `storage_bucket`     | If `:s3`             | S3 bucket name                                                              |
| `mime_type`          | Recommended          | `application/pdf`, `image/jpeg`, `video/mp4`, etc.                          |
| `access_level`       | Yes                  | Use bundle default from table above unless overriding                       |
| `embargo_open_date`  | If embargoed         | Date from which access opens — `nil` = no embargo                           |
| `embargo_close_date` | If time-limited      | Date after which access closes — `nil` = no close embargo                   |
| `item_id`            | Yes                  | FK to parent `Item`                                                         |

---

## 3. Universal Fields & Files (All 13 Types)

These fields and files apply to **every item regardless of type**. They are defined as columns in the `Item` schema and as mandatory bitstreams in the `Bitstream` schema.

### 3.1 Universal Metadata Fields

All mandatory. Map directly to `Item` schema fields.

| Field              | Ecto Field          | Type        | Constraint                                                            | Notes                                                            |
| ------------------ | ------------------- | ----------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `title`            | `:title`            | `:string`   | `validate_required`                                                   | Judul dalam bahasa Indonesia                                     |
| `title_alt`        | `:title_alt`        | `:string`   | `validate_required`                                                   | Judul bahasa Inggris — required by Permenristekdikti No. 44/2015 |
| `language`         | `:language`         | `Ecto.Enum` | `values: [:id, :en]`                                                  | ISO 639-1. Default `:id`                                         |
| `abstract`         | `:abstract`         | `:string`   | `validate_required`                                                   | Abstrak bahasa Indonesia                                         |
| `abstract_alt`     | `:abstract_alt`     | `:string`   | `validate_required`                                                   | Abstrak bahasa Inggris                                           |
| `author_name`      | `item_authors` row  | relational  | `validate_required`                                                   | Goes into `ItemAuthor` table, not a column on `items`            |
| `student_id`       | `:student_id`       | `:string`   | required for thesis types                                             | NIM / NPM                                                        |
| `program_study`    | `:program_study`    | `:string`   | —                                                                     | Program Studi                                                    |
| `faculty`          | `:faculty`          | `:string`   | —                                                                     | Fakultas                                                         |
| `institution`      | `:institution`      | `:string`   | default: university name                                              | Nama institusi                                                   |
| `date_submitted`   | `:date_submitted`   | `:date`     | —                                                                     | Tanggal pengumpulan ke repositori                                |
| `publication_year` | `:publication_year` | `:integer`  | —                                                                     | Tahun terbit / sidang                                            |
| `access_level`     | `:access_level`     | `Ecto.Enum` | `values: [:open, :restricted, :closed]`                               | Default `:open`                                                  |
| `status`           | `:status`           | `Ecto.Enum` | `values: [:draft, :submitted, :under_review, :published, :withdrawn]` | Default `:draft`                                                 |
| `item_type`        | `:item_type`        | `Ecto.Enum` | `values: [13 types]`                                                  | Drives field visibility in the UI                                |

> **Keywords**: `keywords` and `keywords_alt` are **not** columns on `items`. Each keyword becomes one row in `item_keywords` with a `language` field (`:id` or `:en`). Minimum 3, maximum 5 keywords per language.

> **`institution`**: Set a default value in the context function's `create_item/1` if not provided.

### 3.2 Universal Mandatory Files

These 4 files are required for every single item regardless of type.

| Field Key                    | Bundle           | Format    | `access_level`         | Sequence | Description                                                                       |
| ---------------------------- | ---------------- | --------- | ---------------------- | -------- | --------------------------------------------------------------------------------- |
| `file_cover`                 | `THUMBNAIL`      | JPG / PNG | `:open` (always)       | 1        | Halaman sampul / cover page. Shown as thumbnail in search results. Never embargo. |
| `file_abstract`              | `ORIGINAL`       | PDF       | `:inherit`             | 1        | Halaman abstrak (bilingual). Sequence 1 = not embargoed even when full text is.   |
| `file_approval_letter`       | `ADMINISTRATIVE` | PDF       | `:restricted` (always) | 1        | Lembar pengesahan yang sudah ditandatangani. Never public.                        |
| `file_originality_statement` | `LICENSE`        | PDF       | `:restricted` (always) | 1        | Pernyataan keaslian / anti-plagiarisme bermaterai.                                |

---

## 4. Types 1–4 — Skripsi / Tesis / Disertasi / Tugas Akhir

Standard academic theses and final projects. They share the same fields and files;
`item_type` (`skripsi` / `tesis` / `disertasi` / `tugas_akhir`) plus
`degree_level` distinguish them. Use the most specific type available — e.g. an S2
thesis is `item_type: :tesis`, `degree_level: :s2`.

### 4.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field           | Ecto Field       | Type        | Notes                                    |
| --------------- | ---------------- | ----------- | ---------------------------------------- |
| `degree_level`  | `:degree_level`  | `Ecto.Enum` | `values: [:d3, :d4, :s1_terapan, :s1, :s2, :s3]` |
| `department`    | `:department`    | `:string`   | Departemen / Jurusan                     |
| `date_issued`   | `:date_issued`   | `:date`     | Tanggal sidang / ujian                   |
| `approval_date` | `:approval_date` | `:date`     | Tanggal lembar pengesahan ditandatangani |

#### Mandatory — Relational Tables

| Field          | Table            | Ecto Schema    | Notes                                            |
| -------------- | ---------------- | -------------- | ------------------------------------------------ |
| `main_advisor` | `item_advisors`  | `ItemAdvisor`  | `advisor_role: :main_advisor`                    |
| `co_advisor`   | `item_advisors`  | `ItemAdvisor`  | `advisor_role: :co_advisor` — required for S2/S3 |
| `examiner_1`   | `item_examiners` | `ItemExaminer` | `sequence: 1`                                    |
| `examiner_2`   | `item_examiners` | `ItemExaminer` | `sequence: 2`                                    |

#### Optional — Columns on `items`

| Field                    | Ecto Field                | Type        | Notes                                                             |
| ------------------------ | ------------------------- | ----------- | ----------------------------------------------------------------- |
| `research_location`      | `:research_location`      | `:string`   | Lokasi penelitian lapangan                                        |
| `research_period`        | `:research_period`        | `:string`   | e.g. "Januari–Maret 2024"                                         |
| `funding_source`         | `:funding_source`         | `:string`   | Sumber pendanaan / hibah                                          |
| `subject_classification` | `:subject_classification` | `:string`   | Nomor DDC / UDC                                                   |
| `originality_statement`  | `:originality_statement`  | `:boolean`  | Pernyataan keaslian (checked)                                     |
| `thesis_type_detail`     | `:thesis_type_detail`     | `Ecto.Enum` | `values: [:kuantitatif, :kualitatif, :mixed_methods, :rnd, :ptk]` |
| `embargo_open_date`      | `:embargo_open_date`      | `:date`     | Tanggal embargo berakhir                                          |

#### Optional — Relational Tables

| Field              | Table            | Notes                                                               |
| ------------------ | ---------------- | ------------------------------------------------------------------- |
| `examiner_3`       | `item_examiners` | `sequence: 3`, if applicable                                        |
| `external_advisor` | `item_advisors`  | `advisor_role: :external` — pembimbing dari industri / lembaga lain |

#### Supplementary — `item_metadata_extras` rows

Store these as `{field_schema}.{field_element}.{field_qualifier}`:

| Field                 | Key                                 | Value                                        |
| --------------------- | ----------------------------------- | -------------------------------------------- |
| `dedication`          | `local.description.dedication`      | Halaman persembahan text                     |
| `acknowledgement`     | `local.description.acknowledgement` | Kata pengantar text                          |
| `related_publication` | `dc.relation.uri`                   | DOI / URL artikel yang terbit dari tesis ini |
| `previous_degree`     | `dc.description.degree`             | Gelar sebelumnya (S2/S3 relevant)            |
| `orcid_id`            | `dc.contributor.orcid`              | ORCID mahasiswa                              |
| `scopus_author_id`    | `local.identifier.scopusauthor`     | Scopus Author ID                             |

### 4.2 File Fields

#### Mandatory

| Field Key                                   | Bundle                 | Format    | `access_level` | Notes                                                                 |
| ------------------------------------------- | ---------------------- | --------- | -------------- | --------------------------------------------------------------------- |
| `file_cover`                                | `THUMBNAIL`            | JPG / PNG | `:open`        | Halaman sampul                                                        |
| `file_abstract`                             | `ORIGINAL`             | PDF       | `:inherit`     | Abstrak — sequence 1, not embargoed                                   |
| `file_approval_letter`                      | `ADMINISTRATIVE`       | PDF       | `:restricted`  | Lembar pengesahan                                                     |
| `file_originality_statement`                | `LICENSE`              | PDF       | `:restricted`  | Pernyataan keaslian bermaterai                                        |
| `file_fulltext` **OR** at least `file_bab1` | `ORIGINAL` / `CHAPTER` | PDF       | `:inherit`     | Full thesis as one PDF OR split by chapter. At least one is required. |

#### Optional

| Field Key                | Bundle           | Format     | `access_level` | Notes                                                             |
| ------------------------ | ---------------- | ---------- | -------------- | ----------------------------------------------------------------- |
| `file_bab1`              | `CHAPTER`        | PDF        | `:inherit`     | Pendahuluan (sequence 1)                                          |
| `file_bab2`              | `CHAPTER`        | PDF        | `:inherit`     | Tinjauan Pustaka (sequence 2)                                     |
| `file_bab3`              | `CHAPTER`        | PDF        | `:inherit`     | Metodologi Penelitian (sequence 3)                                |
| `file_bab4`              | `CHAPTER`        | PDF        | `:inherit`     | Hasil dan Pembahasan (sequence 4)                                 |
| `file_bab5`              | `CHAPTER`        | PDF        | `:inherit`     | Kesimpulan dan Saran (sequence 5)                                 |
| `file_bab6`              | `CHAPTER`        | PDF        | `:inherit`     | Bab 6 jika ada — e.g. implementation + evaluation (sequence 6)    |
| `file_daftar_isi`        | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Daftar isi                                                        |
| `file_pustaka`           | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Daftar pustaka / referensi                                        |
| `file_lampiran`          | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Lampiran (kuesioner, raw data, dll)                               |
| `file_presentation`      | `SUPPLEMENTAL`   | PDF / PPTX | `:inherit`     | Slide presentasi sidang                                           |
| `file_turnitin_report`   | `ADMINISTRATIVE` | PDF        | `:restricted`  | Laporan similarity Turnitin / iThenticate                         |
| `file_ethical_clearance` | `ADMINISTRATIVE` | PDF        | `:restricted`  | **Mandatory for medical/public health** — surat ethical clearance |

#### Supplementary

| Field Key          | Bundle         | Format                 | Notes                              |
| ------------------ | -------------- | ---------------------- | ---------------------------------- |
| `file_raw_data`    | `SUPPLEMENTAL` | XLSX / CSV / SAV / ZIP | Dataset penelitian mentah          |
| `file_instruments` | `SUPPLEMENTAL` | PDF / DOCX             | Kuesioner, panduan wawancara       |
| `file_transcripts` | `SUPPLEMENTAL` | PDF                    | Transkrip wawancara (anonymized)   |
| `file_publication` | `ORIGINAL`     | PDF                    | Artikel yang terbit dari tesis ini |

---

## 5. Type 2 — Memorandum Hukum (Legal Memorandum)

Specific to Fakultas Hukum. Shares base structure with Skripsi but adds legal-specific fields.

### 5.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                  | Ecto Field              | Type        | Notes                                                                                              |
| ---------------------- | ----------------------- | ----------- | -------------------------------------------------------------------------------------------------- |
| `degree_level`         | `:degree_level`         | `Ecto.Enum` | `values: [:s1, :s2]`                                                                               |
| `legal_subject_matter` | `:legal_subject_matter` | `Ecto.Enum` | `values: [:pidana, :perdata, :tata_negara, :internasional, :bisnis, :adat, :agraria, :lingkungan]` |
| `case_reference`       | `:case_reference`       | `:string`   | Nomor perkara / putusan, e.g. `"Putusan MA No. 123/Pid/2022"`                                      |
| `court_level`          | `:court_level`          | `Ecto.Enum` | `values: [:pn, :pt, :ma, :mk, :ptun, :arbitrase, :bani, :icc]`                                     |
| `legal_issue`          | `:legal_issue`          | `:string`   | The legal question being analyzed                                                                  |
| `date_issued`          | `:date_issued`          | `:date`     | Tanggal sidang / pengesahan                                                                        |

#### Mandatory — Relational Tables

| Field                      | Table            | Notes                         |
| -------------------------- | ---------------- | ----------------------------- |
| `main_advisor`             | `item_advisors`  | `advisor_role: :main_advisor` |
| `examiner_1`, `examiner_2` | `item_examiners` | Penguji sidang                |

#### Optional — Columns on `items`

| Field                   | Ecto Field               | Type        | Notes                                                      |
| ----------------------- | ------------------------ | ----------- | ---------------------------------------------------------- |
| `jurisdiction`          | `:jurisdiction`          | `Ecto.Enum` | `values: [:indonesia, :internasional, :komparatif]`        |
| `legal_analysis_method` | `:legal_analysis_method` | `Ecto.Enum` | `values: [:normatif, :empiris, :komparatif, :socio_legal]` |

#### Optional — Relational Tables

| Field                   | Table                  | Notes                                                       |
| ----------------------- | ---------------------- | ----------------------------------------------------------- |
| `related_legislation`   | `item_metadata_extras` | `key: "local.relation.legislation"`, one row per regulation |
| `law_clinic_supervisor` | `item_advisors`        | `advisor_role: :law_clinic`                                 |

#### Supplementary — `item_metadata_extras`

| Field                         | Key                                | Notes                                 |
| ----------------------------- | ---------------------------------- | ------------------------------------- |
| `verdict`                     | `local.description.verdict`        | Summary of verdict in analyzed case   |
| `related_case`                | `local.relation.case`              | Multi-value: one row per related case |
| `legal_reform_recommendation` | `local.description.recommendation` |                                       |
| `client_type`                 | `local.description.clienttype`     | `individu` / `korporasi` / `negara`   |

### 5.2 File Fields

#### Mandatory

| Field Key                    | Bundle           | Format    | `access_level` | Notes                 |
| ---------------------------- | ---------------- | --------- | -------------- | --------------------- |
| `file_cover`                 | `THUMBNAIL`      | JPG / PNG | `:open`        | Halaman sampul        |
| `file_abstract`              | `ORIGINAL`       | PDF       | `:inherit`     | Halaman abstrak       |
| `file_approval_letter`       | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan     |
| `file_originality_statement` | `LICENSE`        | PDF       | `:restricted`  | Pernyataan keaslian   |
| `file_fulltext`              | `ORIGINAL`       | PDF       | `:inherit`     | Full memorandum hukum |

#### Optional

| Field Key                   | Bundle           | Format     | `access_level` | Notes                                           |
| --------------------------- | ---------------- | ---------- | -------------- | ----------------------------------------------- |
| `file_court_decision`       | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Salinan putusan pengadilan yang dikaji          |
| `file_legislation_copies`   | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Salinan peraturan perundangan                   |
| `file_daftar_isi`           | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Daftar isi                                      |
| `file_pustaka`              | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Daftar pustaka                                  |
| `file_lampiran`             | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Lampiran                                        |
| `file_client_authorization` | `ADMINISTRATIVE` | PDF        | `:restricted`  | Surat kuasa dari klien (jika dari klinik hukum) |
| `file_presentation`         | `SUPPLEMENTAL`   | PDF / PPTX | `:inherit`     | Slide presentasi sidang                         |

---

## 6. Type 3 — Studi Kasus (Case Study)

Common in Ekonomi/Bisnis, Kedokteran/Kesehatan, Psikologi, and Hukum. Access restrictions are especially important here due to privacy and ethics requirements.

### 6.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                | Ecto Field            | Type        | Notes                                                                  |
| -------------------- | --------------------- | ----------- | ---------------------------------------------------------------------- |
| `degree_level`       | `:degree_level`       | `Ecto.Enum` | `values: [:s1, :s2, :s3]`                                              |
| `case_study_type`    | `:case_study_type`    | `Ecto.Enum` | `values: [:bisnis, :klinis, :hukum, :psikologi, :pendidikan, :teknik]` |
| `case_subject`       | `:case_subject`       | `:string`   | Subjek/objek kasus — nama org, anonymized patient ID, dll              |
| `case_period`        | `:case_period`        | `:string`   | Periode kasus yang dikaji                                              |
| `case_location`      | `:case_location`      | `:string`   | Lokasi/setting kasus, or `"anonim"`                                    |
| `analysis_framework` | `:analysis_framework` | `:string`   | SWOT, BCG Matrix, DSM-5, dll                                           |
| `date_issued`        | `:date_issued`        | `:date`     | Tanggal sidang / pengesahan                                            |
| `subject_anonymized` | `:subject_anonymized` | `:boolean`  | Default `false`                                                        |
| `informed_consent`   | `:informed_consent`   | `:boolean`  | Default `false`                                                        |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                         |
| -------------- | --------------- | ----------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field                    | Ecto Field                | Type        | Notes                                                               |
| ------------------------ | ------------------------- | ----------- | ------------------------------------------------------------------- |
| `ethics_approval_number` | `:ethics_approval_number` | `:string`   | **CRITICAL for medical/psychology** — Nomor persetujuan Komite Etik |
| `industry_partner`       | `:industry_partner`       | `:string`   | Nama perusahaan (if not anonymized)                                 |
| `data_collection_method` | `:data_collection_method` | `Ecto.Enum` | `values: [:wawancara, :observasi, :dokumen_sekunder, :mix]`         |

#### Optional — Relational Tables

| Field                 | Table           | Notes                                            |
| --------------------- | --------------- | ------------------------------------------------ |
| `industry_supervisor` | `item_advisors` | `advisor_role: :industry` — nama + jabatan mitra |

#### Supplementary — `item_metadata_extras`

| Field           | Key                             | Notes                              |
| --------------- | ------------------------------- | ---------------------------------- |
| `case_outcome`  | `local.description.outcome`     | Hasil / rekomendasi kasus          |
| `sic_kbli_code` | `local.identifier.kbli`         | KBLI code for business cases       |
| `company_size`  | `local.description.companysize` | `umkm` / `menengah` / `besar`      |
| `icd_code`      | `local.subject.icd`             | ICD-10/11 code for medical studies |
| `dsm_code`      | `local.subject.dsm`             | DSM code for psychology studies    |
| `nda_status`    | `local.rights.nda`              | Boolean                            |

### 6.2 File Fields

#### Mandatory

| Field Key                    | Bundle           | Format    | `access_level` | Notes                    |
| ---------------------------- | ---------------- | --------- | -------------- | ------------------------ |
| `file_cover`                 | `THUMBNAIL`      | JPG / PNG | `:open`        | Halaman sampul           |
| `file_abstract`              | `ORIGINAL`       | PDF       | `:inherit`     | Halaman abstrak          |
| `file_approval_letter`       | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan        |
| `file_originality_statement` | `LICENSE`        | PDF       | `:restricted`  | Pernyataan keaslian      |
| `file_fulltext`              | `ORIGINAL`       | PDF       | `:inherit`     | Full case study document |

#### Optional

| Field Key                   | Bundle           | Format     | `access_level` | Notes                                                      |
| --------------------------- | ---------------- | ---------- | -------------- | ---------------------------------------------------------- |
| `file_ethics_approval`      | `ADMINISTRATIVE` | PDF        | `:restricted`  | **Mandatory for medical/psychology** — Surat Komite Etik   |
| `file_informed_consent`     | `ADMINISTRATIVE` | PDF        | `:restricted`  | Informed consent form — always restricted                  |
| `file_interview_transcript` | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Transkrip wawancara — **must be anonymized before upload** |
| `file_observation_notes`    | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Catatan observasi lapangan                                 |
| `file_company_documents`    | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Annual report, SOP, dokumen perusahaan                     |
| `file_nda`                  | `ADMINISTRATIVE` | PDF        | `:restricted`  | NDA dengan mitra                                           |
| `file_presentation`         | `SUPPLEMENTAL`   | PDF / PPTX | `:inherit`     | Slide presentasi                                           |
| `file_daftar_isi`           | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Daftar isi                                                 |
| `file_lampiran`             | `SUPPLEMENTAL`   | PDF        | `:inherit`     | Lampiran                                                   |

---

## 7. Type 4 — Laporan Proyek (Project Report)

Common in Teknik, Vokasi (D3/D4/Sarjana Terapan), and Arsitektur. Often the most file-heavy type outside of thesis.

### 7.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                 | Ecto Field             | Type        | Notes                                                                                                |
| --------------------- | ---------------------- | ----------- | ---------------------------------------------------------------------------------------------------- |
| `degree_level`        | `:degree_level`        | `Ecto.Enum` | `values: [:d3, :d4, :s1_terapan, :s1]`                                                               |
| `project_title`       | `:project_title`       | `:string`   | Nama resmi proyek                                                                                    |
| `project_type`        | `:project_type`        | `Ecto.Enum` | `values: [:desain, :konstruksi, :implementasi_software, :manufaktur, :sistem, :perencanaan_wilayah]` |
| `project_client`      | `:project_client`      | `:string`   | Nama klien / mitra                                                                                   |
| `project_period`      | `:project_period`      | `:string`   | Tanggal mulai dan selesai proyek                                                                     |
| `project_location`    | `:project_location`    | `:string`   | Lokasi pelaksanaan                                                                                   |
| `project_deliverable` | `:project_deliverable` | `:string`   | Apa yang diserahkan: prototipe / software / desain / dokumen teknis                                  |
| `date_issued`         | `:date_issued`         | `:date`     | Tanggal pengesahan laporan                                                                           |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                         |
| -------------- | --------------- | ----------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field            | Ecto Field        | Type        | Notes                                     |
| ---------------- | ----------------- | ----------- | ----------------------------------------- |
| `team_role`      | `:team_role`      | `Ecto.Enum` | `values: [:ketua, :anggota, :pic_teknis]` |
| `project_budget` | `:project_budget` | `:string`   | Anggaran proyek                           |
| `patent_pending` | `:patent_pending` | `:boolean`  | Sedang dalam proses paten                 |

#### Optional — Relational Tables

| Field                 | Table               | Notes                                                   |
| --------------------- | ------------------- | ------------------------------------------------------- |
| `team_members`        | `item_team_members` | Anggota tim lain (nama + NIM + peran)                   |
| `industry_supervisor` | `item_advisors`     | `advisor_role: :industry` — nama + jabatan + perusahaan |

#### Supplementary — `item_metadata_extras`

| Field                | Key                              | Notes                                    |
| -------------------- | -------------------------------- | ---------------------------------------- |
| `technology_stack`   | `local.description.techstack`    | Multi-value: one row per technology/tool |
| `standard_reference` | `local.relation.standard`        | Multi-value: SNI, ISO, IEEE codes        |
| `project_scale`      | `local.description.scale`        | `pilot` / `production` / `prototype`     |
| `source_code_url`    | `dc.relation.uri`                | GitHub / GitLab link                     |
| `deployment_url`     | `local.identifier.deploymenturl` | Live URL                                 |

### 7.2 File Fields

#### Mandatory

| Field Key                    | Bundle           | Format    | `access_level` | Notes                         |
| ---------------------------- | ---------------- | --------- | -------------- | ----------------------------- |
| `file_cover`                 | `THUMBNAIL`      | JPG / PNG | `:open`        | Halaman sampul                |
| `file_abstract`              | `ORIGINAL`       | PDF       | `:inherit`     | Ringkasan eksekutif / abstrak |
| `file_approval_letter`       | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan             |
| `file_originality_statement` | `LICENSE`        | PDF       | `:restricted`  | Pernyataan keaslian           |
| `file_fulltext`              | `ORIGINAL`       | PDF       | `:inherit`     | Laporan proyek lengkap        |

#### Optional

| Field Key                 | Bundle           | Format          | `access_level` | Notes                                              |
| ------------------------- | ---------------- | --------------- | -------------- | -------------------------------------------------- |
| `file_technical_drawing`  | `SOURCE`         | PDF / DWG / DXF | `:inherit`     | Gambar teknik / blueprint / CAD output             |
| `file_prototype_photo`    | `MEDIA`          | JPG / PNG / ZIP | `:inherit`     | Foto prototipe / hasil proyek                      |
| `file_test_result`        | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Laporan hasil pengujian                            |
| `file_user_manual`        | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Manual pengguna / SOP                              |
| `file_presentation`       | `SUPPLEMENTAL`   | PDF / PPTX      | `:inherit`     | Slide presentasi                                   |
| `file_project_charter`    | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Dokumen project charter / proposal awal            |
| `file_minutes_of_meeting` | `ADMINISTRATIVE` | PDF             | `:restricted`  | Berita acara rapat                                 |
| `file_client_acceptance`  | `ADMINISTRATIVE` | PDF             | `:restricted`  | Berita acara serah terima proyek                   |
| `file_daftar_isi`         | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Daftar isi                                         |
| `file_lampiran`           | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Lampiran                                           |
| `file_source_code`        | `SOURCE`         | ZIP / TAR.GZ    | `:inherit`     | Source code archive                                |
| `file_pcb_schematic`      | `SOURCE`         | PDF / Gerber    | `:inherit`     | Skematik PCB / circuit diagram (hardware projects) |
| `file_bom`                | `SUPPLEMENTAL`   | PDF / XLSX      | `:inherit`     | Bill of Materials                                  |

---

## 8. Type 5 — Karya Kreatif (Creative Work)

Seni Rupa, Desain, Sastra, Musik, Film, Arsitektur, Kriya. Most varied file formats of all 13 types.

### 8.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                 | Ecto Field             | Type        | Notes                                                                                                                               |
| --------------------- | ---------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `degree_level`        | `:degree_level`        | `Ecto.Enum` | `values: [:s1, :s2, :s3]`                                                                                                           |
| `creative_work_type`  | `:creative_work_type`  | `Ecto.Enum` | `values: [:novel, :antologi_puisi, :film_pendek, :komposisi_musik, :lukisan, :desain_produk, :animasi, :game, :arsitektur, :kriya]` |
| `medium_material`     | `:medium_material`     | `:string`   | Media/bahan: cat minyak / digital / kayu / video / audio                                                                            |
| `dimensions_duration` | `:dimensions_duration` | `:string`   | Ukuran (cm × cm) atau durasi (mm:ss)                                                                                                |
| `creation_period`     | `:creation_period`     | `:string`   | Periode penciptaan karya                                                                                                            |
| `artistic_statement`  | `:artistic_statement`  | `:string`   | Pernyataan artistik / konsep                                                                                                        |
| `date_issued`         | `:date_issued`         | `:date`     | Tanggal ujian / pameran                                                                                                             |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                                                 |
| -------------- | --------------- | ----------------------------------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` — Pembimbing / Promotor |

#### Optional — Columns on `items`

| Field                    | Ecto Field                | Type        | Notes                                                                        |
| ------------------------ | ------------------------- | ----------- | ---------------------------------------------------------------------------- |
| `exhibition_performance` | `:exhibition_performance` | `:string`   | Nama pameran / pertunjukan                                                   |
| `exhibition_date`        | `:exhibition_date`        | `:date`     | Tanggal pameran / pertunjukan                                                |
| `exhibition_venue`       | `:exhibition_venue`       | `:string`   | Tempat pameran                                                               |
| `copyright_type`         | `:copyright_type`         | `Ecto.Enum` | `values: [:all_rights_reserved, :cc_by, :cc_by_sa, :cc_by_nc, :cc_by_nc_sa]` |
| `collection_owner`       | `:collection_owner`       | `:string`   | Siapa yang menyimpan karya fisik saat ini                                    |

#### Optional — Relational Tables

| Field              | Table               | Notes                      |
| ------------------ | ------------------- | -------------------------- |
| `curator_director` | `item_advisors`     | `advisor_role: :curator`   |
| `collaborators`    | `item_team_members` | Penari, musisi, aktor, dll |

#### Supplementary — `item_metadata_extras`

| Field                | Key                              | Notes                                    |
| -------------------- | -------------------------------- | ---------------------------------------- |
| `inspiration_source` | `local.description.inspiration`  | Referensi / inspirasi utama              |
| `audience_reception` | `local.description.reception`    | Review / catatan respons audiens         |
| `iswc`               | `local.identifier.iswc`          | International Standard Musical Work Code |
| `isrc`               | `local.identifier.isrc`          | International Standard Recording Code    |
| `isbn`               | `dc.identifier.isbn`             | ISBN (if published as book)              |
| `hak_cipta_number`   | `local.identifier.hki`           | Nomor pendaftaran HKI di DJKI            |
| `color_palette`      | `local.description.colorpalette` | Palet warna utama                        |

### 8.2 File Fields

#### Mandatory

| Field Key                 | Bundle           | Format     | `access_level` | Notes                                           |
| ------------------------- | ---------------- | ---------- | -------------- | ----------------------------------------------- |
| `file_cover`              | `THUMBNAIL`      | JPG / PNG  | `:open`        | Cover / representasi visual karya               |
| `file_artistic_statement` | `ORIGINAL`       | PDF        | `:inherit`     | Pernyataan artistik / konsep karya (sequence 1) |
| `file_approval_letter`    | `ADMINISTRATIVE` | PDF        | `:restricted`  | Lembar pengesahan                               |
| `file_main_work`          | `ORIGINAL`       | **Varies** | `:inherit`     | **File utama karya itu sendiri**                |

**`file_main_work` accepted formats by creative type:**

| Creative Type                         | Accepted Formats                                           |
| ------------------------------------- | ---------------------------------------------------------- |
| Novel / Antologi Puisi / Naskah Drama | PDF                                                        |
| Komposisi Musik (partitur)            | PDF / MusicXML                                             |
| Rekaman Musik                         | MP3 / FLAC / WAV                                           |
| Film Pendek / Animasi                 | MP4 / MOV (or external URL stored as `storage_type: :url`) |
| Lukisan / Karya Seni Rupa 2D          | JPG / PNG / TIFF (min 300 DPI)                             |
| Karya 3D / Patung / Kriya             | JPG / PNG (multiple angles) + PDF documentation            |
| Desain Produk                         | PDF / JPG (renders) + technical drawing                    |
| Game                                  | ZIP (playable build) or external URL                       |
| Arsitektur                            | PDF (full drawing set) + JPG renders                       |
| Fotografi                             | JPG / TIFF + PDF catalog                                   |

#### Optional

| Field Key                       | Bundle           | Format           | `access_level` | Notes                                        |
| ------------------------------- | ---------------- | ---------------- | -------------- | -------------------------------------------- |
| `file_process_documentation`    | `SUPPLEMENTAL`   | PDF / ZIP of JPG | `:inherit`     | Dokumentasi proses: sketsa awal, foto proses |
| `file_exhibition_documentation` | `MEDIA`          | JPG / MP4 / PDF  | `:inherit`     | Foto / video saat dipamerkan                 |
| `file_program_booklet`          | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Program book pameran / pertunjukan           |
| `file_score_parts`              | `SOURCE`         | PDF              | `:inherit`     | Bagian instrumen terpisah (ensemble music)   |
| `file_screenplay`               | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Naskah skenario (for film)                   |
| `file_storyboard`               | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Storyboard (film / animation / game)         |
| `file_technical_rider`          | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Technical rider pementasan                   |
| `file_hki_certificate`          | `ADMINISTRATIVE` | PDF              | `:restricted`  | Sertifikat HKI / DJKI                        |
| `file_artist_statement_video`   | `MEDIA`          | MP4              | `:inherit`     | Video pernyataan artistik oleh mahasiswa     |
| `file_review_documentation`     | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Review / kritik dari kurator / juri          |

---

## 9. Type 6 — Karya Teknologi (Technological Work)

Software, hardware, apps, AI/ML models, datasets. Common in Informatika, Teknik Terapan.

### 9.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                   | Ecto Field               | Type        | Notes                                                                                                                           |
| ----------------------- | ------------------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `degree_level`          | `:degree_level`          | `Ecto.Enum` | `values: [:s1, :s2, :s3]`                                                                                                       |
| `technology_type`       | `:technology_type`       | `Ecto.Enum` | `values: [:aplikasi_mobile, :web_app, :embedded_system, :perangkat_keras, :dataset, :model_ai_ml, :algoritma, :inovasi_proses]` |
| `problem_solved`        | `:problem_solved`        | `:string`   | Masalah yang diselesaikan                                                                                                       |
| `target_user`           | `:target_user`           | `:string`   | Pengguna yang dituju                                                                                                            |
| `implementation_status` | `:implementation_status` | `Ecto.Enum` | `values: [:prototipe, :mvp, :deployed, :published]`                                                                             |
| `testing_method`        | `:testing_method`        | `Ecto.Enum` | `values: [:black_box, :white_box, :user_testing, :benchmark, :usability]`                                                       |
| `date_issued`           | `:date_issued`           | `:date`     | Tanggal pengesahan                                                                                                              |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                         |
| -------------- | --------------- | ----------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor` |

#### Optional — Columns on `items`

| Field                | Ecto Field            | Type        | Notes                                                 |
| -------------------- | --------------------- | ----------- | ----------------------------------------------------- |
| `license_type`       | `:license_type`       | `Ecto.Enum` | `values: [:mit, :apache_2, :gpl, :bsd, :proprietary]` |
| `patent_status`      | `:patent_status`      | `Ecto.Enum` | `values: [:tidak_ada, :dalam_proses, :granted]`       |
| `hki_number`         | `:hki_number`         | `:string`   | Nomor HKI / DJKI                                      |
| `industry_tested_at` | `:industry_tested_at` | `:string`   | Nama institusi/perusahaan tempat uji coba             |

#### Optional — Relational Tables

| Field           | Table               | Notes                                |
| --------------- | ------------------- | ------------------------------------ |
| `co_developers` | `item_team_members` | Rekan pengembang (nama + NIM + role) |

#### Supplementary — `item_metadata_extras`

| Field                 | Key                              | Notes                                              |
| --------------------- | -------------------------------- | -------------------------------------------------- |
| `technology_stack`    | `local.description.techstack`    | Multi-value: one row per language/framework/tool   |
| `platform_os`         | `local.description.platform`     | Multi-value: Android / iOS / Web / Linux / Arduino |
| `performance_metrics` | `local.description.metrics`      | Accuracy %, response time, throughput              |
| `source_code_url`     | `dc.relation.uri`                | GitHub / GitLab URL                                |
| `deployment_url`      | `local.identifier.deploymenturl` | Live URL                                           |
| `dataset_url`         | `local.identifier.dataseturl`    | Mendeley Data, Zenodo, Kaggle                      |
| `model_architecture`  | `local.description.modelarch`    | ResNet-50, BERT, Transformer, etc.                 |
| `acm_classification`  | `local.subject.acm`              | ACM CCS code                                       |

### 9.2 File Fields

#### Mandatory

| Field Key               | Bundle           | Format     | `access_level` | Notes                                                 |
| ----------------------- | ---------------- | ---------- | -------------- | ----------------------------------------------------- |
| `file_cover`            | `THUMBNAIL`      | JPG / PNG  | `:open`        | Cover laporan / screenshot UI                         |
| `file_abstract`         | `ORIGINAL`       | PDF        | `:inherit`     | Abstrak karya teknologi (sequence 1)                  |
| `file_approval_letter`  | `ADMINISTRATIVE` | PDF        | `:restricted`  | Lembar pengesahan                                     |
| `file_technical_report` | `ORIGINAL`       | PDF        | `:inherit`     | Laporan teknis lengkap (methodology, design, testing) |
| `file_main_artifact`    | `SOURCE`         | **Varies** | `:inherit`     | **Artefak utama teknologi**                           |

**`file_main_artifact` accepted formats by technology type:**

| Technology Type            | Accepted Formats                           |
| -------------------------- | ------------------------------------------ |
| Aplikasi Mobile            | APK / IPA + PDF documentation              |
| Web Application            | ZIP (deployable) or URL link               |
| Embedded System / Hardware | ZIP (firmware + schematics)                |
| Model AI / ML              | Pickle / H5 / ONNX / ZIP + Python notebook |
| Dataset                    | CSV / JSON / XLSX / ZIP + README           |
| Algoritma                  | PDF (pseudocode + proof) + source code     |
| Perangkat Keras            | PDF (circuit diagrams, specifications)     |

#### Optional

| Field Key                 | Bundle           | Format           | `access_level` | Notes                                   |
| ------------------------- | ---------------- | ---------------- | -------------- | --------------------------------------- |
| `file_source_code`        | `SOURCE`         | ZIP / TAR.GZ     | `:inherit`     | Source code archive                     |
| `file_test_report`        | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Laporan pengujian                       |
| `file_user_manual`        | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Manual pengguna                         |
| `file_api_documentation`  | `SUPPLEMENTAL`   | PDF / HTML       | `:inherit`     | Dokumentasi API                         |
| `file_demo_video`         | `MEDIA`          | MP4              | `:inherit`     | Video demo / walkthrough                |
| `file_prototype_photo`    | `MEDIA`          | JPG / PNG        | `:inherit`     | Foto prototipe hardware                 |
| `file_dataset`            | `SOURCE`         | CSV / JSON / ZIP | `:inherit`     | Dataset yang digunakan / dihasilkan     |
| `file_jupyter_notebook`   | `SOURCE`         | IPYNB / PDF      | `:inherit`     | Jupyter notebook (for ML/data projects) |
| `file_hki_certificate`    | `ADMINISTRATIVE` | PDF              | `:restricted`  | Sertifikat HKI / DJKI                   |
| `file_patent_application` | `ADMINISTRATIVE` | PDF              | `:restricted`  | Dokumen permohonan paten                |
| `file_presentation`       | `SUPPLEMENTAL`   | PDF / PPTX       | `:inherit`     | Slide presentasi                        |

---

## 10. Type 7 — Artikel Jurnal Nasional Terakreditasi (Sinta)

### 10.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                 | Ecto Field                       | Type        | Notes                                                 |
| --------------------- | -------------------------------- | ----------- | ----------------------------------------------------- |
| `journal_name`        | `:journal_name`                  | `:string`   | Nama jurnal — exact name as registered at Sinta       |
| `sinta_id`            | stored in `item_metadata_extras` | —           | `key: "local.identifier.sinta"`                       |
| `sinta_accreditation` | `:sinta_accreditation`           | `Ecto.Enum` | `values: [:s1, :s2, :s3, :s4, :s5, :s6]`              |
| `issn`                | `:issn`                          | `:string`   | ISSN cetak                                            |
| `eissn`               | `:eissn`                         | `:string`   | ISSN online (E-ISSN)                                  |
| `volume`              | `:volume`                        | `:string`   | Volume jurnal                                         |
| `issue`               | `:issue`                         | `:string`   | Nomor / issue                                         |
| `page_start`          | `:page_start`                    | `:integer`  | Halaman awal                                          |
| `page_end`            | `:page_end`                      | `:integer`  | Halaman akhir                                         |
| `doi`                 | `:doi`                           | `:string`   | DOI artikel — mandatory for Sinta-accredited journals |
| `date_issued`         | `:date_issued`                   | `:date`     | Tanggal publikasi artikel                             |
| `publisher`           | `:publisher`                     | `:string`   | Penerbit jurnal                                       |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                                     |
| -------------- | --------------- | ----------------------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor`             |
| `co_authors`   | `item_authors`  | Multi-value: nama, afiliasi, email, ORCID |

#### Optional — Columns on `items`

| Field              | Ecto Field          | Type        | Notes                                                                 |
| ------------------ | ------------------- | ----------- | --------------------------------------------------------------------- |
| `peer_review_type` | `:peer_review_type` | `Ecto.Enum` | `values: [:single_blind, :double_blind, :open_review]`                |
| `article_type`     | `:article_type`     | `Ecto.Enum` | `values: [:research_article, :review, :short_communication, :letter]` |

#### Supplementary — `item_metadata_extras`

| Field                  | Key                         | Notes                           |
| ---------------------- | --------------------------- | ------------------------------- |
| `conflict_of_interest` | `local.rights.conflict`     | Pernyataan conflict of interest |
| `funding_statement`    | `local.description.funding` | Pernyataan pendanaan            |
| `open_access_status`   | `local.rights.oastatus`     | `gold` / `green` / `closed`     |
| `preprint_url`         | `dc.relation.uri`           | OSF, arXiv, SSRN URL            |
| `data_availability`    | `local.identifier.dataurl`  | Link ke dataset pendukung       |

### 10.2 File Fields

#### Mandatory

| Field Key                | Bundle           | Format    | `access_level` | Notes                                              |
| ------------------------ | ---------------- | --------- | -------------- | -------------------------------------------------- |
| `file_cover`             | `THUMBNAIL`      | JPG / PNG | `:open`        | Screenshot halaman depan artikel yang sudah terbit |
| `file_published_article` | `ORIGINAL`       | PDF       | `:inherit`     | PDF artikel yang sudah diterbitkan (as published)  |
| `file_approval_letter`   | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan dari institusi                   |
| `file_acceptance_letter` | `ADMINISTRATIVE` | PDF       | `:restricted`  | Surat accepted dari jurnal                         |

#### Optional

| Field Key                     | Bundle           | Format           | `access_level` | Notes                                  |
| ----------------------------- | ---------------- | ---------------- | -------------- | -------------------------------------- |
| `file_manuscript_submitted`   | `SUPPLEMENTAL`   | PDF / DOCX       | `:inherit`     | Versi manuskrip sebelum accepted       |
| `file_review_response`        | `SUPPLEMENTAL`   | PDF / DOCX       | `:inherit`     | Response to reviewers letter           |
| `file_turnitin_report`        | `ADMINISTRATIVE` | PDF              | `:restricted`  | Laporan similarity                     |
| `file_raw_data`               | `SOURCE`         | CSV / XLSX / ZIP | `:inherit`     | Dataset penelitian pendukung           |
| `file_supplementary_material` | `SUPPLEMENTAL`   | PDF / ZIP        | `:inherit`     | Supplementary material dari jurnal     |
| `file_postprint`              | `SUPPLEMENTAL`   | PDF              | `:inherit`     | Postprint / author-accepted manuscript |

---

## 11. Type 8 — Artikel Jurnal Internasional Bereputasi (Scopus / WoS)

Inherits all Type 7 fields, plus:

### 11.1 Metadata Fields

#### Mandatory — Additional Columns (beyond Type 7)

| Field            | Ecto Field                       | Type        | Notes                                                             |
| ---------------- | -------------------------------- | ----------- | ----------------------------------------------------------------- |
| `scopus_id`      | stored in `item_metadata_extras` | —           | `key: "local.identifier.scopus"`                                  |
| `wos_id`         | stored in `item_metadata_extras` | —           | `key: "local.identifier.wos"`                                     |
| `quartile`       | `:quartile`                      | `Ecto.Enum` | `values: [:q1, :q2, :q3, :q4]` — **CRITICAL for Dikti reporting** |
| `scopus_indexed` | `:scopus_indexed`                | `:boolean`  | Default `false`                                                   |
| `wos_indexed`    | `:wos_indexed`                   | `:boolean`  | Default `false`                                                   |

#### Supplementary — `item_metadata_extras`

| Field                   | Key                                | Notes                       |
| ----------------------- | ---------------------------------- | --------------------------- |
| `citation_count_scopus` | `local.description.citationscopus` |                             |
| `citation_count_wos`    | `local.description.citationwos`    |                             |
| `orcid_all_authors`     | `dc.contributor.orcid`             | Multi-value: one per author |
| `pubmed_id`             | `local.identifier.pubmed`          | For medical/health journals |

### 11.2 File Fields

#### Mandatory (all of Type 7, plus)

| Field Key                    | Bundle           | Format    | `access_level` | Notes                                                                        |
| ---------------------------- | ---------------- | --------- | -------------- | ---------------------------------------------------------------------------- |
| `file_scopus_indexing_proof` | `ADMINISTRATIVE` | PDF / PNG | `:restricted`  | Screenshot / bukti terindeks di Scopus atau WoS — required for BKD reporting |
| `file_doi_certificate`       | `ADMINISTRATIVE` | PDF / PNG | `:restricted`  | Bukti DOI registered                                                         |

#### Optional (additional beyond Type 7)

| Field Key                  | Bundle           | Format    | `access_level` | Notes                                   |
| -------------------------- | ---------------- | --------- | -------------- | --------------------------------------- |
| `file_wos_indexing_proof`  | `ADMINISTRATIVE` | PDF / PNG | `:restricted`  | Screenshot bukti indexing di WoS        |
| `file_citation_screenshot` | `SUPPLEMENTAL`   | PDF / PNG | `:inherit`     | Screenshot jumlah sitasi                |
| `file_preprint`            | `SUPPLEMENTAL`   | PDF       | `:inherit`     | Preprint version (arXiv, OSF, SSRN)     |
| `file_open_access_proof`   | `ADMINISTRATIVE` | PDF / PNG | `:restricted`  | Bukti pembayaran APC atau konfirmasi OA |

---

## 12. Type 9 — Artikel Prosiding Konferensi Internasional

### 12.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                 | Ecto Field             | Type       | Notes                                                                                                                                  |
| --------------------- | ---------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `conference_name`     | `:conference_name`     | `:string`  | Nama konferensi (full official name)                                                                                                   |
| `conference_date`     | `:conference_date`     | `:date`    | Tanggal penyelenggaraan — stored as `conference_date` in `item_metadata_extras` `key: "local.date.conference"` or as a `:string` field |
| `conference_location` | `:conference_location` | `:string`  | Kota, negara                                                                                                                           |
| `publisher`           | `:publisher`           | `:string`  | IEEE / ACM / Springer / Elsevier                                                                                                       |
| `doi`                 | `:doi`                 | `:string`  | DOI artikel                                                                                                                            |
| `isbn`                | `:isbn`                | `:string`  | ISBN prosiding                                                                                                                         |
| `issn`                | `:issn`                | `:string`  | ISSN prosiding                                                                                                                         |
| `page_start`          | `:page_start`          | `:integer` | Halaman awal                                                                                                                           |
| `page_end`            | `:page_end`            | `:integer` | Halaman akhir                                                                                                                          |
| `date_issued`         | `:date_issued`         | `:date`    | Tanggal publikasi prosiding                                                                                                            |

#### Mandatory — Relational Tables

| Field          | Table           | Notes                               |
| -------------- | --------------- | ----------------------------------- |
| `main_advisor` | `item_advisors` | `advisor_role: :main_advisor`       |
| `co_authors`   | `item_authors`  | nama, afiliasi, email — multi-value |

#### Optional — Columns on `items`

| Field              | Ecto Field          | Type      | Notes                    |
| ------------------ | ------------------- | --------- | ------------------------ |
| `best_paper_award` | `:best_paper_award` | `:string` | Nama award (if received) |

#### Supplementary — `item_metadata_extras`

| Field                      | Key                                | Notes                                            |
| -------------------------- | ---------------------------------- | ------------------------------------------------ |
| `extended_to_journal`      | `dc.relation.uri`                  | URL jurnal extension (if applicable)             |
| `core_rank`                | `local.subject.corerank`           | `A*` / `A` / `B` / `C` — CORE Conference Ranking |
| `virtual_presentation_url` | `local.identifier.presentationurl` | URL rekaman presentasi online                    |

### 12.2 File Fields

#### Mandatory

| Field Key                | Bundle           | Format    | `access_level` | Notes                                             |
| ------------------------ | ---------------- | --------- | -------------- | ------------------------------------------------- |
| `file_cover`             | `THUMBNAIL`      | JPG / PNG | `:open`        | Screenshot halaman depan artikel dalam prosiding  |
| `file_published_paper`   | `ORIGINAL`       | PDF       | `:inherit`     | PDF artikel dari prosiding yang sudah diterbitkan |
| `file_approval_letter`   | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan                                 |
| `file_acceptance_letter` | `ADMINISTRATIVE` | PDF       | `:restricted`  | Surat acceptance dari konferensi                  |

#### Optional

| Field Key                      | Bundle           | Format           | `access_level` | Notes                                                    |
| ------------------------------ | ---------------- | ---------------- | -------------- | -------------------------------------------------------- |
| `file_presentation_slides`     | `SUPPLEMENTAL`   | PDF / PPTX       | `:inherit`     | Slide presentasi di konferensi                           |
| `file_poster`                  | `MEDIA`          | PDF / JPG        | `:inherit`     | File poster (min A0 size)                                |
| `file_presentation_video`      | `MEDIA`          | MP4 / URL        | `:inherit`     | Rekaman presentasi                                       |
| `file_indexing_proof`          | `ADMINISTRATIVE` | PDF / PNG        | `:restricted`  | Bukti artikel terindeks di Scopus / IEEE Xplore / ACM DL |
| `file_conference_registration` | `ADMINISTRATIVE` | PDF              | `:restricted`  | Bukti registrasi / pembayaran ke konferensi              |
| `file_raw_data`                | `SOURCE`         | CSV / XLSX / ZIP | `:inherit`     | Dataset pendukung                                        |

---

## 13. Type 10 — Capstone Project

Multidisciplinary, integrative, team-based. Aligned with MBKM (Merdeka Belajar Kampus Merdeka) schemes.

### 13.1 Metadata Fields

#### Mandatory — Columns on `items`

| Field                  | Ecto Field              | Type        | Notes                                                          |
| ---------------------- | ----------------------- | ----------- | -------------------------------------------------------------- |
| `degree_level`         | `:degree_level`         | `Ecto.Enum` | `values: [:s1, :d4]`                                           |
| `capstone_theme`       | `:capstone_theme`       | `:string`   | Tema besar, e.g. SDGs, Smart City, Ketahanan Pangan            |
| `project_type`         | `:project_type`         | `Ecto.Enum` | `values: [:product, :service, :policy, :research, :community]` |
| `partner_institution`  | `:partner_institution`  | `:string`   | Institusi mitra (DUDI / NGO / Pemda)                           |
| `problem_statement`    | `:problem_statement`    | `:string`   | Rumusan masalah yang dihadapi mitra                            |
| `solution_description` | `:solution_description` | `:string`   | Solusi yang dikembangkan tim                                   |
| `date_issued`          | `:date_issued`          | `:date`     | Tanggal pengesahan                                             |

#### Mandatory — Relational Tables

| Field                | Table               | Notes                                                  |
| -------------------- | ------------------- | ------------------------------------------------------ |
| `main_advisor`       | `item_advisors`     | `advisor_role: :main_advisor`                          |
| `partner_supervisor` | `item_advisors`     | `advisor_role: :industry` — Pembimbing dari mitra      |
| `team_members`       | `item_team_members` | Semua anggota tim (nama + NIM + program studi + peran) |

#### Optional — Columns on `items`

| Field              | Ecto Field          | Type        | Notes                                                                                           |
| ------------------ | ------------------- | ----------- | ----------------------------------------------------------------------------------------------- |
| `mbkm_scheme`      | `:mbkm_scheme`      | `Ecto.Enum` | `values: [:magang, :kkn_t, :penelitian, :proyek_independen, :pertukaran_mahasiswa, :wirausaha]` |
| `project_budget`   | `:project_budget`   | `:string`   | Anggaran proyek                                                                                 |
| `capstone_partner` | `:capstone_partner` | `:string`   | Nama mitra capstone                                                                             |

#### Supplementary — `item_metadata_extras`

| Field                       | Key                             | Notes                               |
| --------------------------- | ------------------------------- | ----------------------------------- |
| `sdg_goals`                 | `local.subject.sdg`             | Multi-value: one row per SDG number |
| `deliverable_list`          | `local.description.deliverable` | Multi-value                         |
| `cross_disciplinary_fields` | `local.subject.discipline`      | Multi-value                         |
| `student_reflection`        | `local.description.reflection`  | Refleksi pembelajaran               |
| `community_testimonial`     | `local.description.testimonial` | Testimoni dari mitra / komunitas    |

### 13.2 File Fields

#### Mandatory

| Field Key                  | Bundle           | Format    | `access_level` | Notes                                               |
| -------------------------- | ---------------- | --------- | -------------- | --------------------------------------------------- |
| `file_cover`               | `THUMBNAIL`      | JPG / PNG | `:open`        | Cover laporan / foto tim dengan mitra               |
| `file_abstract`            | `ORIGINAL`       | PDF       | `:inherit`     | Ringkasan eksekutif proyek                          |
| `file_approval_letter`     | `ADMINISTRATIVE` | PDF       | `:restricted`  | Lembar pengesahan dari dosen + mitra                |
| `file_final_report`        | `ORIGINAL`       | PDF       | `:inherit`     | Laporan akhir capstone project lengkap              |
| `file_partner_endorsement` | `ADMINISTRATIVE` | PDF       | `:restricted`  | Surat keterangan / endorsement dari institusi mitra |

#### Optional

| Field Key                    | Bundle           | Format          | `access_level` | Notes                                           |
| ---------------------------- | ---------------- | --------------- | -------------- | ----------------------------------------------- |
| `file_project_charter`       | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Project charter / project brief awal            |
| `file_deliverable_evidence`  | `MEDIA`          | PDF / JPG / ZIP | `:inherit`     | Bukti deliverable: foto, screenshot, sertifikat |
| `file_prototype_demo`        | `MEDIA`          | MP4 / ZIP / URL | `:inherit`     | Demo produk / prototipe                         |
| `file_community_testimonial` | `SUPPLEMENTAL`   | PDF / MP4       | `:inherit`     | Testimoni dari mitra / komunitas                |
| `file_presentation`          | `SUPPLEMENTAL`   | PDF / PPTX      | `:inherit`     | Slide presentasi akhir                          |
| `file_mbkm_logbook`          | `ADMINISTRATIVE` | PDF             | `:restricted`  | Logbook kegiatan MBKM                           |
| `file_student_reflection`    | `SUPPLEMENTAL`   | PDF             | `:inherit`     | Refleksi pembelajaran mahasiswa                 |
| `file_source_code`           | `SOURCE`         | ZIP             | `:inherit`     | Source code (if project produces software)      |
| `file_financial_report`      | `ADMINISTRATIVE` | PDF             | `:restricted`  | Laporan keuangan proyek                         |

---

## 14. Ecto Schema Field Placement Guide

### 14.1 Add These Fields to the `Item` Schema

All of the following are optional columns in the `items` table. Add them to the `Item` Ecto schema and include them in `@optional_fields` in the changeset. Run a migration for each group you add.

```elixir
# ── Type-Specific Scalar Fields ─────────────────────────────────────────────

# Shared across multiple types
field :approval_date,          :date
field :research_location,      :string
field :research_period,        :string
field :funding_source,         :string
field :thesis_type_detail,     Ecto.Enum,
  values: [:kuantitatif, :kualitatif, :mixed_methods, :rnd, :ptk]
field :subject_classification, :string
field :originality_statement,  :boolean, default: false
field :institution,            :string

# Hukum / Legal
field :legal_subject_matter,   Ecto.Enum,
  values: [:pidana, :perdata, :tata_negara, :internasional,
           :bisnis, :adat, :agraria, :lingkungan]
field :case_reference,         :string
field :court_level,            Ecto.Enum,
  values: [:pn, :pt, :ma, :mk, :ptun, :arbitrase, :bani, :icc]
field :legal_issue,            :string
field :jurisdiction,           Ecto.Enum,
  values: [:indonesia, :internasional, :komparatif]
field :legal_analysis_method,  Ecto.Enum,
  values: [:normatif, :empiris, :komparatif, :socio_legal]

# Studi Kasus
field :case_study_type,        Ecto.Enum,
  values: [:bisnis, :klinis, :hukum, :psikologi, :pendidikan, :teknik]
field :case_subject,           :string
field :case_period,            :string
field :case_location,          :string
field :analysis_framework,     :string
field :subject_anonymized,     :boolean, default: false
field :informed_consent,       :boolean, default: false
field :ethics_approval_number, :string
field :industry_partner,       :string
field :data_collection_method, Ecto.Enum,
  values: [:wawancara, :observasi, :dokumen_sekunder, :mix]

# Laporan Proyek
field :project_title,          :string
field :project_type,           Ecto.Enum,
  values: [:desain, :konstruksi, :implementasi_software,
           :manufaktur, :sistem, :perencanaan_wilayah,
           :product, :service, :policy, :research, :community]
field :project_client,         :string
field :project_period,         :string
field :project_location,       :string
field :project_deliverable,    :string
field :team_role,              Ecto.Enum,
  values: [:ketua, :anggota, :pic_teknis]
field :project_budget,         :string
field :patent_pending,         :boolean, default: false

# Karya Kreatif
field :creative_work_type,     Ecto.Enum,
  values: [:novel, :antologi_puisi, :film_pendek, :komposisi_musik,
           :lukisan, :desain_produk, :animasi, :game, :arsitektur, :kriya]
field :medium_material,        :string
field :dimensions_duration,    :string
field :creation_period,        :string
field :artistic_statement,     :string
field :exhibition_performance, :string
field :exhibition_date,        :date
field :exhibition_venue,       :string
field :copyright_type,         Ecto.Enum,
  values: [:all_rights_reserved, :cc_by, :cc_by_sa, :cc_by_nc, :cc_by_nc_sa]
field :collection_owner,       :string

# Karya Teknologi
field :technology_type,        Ecto.Enum,
  values: [:aplikasi_mobile, :web_app, :embedded_system, :perangkat_keras,
           :dataset, :model_ai_ml, :algoritma, :inovasi_proses]
field :problem_solved,         :string
field :target_user,            :string
field :implementation_status,  Ecto.Enum,
  values: [:prototipe, :mvp, :deployed, :published]
field :testing_method,         Ecto.Enum,
  values: [:black_box, :white_box, :user_testing, :benchmark, :usability]
field :license_type,           Ecto.Enum,
  values: [:mit, :apache_2, :gpl, :bsd, :proprietary]
field :patent_status,          Ecto.Enum,
  values: [:tidak_ada, :dalam_proses, :granted]
field :hki_number,             :string
field :industry_tested_at,     :string

# Jurnal (Nasional + Internasional)
field :journal_name,           :string
field :issn,                   :string
field :eissn,                  :string
field :doi,                    :string
field :volume,                 :string
field :issue,                  :string
field :page_start,             :integer
field :page_end,               :integer
field :publisher,              :string
field :place_of_publication,   :string
field :isbn,                   :string
field :sinta_accreditation,    Ecto.Enum,
  values: [:s1, :s2, :s3, :s4, :s5, :s6]
field :scopus_indexed,         :boolean, default: false
field :wos_indexed,            :boolean, default: false
field :quartile,               Ecto.Enum,
  values: [:q1, :q2, :q3, :q4]
field :peer_review_type,       Ecto.Enum,
  values: [:single_blind, :double_blind, :open_review]
field :article_type,           Ecto.Enum,
  values: [:research_article, :review, :short_communication, :letter]

# Prosiding
field :conference_name,        :string
field :conference_location,    :string
field :conference_date,        :string   # stored as string "YYYY-MM-DD" for flexibility

# Capstone / MBKM
field :capstone_theme,         :string
field :partner_institution,    :string
field :problem_statement,      :string
field :solution_description,   :string
field :mbkm_scheme,            Ecto.Enum,
  values: [:magang, :kkn_t, :penelitian, :proyek_independen,
           :pertukaran_mahasiswa, :wirausaha]
field :capstone_partner,       :string
field :best_paper_award,       :string
```

### 14.2 New Child Table Schemas

#### ItemExaminer

```elixir
schema "item_examiners" do
  field :examiner_name,     :string
  field :examiner_name_alt, :string
  field :affiliation,       :string
  field :nidn,              :string
  field :sequence,          :integer, default: 1
  belongs_to :item, Kiroku.Repository.Item
  timestamps()
end
```

#### ItemTeamMember

```elixir
schema "item_team_members" do
  field :member_name,     :string
  field :member_name_alt, :string
  field :role,            Ecto.Enum,
    values: [:lead_developer, :developer, :designer, :researcher, :tester,
             :performer, :collaborator, :other],
    default: :developer
  field :student_id,      :string
  field :affiliation,     :string
  field :sequence,        :integer, default: 1
  belongs_to :item, Kiroku.Repository.Item
  timestamps()
end
```

---

## 15. Field Visibility Helper

The submission wizard shows and hides fields based on `item_type`. Define this helper:

```elixir
# lib/kiroku_web/live/helpers/field_visibility.ex
defmodule KirokuWeb.Live.Helpers.FieldVisibility do

  @thesis_types ~w(skripsi tesis disertasi tugas_akhir
                   memorandum_hukum studi_kasus laporan_proyek
                   karya_kreatif karya_teknologi capstone)a
  @journal_types ~w(jurnal_nasional jurnal_internasional prosiding)a

  def show_field?(:degree_level, type), do: type in @thesis_types
  def show_field?(:student_id, type),   do: type in @thesis_types
  def show_field?(:student_name, type), do: type in @thesis_types

  def show_field?(:journal_name, type), do: type in [:jurnal_nasional, :jurnal_internasional]
  def show_field?(:sinta_accreditation, type), do: type == :jurnal_nasional
  def show_field?(:scopus_indexed, type), do: type == :jurnal_internasional
  def show_field?(:wos_indexed, type), do: type == :jurnal_internasional
  def show_field?(:quartile, type), do: type == :jurnal_internasional
  def show_field?(:conference_name, type), do: type == :prosiding

  def show_field?(:legal_subject_matter, type), do: type == :memorandum_hukum
  def show_field?(:case_reference, type), do: type == :memorandum_hukum
  def show_field?(:court_level, type), do: type == :memorandum_hukum

  def show_field?(:case_study_type, type), do: type == :studi_kasus
  def show_field?(:subject_anonymized, type), do: type == :studi_kasus
  def show_field?(:informed_consent, type), do: type == :studi_kasus

  def show_field?(:project_type, type), do: type in [:laporan_proyek, :capstone]
  def show_field?(:project_client, type), do: type == :laporan_proyek
  def show_field?(:partner_institution, type), do: type == :capstone
  def show_field?(:mbkm_scheme, type), do: type == :capstone

  def show_field?(:creative_work_type, type), do: type == :karya_kreatif
  def show_field?(:artistic_statement, type), do: type == :karya_kreatif
  def show_field?(:medium_material, type), do: type == :karya_kreatif

  def show_field?(:technology_type, type), do: type == :karya_teknologi
  def show_field?(:problem_solved, type), do: type == :karya_teknologi
  def show_field?(:implementation_status, type), do: type == :karya_teknologi

  def show_field?(_field, _type), do: false

  # Returns the label to use for "abstract" based on item type
  def abstract_label(:karya_kreatif), do: "Pernyataan Artistik"
  def abstract_label(:karya_teknologi), do: "Deskripsi Masalah dan Solusi"
  def abstract_label(:capstone), do: "Ringkasan Eksekutif"
  def abstract_label(_), do: "Abstrak"

  # Returns the required advisor/examiner roles for a given type.
  # :skripsi/:tesis/:disertasi/:tugas_akhir all require examiner; the rest follow below.
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
end
```

---
