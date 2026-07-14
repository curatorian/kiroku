# Kiroku — Enhancement Roadmap

A living document tracking Kiroku's progress toward becoming a credible
DSpace / EPrints alternative. Update the status of each item as work proceeds.

**Legend:** `[ ]` not started · `[~]` in progress · `[x]` done

---

## A. Current strengths (production-quality)

These areas are mature and need no immediate work:

- **Metadata model** — 13 Indonesian item types, ~50 type-specific fields, structured contributors (authors/advisors/examiners/keywords with ORCID/Scopus IDs), extensible `item_metadata_extras` DC-style table.
- **DSpace SAF interop** — bidirectional Simple Archive Format import/export with Dublin Core crosswalk + Oban workers.
- **Citation export** — six real formats (APA, MLA, Chicago, IEEE, BibTeX, RIS) with edge-case handling.
- **Access control** — three-tier visibility (public/internal/private) + hierarchical RBAC policies + embargoes + bundle-forced rules + collection-default inheritance.
- **Review workflow** — clean FSM (draft→submitted→under_review→published/withdrawn) with Oban email notifications.
- **Legacy migration** — production-grade MSSQL sync with run tracking, change-detection checksums, dead-letter queue.
- **Code health** — zero TODO/FIXME markers, 146 tests, `mix precommit` clean, DB-backed runtime settings, onboarding wizard, health endpoint.

---

## B. Tier 1 — Do these first (high impact, blocks real-world use)

- [x] **1.1 Search: generated `search_vector` column + GIN index + `ts_rank` relevance**
  - Replace inline `to_tsvector` with a PostgreSQL `GENERATED ALWAYS AS (...) STORED` column.
  - Add a GIN index so search uses the index instead of recomputing the vector.
  - Order results by `ts_rank` when a term is present; keep `published_at` for browse.
  - _Notes:_ Currently `to_tsvector('indonesian', title || abstract)` is recomputed on every query (`lib/kiroku/repository.ex`). No PDF-content indexing yet (see 2.2). Extending the vector to authors/keywords needs denormalization (future).
  - _Done:_ migration `add_search_vector_to_items`, indexed `maybe_full_text_filter`, `apply_search_ordering/2` (ts_rank DESC on term; `published_at` DESC on browse). 2 new tests.

- [x] **1.2 SEO: sitemap.xml + `citation_*`/Schema.org/Open Graph meta tags**
  - Generate `sitemap.xml` (controller + Oban refresh job).
  - Add `citation_title`, `citation_author`, `citation_pdf_url`, `citation_doi` meta tags to the item layout for Google Scholar.
  - Add Schema.org `ScholarlyArticle` / `Thesis` JSON-LD.
  - Add Open Graph tags for social sharing.
  - Replace the boilerplate `robots.txt` (currently commented-out Phoenix default) and add a `Sitemap:` directive.
  - _Done:_ `SeoController` serves dynamic `/robots.txt` + `/sitemap.xml` (absolute URLs); `Repository.sitemap_entries/0` (public items/communities/collections); `KirokuWeb.SEO.item_meta/1` component rendered on the item page emits Google Scholar `citation_*`, Open Graph, Twitter Card, and Schema.org JSON-LD. `robots.txt` moved off the static-asset list. 7 new tests.

- [x] **1.3 OAI-PMH: resumptionToken + apply `set`/`from`/`until`**
  - Implement `resumptionToken` pagination (`lib/kiroku/oai/builder.ex`) — currently returns the whole corpus in one response.
  - Apply the `set` parameter (advertised by `ListSets` but ignored in `ListRecords`).
  - Apply `from`/`until` date filters (echoed but not applied today).
  - Add OAI tests (currently zero).
  - _Done:_ rewrote the OAI builder — `Repository.oai_items/1` (filters by date range + `com_`/`col_` set, ordered by `updated_at`, paginated); stateless base64 resumptionToken carrying cursor + original params; `from`/`until` selective harvesting on `updated_at`; `noRecordsMatch` error on empty results; `ListSets` now emits collections too; `GetRecord` validates identifiers (no more 500 on bad UUID). Datestamp switched to `updated_at` (was `published_at`, often nil). Crawler endpoints exempted from `SetupGuard`. 15 new OAI tests (the module previously had zero).

- [x] **1.4 Fixity: compute checksum on upload + Oban fixity-validation cron**
  - `bitstreams.checksum` exists but `Storage.Uploader` never writes it (always NULL).
  - Compute MD5 on upload, populate the column.
  - Add a periodic Oban job that recomputes and compares checksums; flag mismatches.
  - Add an admin report for failed fixity checks.
  - _Done:_ `Uploader.upload/3` now returns `%{path, checksum, size}` (MD5); the submission wizards + SAF importer persist `checksum` + `checksum_algorithm`. New `bitstream_fixity_checks` audit table + `last_fixity_at`/`last_fixity_ok` on bitstreams. `Content.check_bitstream/1` (verify / establish baseline for legacy rows / record read errors), `run_fixity_batch/1`, `fixity_summary/0`, `list_fixity_failures/0`. `FixityWorker` (Oban, daily cron `FIXITY_CRON`, default `0 3 * * *`). Dashboard "File Integrity" widget. 8 tests.

- [x] **1.5 Statistics: track downloads + surface counts + wire dead code**
  - `BitstreamController.show` serves files with no event recording — add download tracking.
  - `Analytics.count_views/1`, `top_viewed_items/1`, `views_by_date/2` have zero callers — surface on the admin dashboard and public item pages.
  - Add bot filtering (inspect `user_agent`, exclude known crawlers).
  - _Done:_ new `download_events` table + `DownloadEvent` schema; `Analytics` gained `record_download/4`, `count_downloads_for_*`, `top_downloaded_items`, plus `bot?/1` + `ip_hash/1` shared with `record_view` (both now skip crawlers). Bitstream controller records non-bot downloads on serve. Item page displays view + download counts and now records views only on the connected mount (fixed a latent double-count) with bot filtering. Admin dashboard gained a "Popular" widget (top viewed + top downloaded, item-titled). 11 tests.

- [x] **1.6 REST API: write endpoints (POST items/bitstreams)**
  - Currently read-only (`resources ... only: [:index, :show]`).
  - Add create/update/delete for items + bitstream deposit, gated by API token + `Authorization.can?`.
  - Add OpenAPI/Swagger spec (machine-readable contract).
  - _Done:_ `POST /api/v1/items` (create draft, submitter-bound), `PATCH /api/v1/items/:id` (update), `POST /api/v1/items/:id/bitstreams` (multipart file deposit with checksum + bundle validation). All gated by API token + `Authorization.can?/3` (`:create`/`:update`). Proper 201/200/400/403/404/422 JSON responses with changeset-error mapping. `/api-info` docs page updated. (OpenAPI spec deferred — it's a separate concern from the write endpoints themselves.) 10 tests.

---

## C. Tier 2 — Strongly recommended for parity

- [x] **2.1 DOI minting via DataCite (or Crossref)**
  - Register DOI on `publish_item`. Use `Req` (already a dep) for the API.
  - _Done:_ pluggable `Kiroku.Doi.Provider` behaviour with two implementations — `Kiroku.Doi.Providers.DataCite` (REST API via Req, full DataCite-JSON payload with creators/ORCID/resource types) and `Kiroku.Doi.Providers.Mock` (deterministic, network-free, for dev/test). `Kiroku.Doi` dispatches by runtime `doi_provider` setting. New `doi_status` (`pending`/`minting`/`minted`/`failed`/`not_required`) + `doi_minted_at` columns on items. Async via `Kiroku.Workers.DoiMintWorker` (Oban, max_attempts: 5) enqueued by `publish_item/1` only when `doi_enabled` is on and the item has no DOI. Master switch + provider/prefix/credentials in Settings. Existing items with a DOI backfilled to `:minted`. 14 tests.

- [x] **2.2 Full-text PDF extraction + content indexing**
  - Extract text from uploaded PDFs (Rust NIF, e.g. `pdftotext`, or an external worker).
  - Store extracted text; fold into the `search_vector`. This is the feature that makes a thesis repository genuinely useful.
  - _Done:_ `Content.extract_text/1` shells out to `pdftotext` (poppler-utils) via temp file (Elixir 1.20 dropped `System.cmd`'s `:input` option). Best-effort page count via `pdfinfo`. New `bitstream_extracted_text` table (one row per bitstream, idempotent upsert, records both text and errors). Denormalized `items.extracted_text` cache rebuilt by `Content.recompute_item_extracted_text/1` whenever extraction completes — Postgres `search_vector` GENERATED column expanded to fold `extracted_text` into the GIN-indexed tsvector. `Kiroku.Workers.PdfTextWorker` (Oban, max_attempts: 3) auto-enqueued by `Content.create_bitstream/1` for ORIGINAL/CHAPTER PDFs with stored bytes. Search vector now matches terms that appear only inside PDF bodies. 13 tests.

- [x] **2.3 Faceted search sidebar** (author, subject, year, type, faculty — with counts)
  - Replace `<select>` dropdowns with real facets returning per-value aggregation counts.
  - Brand guidelines (`plans/03:567`) already call for this layout.
  - _Done:_ `Repository.facets/1` returns per-value counts for item_type, publication_year, faculty, author_name, and keyword. Each facet's counts are computed excluding that facet's own filter (Amazon-style multi-select) so the other values don't collapse when one is picked. New `author` and `keyword` filter params on `search_items` enable clicking those facets. Refactored the search query into a shared `search_base_query/1` so results + facets stay consistent. SearchLive rewritten with a sticky left sidebar of facet groups (counts, item_type labels in Bahasa, click-to-toggle `<.link patch>` navigation). "Clear all filters" button. 11 Repository tests + 7 LiveView tests.

- [x] **2.4 Browse-by-author / browse-by-date / browse-by-title indexes**
  - Standard IR navigation. Only structural browse (community→collection→items) exists today.
  - _Done:_ `Repository.browse_by_author/1`, `browse_by_date/1`, `browse_by_title/1` aggregations (all visibility-scope aware, all paginated or limit-capped). BrowseLive extended with a `?by=structure|author|date|title` mode tab UI. Author mode renders an alphabet jump-bar + per-letter sections. Date mode lists years newest-first. Title mode paginates the alphabetical item list. Every entry links into `/search` with the matching filter, so the existing facet sidebar serves as the result page. 7 Repository tests + 6 LiveView tests.

- [ ] **2.5 SWORD v2 deposit API**
  - Required by many publishers for automated article deposit. No SWORD code exists.
  - Service Document, Col-IRI / SED-IRI, Atom entry handling.

- [ ] **2.6 Automatic thumbnail generation**
  - The `image` dep was planned (`plans/01`) but dropped. THUMBNAIL bundle exists; only generation is missing.
  - Generate first-page thumbnail for PDFs, resize uploaded images.

- [ ] **2.8 Versioning & metadata audit log**
  - No `item_versions` table, no `audit_logs`. DSpace and EPrints both have item versioning.
  - Append-only history of who changed what when (current `reviewed_by_id`/`reviewed_at` capture only the latest).

---

## D. Tier 3 — Differentiators & integration depth

- [ ] **3.1 ORCID OAuth login + ORCID API lookup + user-level ORCID**
  - ORCID is only a free-text field on authors, never on `User`.

- [ ] **3.2 OpenAIRE compliance** (funded-result metadata, project linking, grant IDs)
  - Required for EU/institutional mandates; zero code today.

- [ ] **3.3 SAML/Shibboleth / OIDC** as alternatives to PAuS
  - Only PAuS SSO exists; no federation support — limits reuse beyond UNPAD.

- [ ] **3.4 Author profile pages + item claiming**
  - No `/authors/:id`, no claim flow. Both DSpace and EPrints have author profiles.

- [ ] **3.5 Configurable per-collection workflow** (multi-step, reviewer pools)
  - Currently one hardcoded FSM shared by all collections.
  - Model workflow as data (`collection_workflows` table referencing steps).

- [ ] **3.6 RSS/Atom feeds + saved-search subscriptions + digest emails**
  - No feeds at all today.

- [ ] **3.7 Bulk metadata edit + CSV import/export**
  - `nimble_csv` was planned but dropped. Only SAF batch import exists.

- [ ] **3.8 BagIt / AIP preservation packaging**
  - Only SAF today; no archival packaging for long-term preservation.

- [ ] **3.9 Reference-manager hooks** (COinS/OpenURL, Zotero/Mendeley web importer)
  - Low effort, high user convenience.

---

## E. Tier 4 — Polish & code-health

- [ ] **4.1 Wire the silently-dropped `:review_started` and `:withdrawn` email events**
  - `review_notifier.ex` falls through to `_ -> :ok` for these two events.

- [ ] **4.2 Expose dead `Collection.license_text` + `logo_bitstream_id` fields in admin UI, or remove them**

- [ ] **4.3 Make API-token admin UI issue tokens on behalf of other users** (currently self-scoped only)

- [ ] **4.4 Replace the boilerplate `README.md` and `robots.txt`**

- [ ] **4.5 Reconcile stale docs** — `plans/05_mssql_import.md` (wrong legacy schema) and `docs/sync_and_import.md` (references nonexistent `ImportWorker`)

- [ ] **4.6 Add the planned `Group`-based RBAC** (`RbacPolicy.belongs_to :group`) for team-based review pools

- [ ] **4.7 Add OAI-PMH tests** (currently zero)

---

## F. Architectural recommendations

1. **Solr vs Postgres FTS.** Postgres FTS (1.1) gets ~80% of the way with no new infra. If typo-tolerance + faceting at scale is later needed (2.3), Meilisearch or Typesense is a lighter lift than Solr. Don't jump to Solr prematurely.

2. **Metadata registry.** Adding a metadata field today requires a migration + schema + form change. Fine for one institution; to make Kiroku a reusable platform, build a DSpace-style `metadata_field` registry so admins define fields at runtime.

3. **Media-filter pipeline.** Several Tier 2 features (thumbnail gen 2.6, PDF text extraction 2.2, virus scan 2.7) are all "do work on upload." Build a single `BitstreamProcessor` Oban pipeline with pluggable stages rather than three separate workers — matches DSpace's `MediaFilter` pattern.

4. **Configurable workflow.** The hardcoded FSM is the ceiling on review complexity. If multi-step review (3.5) is anticipated, model workflow as data before you need it.

---

## G. Completed work (this phase)

- [x] Fine-grained access permissions — three-tier visibility + RBAC delegation (commit `3d45632`)
- [x] 1.1 — indexed full-text search (`search_vector` generated column + GIN index + `ts_rank` relevance)
- [x] 1.2 — SEO/discoverability (dynamic sitemap.xml + robots.txt, Google Scholar/Schema.org/Open Graph meta tags on item pages)
- [x] 1.3 — OAI-PMH completeness (resumptionToken pagination, set/from/until filtering, noRecordsMatch, ListSets collections, identifier validation, 15 new tests)
- [x] 1.4 — File fixity (checksum on upload, bitstream_fixity_checks audit table, daily FixityWorker cron, dashboard widget, 8 tests)
- [x] 1.5 — Usage statistics (download tracking, bot filtering, view/download counts on item page + admin dashboard, fixed double-counting, 11 tests)
- [x] 1.6 — REST write API (create/update item, multipart bitstream deposit, authorization-gated, /api-info updated, 10 tests)
- [x] 2.1 — DOI minting (pluggable DataCite/Mock providers, async via Oban on publish, 14 tests)
- [x] 2.2 — PDF text extraction (pdftotext + bitstream_extracted_text + denormalized item cache + search_vector fold-in, auto-enqueued on bitstream create, 13 tests)
- [x] 2.3 — Faceted search (Repository.facets/1 + multi-select sidebar, author/keyword filters, 18 tests)
- [x] 2.4 — Browse by author/date/title (3 aggregations + BrowseLive ?by= tabs, 13 tests)

**Tier 1 complete. Tier 2 underway (4 of 7).**
