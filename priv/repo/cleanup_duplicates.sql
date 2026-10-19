-- cleanup_duplicates.sql
-- Run inside the container:
--   podman exec -i kiroku_app psql -U postgres -d kiroku_prod < /dev/stdin < cleanup_duplicates.sql
--
-- Or dry-run first:
--   podman exec -i kiroku_app psql -U postgres -d kiroku_prod -c "SELECT count(*) FROM bitstreams" 

BEGIN;

-- 1. Duplicate bitstreams: keep newest per (item_id, filename), delete rest
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY item_id, filename ORDER BY inserted_at DESC) AS rn
  FROM bitstreams
)
DELETE FROM bitstreams WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 2. Duplicate sync_record_tracking: keep newest per legacy_id, delete rest
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY legacy_id ORDER BY synced_at DESC) AS rn
  FROM sync_record_tracking
)
DELETE FROM sync_record_tracking WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 3. Reset sync stats so the dashboard shows accurate numbers after re-sync
-- (uncomment if you want a clean slate)
-- DELETE FROM sync_record_tracking;
-- DELETE FROM sync_runs;

COMMIT;

-- Verify
SELECT 'bitstreams' AS table_name, count(*) AS total FROM bitstreams
UNION ALL
SELECT 'items', count(*) FROM items
UNION ALL
SELECT 'sync_record_tracking', count(*) FROM sync_record_tracking;
