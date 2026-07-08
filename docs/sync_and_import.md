# Sync & Import

How Kiroku ingests legacy thesis records from the MSSQL database into the
PostgreSQL repository. This document covers architecture, the two sync modes,
entry points, change detection, error handling, file/PDF handling, configuration,
and troubleshooting.

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Data Flow](#architecture--data-flow)
- [Source: MSSQL Legacy Views](#source-mssql-legacy-views)
- [Destination: PostgreSQL Repository Model](#destination-postgresql-repository-model)
- [Two Sync Modes](#two-sync-modes)
  - [Incremental Sync](#incremental-sync)
  - [Full Import](#full-import)
- [Entry Points](#entry-points)
  - [1. Admin Dashboard (`/admin/sync`)](#1-admin-dashboard-adminsync)
  - [2. CLI Mix Task](#2-cli-mix-task)
  - [3. Scheduled Cron Jobs](#3-scheduled-cron-jobs)
- [Change Detection & Checksums](#change-detection--checksums)
- [Error Handling & Dead-Letter Queue](#error-handling--dead-letter-queue)
- [File & PDF Handling](#file--pdf-handling)
- [Configuration](#configuration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Module Reference](#module-reference)

---

## Overview

Kiroku reads student thesis records from four legacy MSSQL views and upserts
them into the PostgreSQL-backed institutional repository. The system:

- Streams records in batches to keep memory bounded.
- Builds the community → sub-community → collection hierarchy automatically.
- Stores files as **URL references** (no PDF bytes are downloaded).
- Tracks every run and every per-record outcome for observability.
- Surfaces failures via a dead-letter queue with retry / resolve actions.

There are two distinct operations, often confused:

| | Incremental Sync | Full Import |
|---|---|---|
| Worker | `MssqlSyncWorker` | `ImportWorker` |
| What it does | Only new/changed records | Re-processes **every** record |
| Use case | Routine, cron-driven | Initial load, corrections |
| Idempotent? | Yes (checksum-gated) | Yes (upsert by handle) |

---

## Architecture & Data Flow

```
                  ┌─────────────────────────────────────────────┐
   Entry points   │  /admin/sync   │   mix task   │   Oban cron │
                  └──────────┬──────┴──────┬───────┴──────┬──────┘
                             │             │              │
                             ▼             ▼              ▼
                   ┌─────────────────────────────────────────┐
   Workers         │ MssqlSyncWorker  │   ImportWorker       │
                   │ (incremental)    │   (full)             │
                   └──────────┬───────┴───────┬──────────────┘
                              │               │
                              └──────┬────────┘
                                     ▼
                   ┌─────────────────────────────────────────┐
   Core logic      │          Kiroku.Sync.Importer           │
                   │  (single source of truth — run_view/2)  │
                   └──────┬───────────────┬──────────────────┘
                          │               │
              ┌───────────▼────┐   ┌──────▼───────────────┐
   Read/Write │  LegacyRepo    │   │  Repo (PostgreSQL)    │
              │  (MSSQL, RO)   │   │  items, bitstreams,   │
              └────────────────┘   │  communities, etc.    │
                                   │  + sync_runs tracking │
                                   └───────────────────────┘
```

All three entry points funnel through `Kiroku.Sync.Importer.run_view/2`, so
behavior is identical regardless of how a run is triggered.

---

## Source: MSSQL Legacy Views

Four views in the legacy MSSQL database, all sharing the same column layout
(`lib/kiroku/legacy_thesis.ex`):

| View | Item type |
|---|---|
| `Skripsi` | `:skripsi` |
| `Tesis` | `:tesis` |
| `Disertasi` | `:disertasi` |
| `Tugas-Akhir` | `:tugas_akhir` |

Key columns used during import:

| Column | Purpose |
|---|---|
| `NPM` | Student number — **primary key** within each view |
| `Nama`, `Kode`, `Program_Studi`, `Jenjang`, `Fakultas`, `Jenis` | Bibliographic + hierarchy placement |
| `Judul`, `Abstrak` | Title & abstract |
| `Tgl_Upload` | Upload timestamp (used by incremental change detection) |
| `LinkPath` | Base URL of the legacy file server |
| `FileCover`, `FileAbstrak`, `FileBab1..6`, `FileDaftarIsi`, `FileLampiran`, `FilePustaka`, `FileSurat`, `FileSuratIsi`, `FilePengesahan` | Relative filenames for each PDF/section |
| `stPublikasi`, `Verifikasi`, `Validasi` | Status flags — mapped to item `status` |
| `idpustaka`, `TagPustaka` | Library handle / classification |

The legacy repo is **read-only** and is started on demand by the workers
(`LegacyRepo.start_link/0`), not at application boot.

---

## Destination: PostgreSQL Repository Model

Each imported record produces:

1. **One `Item`** — the thesis metadata (title, abstract, author, status, etc.).
   - Identified by `legacy_id` (e.g. `skripsi/110110060019`) and `handle`.
2. **Multiple `Bitstream` rows** — one per non-empty `File*` column. Each stores a
   URL reference (see [File & PDF Handling](#file--pdf-handling)).
3. **Community / Collection hierarchy** — auto-created if missing:

   ```
   Tugas Akhir Mahasiswa Universitas Padjadjaran   (root community)
   └─ Fakultas <Fakultas>                           (sub-community)
       └─ <Jenjang>                                 (sub-community)
           └─ <Jenjang> <Program_Studi>              (collection — item lands here)
   ```

4. **A `SyncRun`** — one per view per run, tracking aggregate stats.
5. **`SyncRecordTracking` rows** — one per record, recording the outcome
   (`inserted` / `updated` / `failed` / `skipped`) and a content checksum.

---

## Two Sync Modes

### Incremental Sync

- **Worker:** `Kiroku.Workers.MssqlSyncWorker` (`queue: :sync`, `max_attempts: 3`, `unique: [period: 300]`)
- **Behavior:** Iterates every record in the view but **skips** records that
  haven't changed since their last successful sync (see
  [Change Detection](#change-detection--checksums)).
- **Triggered by:** cron schedule (every 6 hours per view) and the per-view
  **"Sync"** buttons on the dashboard.
- **When to use:** Routine operation. Safe to run frequently.

### Full Import

- **Worker:** `Kiroku.Workers.ImportWorker` (`queue: :sync`, `max_attempts: 1`, `unique: [period: 600]`)
- **Behavior:** Re-processes **every** record in the view(s), ignoring change
  detection. Upserts by handle, so it is idempotent.
- **Triggered by:** the **"Import all views"** / per-view **"Full Import"**
  buttons on the dashboard, or the CLI mix task.
- **When to use:** Initial migration, or after a code/schema change that should
  be applied retroactively to all records.
- **Dry-run mode:** Pass `--dry-run` (CLI) or toggle the dry-run switch on the
  dashboard. Parses and validates every record but writes nothing — useful for
  smoke-testing the connection and data shape.

---

## Entry Points

### 1. Admin Dashboard (`/admin/sync`)

LiveView: `KirokuWeb.AdminSyncLive` (`lib/kiroku_web/live/admin_sync_live.ex`)

Restricted to admins and superadmins. Provides:

- **Stats cards** — total runs, successful, failed, records processed (per view).
- **Incremental Sync** buttons — one per view + "Sync all".
- **Full Import** buttons — one per view + "Import all views", with a dry-run toggle.
- **MSSQL connection status** panel (live `SELECT @@VERSION` probe).
- **Recent runs** list (auto-refreshes every 5 seconds while jobs are active).
- **Dead-letter queue** with per-row **Retry** and **Resolve** actions.
- **SAF export / import** section (DSpace Simple Archive Format — separate flow).

Clicks enqueue Oban jobs; nothing runs synchronously in the LiveView process.

### 2. CLI Mix Task

```
mix kiroku.import_from_mssql                       # full import, all views
mix kiroku.import_from_mssql --dry-run             # validate only
mix kiroku.import_from_mssql --incremental         # only changed records
mix kiroku.import_from_mssql --view Skripsi        # one view
mix kiroku.import_from_mssql --batch-size 500      # larger stream chunks
mix kiroku.import_from_mssql --check-connection    # probe MSSQL, no import
```

Options:

| Flag | Type | Default | Description |
|---|---|---|---|
| `--dry-run` | bool | `false` | Parse and validate but persist nothing. |
| `--incremental` | bool | `false` | Only sync records changed since last run. |
| `--view NAME` | string | all | One of `Skripsi`, `Tesis`, `Disertasi`, `Tugas-Akhir`. |
| `--batch-size N` | int | `100` | Streaming chunk size. |
| `--check-connection` | bool | `false` | Test MSSQL connectivity and exit. |

### 3. Scheduled Cron Jobs

Configured in `config/config.exs` (override with the `SYNC_CRON` env var,
default `0 */6 * * *` — every 6 hours):

```elixir
{sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Skripsi"}},
{sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Tesis"}},
{sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Disertasi"}},
{sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Tugas-Akhir"}}
```

These enqueue four `MssqlSyncWorker` jobs per tick (incremental mode).

---

## Change Detection & Checksums

Implemented in `Kiroku.Sync` (`lib/kiroku/sync.ex`).

A record is considered **changed** (and thus eligible for incremental sync) if
**any** of these are true:

1. It has no prior `SyncRecordTracking` row (brand new).
2. Its **SHA-256 checksum** differs from the last successful sync.
3. Its `Tgl_Upload` timestamp is newer than the last sync's `last_synced_at`.

The checksum is computed over a fixed set of relevant fields joined by `|`:

```
Judul | Abstrak | Fakultas | Program_Studi | Jenjang | Nama |
stPublikasi | Verifikasi | Validasi | LinkPath | FileCover | FileAbstrak | Tgl_Upload
```

Full imports ignore this entirely — they re-process every record unconditionally.

---

## Error Handling & Dead-Letter Queue

**Per-record failures are isolated.** If a single record fails to insert, the
run continues with the next record. The failure is recorded as a
`SyncRecordTracking` row with `action: "failed"` and the changeset errors in
`error_message`.

A `SyncRun` is only marked **failed** if **every** record in the view failed
(`failed >= total`). Partial failures leave the run as `completed` with the
failure count visible on the dashboard.

**Dead-letter queue** (`Kiroku.Sync.DeadLetterQueue`): records that fail
repeatedly and require manual intervention are surfaced on `/admin/sync` with
two actions:

- **Retry** — enqueues a `SyncRetryWorker` job that calls
  `Importer.run_single/3` to re-process just that record.
- **Resolve** — marks the entry as resolved (with a note) and hides it from the
  active queue.

Error categories (validated): `transient`, `data`, `system`, `critical`, `unknown`.

---

## File & PDF Handling

**No PDFs are downloaded during import.** The legacy `File*` columns hold
**relative filenames**, and `LinkPath` holds a base URL. The importer
reconstructs a full URL and stores it as a reference.

For each non-empty `File*` column, a `Bitstream` row is created with:

```elixir
storage_type: :url
storage_url:  build_file_url(link_path, file_col)   # simple string concat
```

File → bundle mapping (`lib/kiroku/sync/importer.ex` `create_bitstreams_for_record/2`):

| Source column | Bundle | Access |
|---|---|---|
| `FileCover` | `THUMBNAIL` | open |
| `FileAbstrak` | `ORIGINAL` | inherit |
| `FileBab1..6` | `CHAPTER` (seq 1..6) | inherit |
| `FileDaftarIsi` | `SUPPLEMENTAL` (1) | inherit |
| `FilePustaka` | `SUPPLEMENTAL` (2) | inherit |
| `FileLampiran` | `SUPPLEMENTAL` (3) | inherit |
| `FilePengesahan` | `ADMINISTRATIVE` (1) | restricted |
| `FileSurat` | `ADMINISTRATIVE` (2) | restricted |
| `FileSuratIsi` | `ADMINISTRATIVE` (3) | restricted |

`build_file_url/2` is pure string concatenation (`lib/kiroku/sync/importer.ex:527`):

```elixir
build_file_url("https://repo.../thesis/110110/2006/", "110110060019_c_7608.pdf")
# => "https://repo.../thesis/110110/2006/110110060019_c_7608.pdf"
```

When a `:url` bitstream is requested, the controller issues a plain HTTP
redirect to the stored URL (`lib/kiroku_web/controllers/bitstream_controller.ex`).
The legacy file server (which may be fronting MinIO, e.g. URLs containing
`thesis-minio/`) is responsible for serving the actual bytes.

> **Note:** The importer does **not** fetch, download, or persist any file
> content. Filesystem/MinIO uploads only happen in the separate SAF importer
> and the interactive submission UI.

---

## Configuration

### MSSQL connection (read-only legacy repo)

Configured via environment variables, read in `config/runtime.exs` (prod) and
`config/dev.exs` (dev):

| Env var | Required | Default | Description |
|---|---|---|---|
| `MSSQL_HOST` | yes | — | MSSQL server hostname |
| `MSSQL_DB` | yes | — | Legacy database name |
| `MSSQL_USER` | yes | — | Database username (read-only recommended) |
| `MSSQL_PASS` | yes | — | Database password |
| `MSSQL_PORT` | no | `1433` | MSSQL TCP port |

Pool size is fixed at `2` (the repo is import-time only, not on the hot path).

Verify connectivity any time with:

```bash
mix kiroku.import_from_mssql --check-connection
```

### Oban queues

Defined in `config/config.exs`:

```elixir
queues: [default: 10, embargo: 2, notifications: 5, sync: 2, sync_retries: 1]
```

- `sync` — both `ImportWorker` and `MssqlSyncWorker` (concurrency 2).
- `sync_retries` — `SyncRetryWorker` for dead-letter retries (concurrency 1).

### Cron overrides

| Env var | Default | Controls |
|---|---|---|
| `SYNC_CRON` | `0 */6 * * *` | Incremental sync schedule |
| `EMBARGO_CRON` | `0 2 * * *` | Embargo lifter (unrelated to import) |

---

## Monitoring

The `/admin/sync` dashboard auto-refreshes every 5 seconds while jobs are
active, showing:

- Aggregate stats per source view (from `Kiroku.Sync.get_sync_stats/0`).
- The last 15 `SyncRun` rows with status, duration, and record counts.
- Unresolved dead-letter entries (up to 50).

To inspect Oban jobs directly (outside the UI):

```bash
mix run -e '
{:ok, _} = Application.ensure_all_started(:oban)
import Ecto.Query
Kiroku.Repo.all(
  from j in Oban.Job,
    where: j.queue == "sync",
    order_by: [desc: j.inserted_at],
    limit: 20,
    select: map(j, [:id, :worker, :state, :args, :attempt, :errors, :inserted_at])
) |> IO.inspect()
'
```

---

## Troubleshooting

### "Import all views" button does nothing

Symptoms: no flash, no new runs in Recent Runs. Likely causes, in order:

1. **Oban unique constraint.** Both workers are `unique`-gated
   (`ImportWorker` 10 min, `MssqlSyncWorker` 5 min). Clicking again with identical
   args inside that window silently rejects the insert and shows the error flash
   *"Could not queue the job. It may already be running."* Wait or cancel the
   existing job.
2. **MSSQL unreachable.** Check the connection panel on the dashboard or run
   `mix kiroku.import_from_mssql --check-connection`. If `SELECT @@VERSION` times
   out, no records will import even though the job runs.
3. **Job crashed on insert.** Run the Oban query above and inspect `errors`.
   A common cause is a Postgrex type mismatch (e.g. a `bigint` PK column
   receiving a UUID) — fix the offending schema/migration, then re-enqueue.

### Records are skipped unexpectedly

In incremental mode, records skip when `should_sync_record?/2` returns false
(unchanged checksum + old `Tgl_Upload`). Run a **full import** (or the CLI task
without `--incremental`) to force reprocessing.

### Sync runs show as `failed` but only some records errored

That's expected: a run is only marked failed when **every** record fails. With
mixed outcomes the run stays `completed` and the per-record failures appear in
the dead-letter queue and `SyncRecordTracking`.

### `LegacyRepo` won't start

The repo is started on demand by the workers/CLI. If it fails, check the four
`MSSQL_*` env vars, network/firewall access to the MSSQL host, and that the
credentials have at least `SELECT` on the four views.

---

## Module Reference

| File | Role |
|---|---|
| `lib/kiroku/sync/importer.ex` | **Core** — `run_view/2`, `run_single/3`, field mapping, bitstream creation |
| `lib/kiroku/sync.ex` | Sync run lifecycle, change detection, checksums, record tracking |
| `lib/kiroku/sync/sync_run.ex` | `SyncRun` schema (per-view-per-run aggregate) |
| `lib/kiroku/sync/sync_record_tracking.ex` | `SyncRecordTracking` schema (per-record outcome + checksum) |
| `lib/kiroku/sync/dead_letter_queue.ex` | `DeadLetterQueue` schema (repeated-failure records) |
| `lib/kiroku/workers/mssql_sync_worker.ex` | Incremental sync Oban worker |
| `lib/kiroku/workers/import_worker.ex` | Full import Oban worker |
| `lib/kiroku/workers/sync_retry_worker.ex` | Dead-letter retry worker |
| `lib/mix/tasks/import_from_mssql.ex` | CLI task (`mix kiroku.import_from_mssql`) |
| `lib/kiroku/legacy_thesis.ex` | `LegacyView` read-only MSSQL schema |
| `lib/kiroku/legacy_repo.ex` | Read-only Ecto repo for MSSQL |
| `lib/kiroku_web/live/admin_sync_live.ex` | Admin dashboard LiveView |
| `lib/kiroku_web/controllers/bitstream_controller.ex` | Serves `:url` bitstreams via redirect |
| `config/config.exs` | Oban queues + cron schedule |
| `config/runtime.exs` / `config/dev.exs` | MSSQL connection env vars |
