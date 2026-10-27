# API v1 — kiosk-gap closure release notes

Covers the 2026-10 kiosk feedback (blockers 1–4, new endpoints, contract consistency).

## Data changes

1. Run `mix ecto.migrate` — adds:
   - `api_tokens.token_type` (`user` | `device`) + `approved_at`,
   - `kiosk_events` table (idempotent per session/type/timestamp),
   - `(faculty, published_at)` composite + `text_pattern_ops` prefix indexes on
     items (title/student_name/subject_classification).
2. Backfill legacy bitstream metadata (was NULL from the MSSQL sync and SAF
   importers). Run once after switching on:

       bin/oban-run?  # or via iex:
       %{"limit" => 500}
       |> Kiroku.Workers.BitstreamMetadataBackfillWorker.new()
       |> Oban.insert()

   mime_type is filename-derived, file_size via local stat / S3 HEAD / URL
   HEAD probe. `file_size = 0` means "externally hosted / unknown" (legacy URL
   bitstreams whose file the host stopped answering for).
3. Optional settings: `legacy_file_base_url` (DB setting) or env
   `LEGACY_FILE_BASE_URL` — resolves relative legacy `LinkPath` file paths to
   absolute URLs so HEAD probes and redirects work.

## New endpoints

- `GET /api/v1/items/{item_id}/bitstreams/{bitstream_id}` — file bytes with
  Range support (206 + Content-Range, Accept-Ranges, ETag); item id OR handle;
  403 (not omit) on access denial.
- `GET /api/v1/items/{item_id}/thumbnails/{size}` — stored THUMBNAIL bytes.
- `GET /api/v1/kiosks/status` — kiosk state (maintenance flag > needs_reverify
  for unapproved device tokens > active; deleted tokens 401 = revoked), tier,
  server_time, announcement, contact, policies. Managed in `/admin/kiosk`.
- `POST /api/v1/events` — batch ingest, idempotent per (sessionId, type,
  timestamp), max 500.
- `GET /api/v1/communities/{id}/subcommunities` — direct children.

## Changed behavior

- Error envelope: every `/api/v1` non-2xx is
  `application/json {"error": "<machine_code>", "message": "<human>"}` (422
  adds `fields`). Framework 404s from unmatched `/api/v1/*` paths now use the
  same envelope.
- `GET /api/v1/items`: new `sort`, `order`, `starts_with` params; returns
  `X-Total-Count` header + `meta` block (`total_count`, `total_pages`, `page`,
  `per_page`); `page`/`per_page` clamped >= 1, per_page capped at 100.
- `GET /api/v1/items` briefs include the owning collection
  (`collection: {id, name, handle}`).
- `GET /api/v1/items/{id}` accepts handles (already did) — the bitstreams
  route now accepts them too.
- `GET /api/v1/communities` and `GET /api/v1/collections` serve `ETag` +
  `X-Total-Count`; matching `If-None-Match` gets 304.
- Search semantics documented in swagger-repository.json (AND-of-tokens via
  plainto_tsquery('indonesian') over the generated search_vector + author/
  keyword EXISTS).

## Ops notes

- **Nginx must not answer 404 for /api/v1 paths it does not know** — proxy all
  `/api/v1/*` (and `/items/*` file URLs) to Phoenix so clients only ever see
  JSON from the framework. A 404 from nginx under /api/v1 is a misconfiguration.
- Rate limiting (Retry-After on 429) remains deferred.
- Kiosk release checklist: run backfill worker (step 2), create a device token
  in /admin/api-tokens, approve it, `GET /api/v1/kiosks/status` shows
  `"state": "active", "tier": "kiosk"`.
