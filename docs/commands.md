# Kiroku Mix Tasks Reference

## Database & Sync

### `mix kiroku.import_from_mssql`

Full import of all legacy thesis records from MSSQL into PostgreSQL. Use for initial setup or full re-import.

```bash
# Local
mix kiroku.import_from_mssql

# Production
podman exec kiroku_app mix kiroku.import_from_mssql
```

### `mix kiroku.reset_empty_titles`

Resets sync tracking for items with empty titles or null abstracts, so the next incremental sync re-fetches them from MSSQL. Safe to run locally — only touches PostgreSQL.

```bash
# Local
mix kiroku.reset_empty_titles --dry-run
mix kiroku.reset_empty_titles

# Production
podman exec kiroku_app mix kiroku.reset_empty_titles --dry-run
podman exec kiroku_app mix kiroku.reset_empty_titles
```

### `mix kiroku.refetch_empty_titles`

Re-fetches items with empty titles directly from MSSQL. Requires MSSQL access — use in production or locally with MSSQL configured.

```bash
# Local (if MSSQL configured)
mix kiroku.refetch_empty_titles --dry-run
mix kiroku.refetch_empty_titles

# Production
podman exec kiroku_app mix kiroku.refetch_empty_titles --dry-run
podman exec kiroku_app mix kiroku.refetch_empty_titles
```

### `mix kiroku.cleanup_duplicates`

Removes duplicate bitstreams (same item_id + filename) and duplicate sync_record_tracking entries.

```bash
# Local
mix kiroku.cleanup_duplicates --dry-run
mix kiroku.cleanup_duplicates

# Production
podman exec kiroku_app mix kiroku.cleanup_duplicates --dry-run
podman exec kiroku_app mix kiroku.cleanup_duplicates
```

## Database Access

### PostgreSQL shell

```bash
# Local
psql -U postgres -d kiroku_dev

# Production
podman exec -it kiroku_app psql -U postgres -d kiroku_prod
```

### Quick queries

```bash
# Count items by type
psql -d kiroku_dev -c "SELECT item_type, count(*) FROM items GROUP BY item_type ORDER BY count DESC;"

# Count items with empty title
psql -d kiroku_dev -c "SELECT count(*) FROM items WHERE title = 'Empty Title';"

# Check sync run status
psql -d kiroku_dev -c "SELECT id, view_name, status, records_processed, records_inserted, records_updated, records_skipped, started_at, completed_at FROM sync_runs ORDER BY started_at DESC LIMIT 10;"

# Force-stop a stale sync
podman exec kiroku_app psql -U postgres -d kiroku_prod -c "UPDATE sync_runs SET status = 'failed', completed_at = now(), error_message = 'Force stopped' WHERE status = 'running';"
```

## SAF (Simple Archive Format)

### `mix kiroku.saf.export`

Export items/collections to DSpace Simple Archive Format.

```bash
# Local
mix kiroku.saf.export

# Production
podman exec kiroku_app mix kiroku.saf.export
```

### `mix kiroku.saf.import`

Import items from a DSpace Simple Archive Format archive.

```bash
# Local
mix kiroku.saf.import

# Production
podman exec kiroku_app mix kiroku.saf.import
```

## Deployment

### Build and deploy

```bash
bin/deploy              # Deploy without migrations
bin/deploy --migrate    # Deploy with migrations
```

## Assets

### `mix assets.build`

Alias for `compile`, `tailwind kiroku`, `esbuild kiroku`.

```bash
mix assets.build
```

### `mix assets.deploy`

Minify Tailwind + esbuild, generate digest hashes for production.

```bash
mix assets.deploy
```
