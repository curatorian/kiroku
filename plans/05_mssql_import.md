# MSSQL Legacy Import

## Kiroku — `mix import_from_mssql` Implementation Guide

---

## 0. Overview

The legacy database (`tbtMhsUploadThesis` on MSSQL) is read **once** during import and never
touched again. Every row becomes one `Item` + associated `Bitstream` rows in the Kiroku
PostgreSQL database. The `LegacyRepo` is started only inside the Mix task — it is not in the
application supervision tree.

**Rule: `LegacyRepo` is read-only, forever. Never write to it.**

---

## 1. `LegacyThesis` Ecto Schema

The MSSQL table name is `tbtMhsUploadThesis`. Map every column exactly as it exists:

```elixir
# lib/kiroku/legacy_thesis.ex
defmodule Kiroku.LegacyThesis do
  use Ecto.Schema

  # No primary key module attribute — use the default integer :id
  # MSSQL tables typically have an integer PK; IDControl is our reference
  @primary_key false

  schema "tbtMhsUploadThesis" do
    field :IDControl,      :integer,  primary_key: true
    field :MhsNPM,         :string    # Student NIM/NPM
    field :LinkPath,       :string    # Base URL of legacy file server (e.g. "http://repo.univ.ac.id/files")
    field :FileCover,      :string    # Relative path to cover image
    field :FileAbstrak,    :string    # Relative path to abstract PDF
    field :FileDaftarIsi,  :string    # Relative path to table of contents PDF
    field :FileBab1,       :string    # Chapter 1 PDF
    field :FileBab2,       :string    # Chapter 2 PDF
    field :FileBab3,       :string    # Chapter 3 PDF
    field :FileBab4,       :string    # Chapter 4 PDF
    field :FileBab5,       :string    # Chapter 5 PDF
    field :FileBab6,       :string    # Chapter 6 PDF (if exists)
    field :FileLampiran,   :string    # Appendix PDF
    field :FilePustaka,    :string    # Bibliography PDF
    field :FileSurat,      :string    # Submission/cover letter PDF
    field :FileSuratIsi,   :string    # Signed submission form / content of letter
    field :FilePengesahan, :string    # Lembar pengesahan (approval letter PDF)
    field :FilePresentasi, :string    # Defense presentation slides
    field :FileFullText,   :string    # Full text PDF (single file)
    field :Judul,          :string    # Title in Indonesian
    field :Abstrak,        :string    # Abstract in Indonesian
    field :Bahasa,         :string    # Language ("Indonesia", "English", "Inggris")
    field :Keywords,       :string    # Semicolon or comma-separated keywords
    field :UploadTgl,      :utc_datetime  # Upload/submission date
    field :idpustaka,      :string    # Legacy handle/identifier (e.g. "123456789/42")
    field :TagPustaka,     :string    # Library classification tag / call number
    field :stPublikasi,    :integer   # Publication status: 0=draft, 1=active
    field :Verifikasi,     :integer   # Librarian verification: 0=no, 1=yes
    field :Validasi,       :integer   # Advisor/admin validation: 0=no, 1=yes
    field :JudulBersih,    :string    # Cleaned title (stripped formatting)
    field :AbstrakBersih,  :string    # Cleaned abstract
    field :EmbargoDate,    :date      # Embargo end date (nil = no embargo)
    field :DataAge,        :integer   # Computed freshness indicator — not imported
  end
end
```

---

## 2. Field Mapping — MSSQL → Kiroku

### 2.1 `Item` Columns

| MSSQL Column                              | Kiroku `Item` Field      | Transform                                                              |
| ----------------------------------------- | ------------------------ | ---------------------------------------------------------------------- |
| `IDControl`                               | `legacy_id`              | Stored as `legacy_id`; used as `conflict_target` for idempotent upsert |
| `MhsNPM`                                  | `student_id`             | Direct string copy                                                     |
| `Judul`                                   | `title`                  | Prefer `JudulBersih` if non-empty, fallback to `Judul`                 |
| `JudulBersih`                             | `title`                  | Preferred over `Judul` if present                                      |
| `Abstrak`                                 | `abstract`               | Prefer `AbstrakBersih` if non-empty                                    |
| `AbstrakBersih`                           | `abstract`               | Preferred over `Abstrak` if present                                    |
| `Bahasa`                                  | `language`               | Map via `map_language/1` → `:id` or `:en`                              |
| `UploadTgl`                               | `date_submitted`         | Cast to `Date.t()`                                                     |
| `idpustaka`                               | `idpustaka` + `handle`   | Used directly as `handle` if valid format                              |
| `TagPustaka`                              | `subject_classification` | Direct string copy                                                     |
| `stPublikasi` + `Verifikasi` + `Validasi` | `status`                 | Map via `map_status/3`                                                 |
| `EmbargoDate`                             | `embargo_open_date`      | Direct date copy; nil if null                                          |
| `LinkPath`                                | `base_url`               | Stored for reference — used to construct bitstream URLs                |
| —                                         | `item_type`              | Always `:skripsi` (all legacy records are theses)                      |
| —                                         | `institution`            | Set from app config: `Application.get_env(:kiroku, :institution_name)` |

> **`DataAge`** — do not import. It is a computed column.

### 2.2 Language Mapping

```elixir
defp map_language("Indonesia"),   do: :id
defp map_language("Indonesian"),  do: :id
defp map_language("English"),     do: :en
defp map_language("Inggris"),     do: :en
defp map_language(nil),           do: :id
defp map_language(_),             do: :id   # default for unknown values
```

### 2.3 Status Mapping

```elixir
# stPublikasi: 1 = active/published, 0 = draft/inactive
# Verifikasi:  1 = verified by librarian, 0 = not yet
# Validasi:    1 = validated by admin, 0 = not yet

defp map_status(1, 1, 1),  do: :published     # fully approved and public
defp map_status(1, 1, 0),  do: :under_review  # verified but not yet validated
defp map_status(1, 0, _),  do: :submitted     # uploaded but not yet verified
defp map_status(0, _, _),  do: :submitted     # inactive / draft
defp map_status(_, _, _),  do: :submitted     # default fallback
```

### 2.4 Handle Generation

```elixir
defp build_handle(nil, control_id),  do: "123456789/legacy-#{control_id}"
defp build_handle("", control_id),   do: "123456789/legacy-#{control_id}"
defp build_handle(idpustaka, _),     do: idpustaka
```

The prefix `"123456789"` is the legacy DSpace handle prefix. Adjust to match your
institution's actual handle server prefix.

### 2.5 Keyword Parsing

```elixir
defp parse_keywords(nil), do: []
defp parse_keywords(""),  do: []
defp parse_keywords(raw) do
  raw
  |> String.split(~r/[;,]/)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()
  |> Enum.take(10)  # cap at 10 keywords for safety
end
```

---

## 3. Bitstream Mapping — File Columns

Each non-nil file column creates one `Bitstream` row. The full URL is:
`String.trim_trailing(link_path, "/") <> "/" <> String.trim_leading(file_col, "/")`

| MSSQL File Column | Bundle            | Sequence | `access_level` | Notes                                             |
| ----------------- | ----------------- | -------- | -------------- | ------------------------------------------------- |
| `FileCover`       | `:THUMBNAIL`      | 1        | `:open`        | Cover image — always open                         |
| `FileAbstrak`     | `:ORIGINAL`       | 1        | `:inherit`     | Abstract — NOT embargoed even if item has embargo |
| `FileFullText`    | `:ORIGINAL`       | 2        | `:inherit`     | Full text; subject to embargo                     |
| `FileBab1`        | `:CHAPTER`        | 1        | `:inherit`     | Chapter 1 — subject to embargo                    |
| `FileBab2`        | `:CHAPTER`        | 2        | `:inherit`     | Chapter 2                                         |
| `FileBab3`        | `:CHAPTER`        | 3        | `:inherit`     | Chapter 3                                         |
| `FileBab4`        | `:CHAPTER`        | 4        | `:inherit`     | Chapter 4                                         |
| `FileBab5`        | `:CHAPTER`        | 5        | `:inherit`     | Chapter 5                                         |
| `FileBab6`        | `:CHAPTER`        | 6        | `:inherit`     | Chapter 6 (skip if nil)                           |
| `FileDaftarIsi`   | `:SUPPLEMENTAL`   | 1        | `:inherit`     | Table of contents                                 |
| `FilePustaka`     | `:SUPPLEMENTAL`   | 2        | `:inherit`     | Bibliography                                      |
| `FileLampiran`    | `:SUPPLEMENTAL`   | 3        | `:inherit`     | Appendices                                        |
| `FilePresentasi`  | `:SUPPLEMENTAL`   | 4        | `:inherit`     | Defense slides                                    |
| `FilePengesahan`  | `:ADMINISTRATIVE` | 1        | `:restricted`  | Lembar pengesahan — always restricted             |
| `FileSurat`       | `:ADMINISTRATIVE` | 2        | `:restricted`  | Submission letter — always restricted             |
| `FileSuratIsi`    | `:ADMINISTRATIVE` | 3        | `:restricted`  | Signed submission form — always restricted        |

> **Note**: `Bitstream.changeset/2` automatically enforces `:open` for `:THUMBNAIL` and
> `:restricted` for `:ADMINISTRATIVE` and `:LICENSE`, regardless of the value passed in attrs.

---

## 4. Mix Task Implementation

```elixir
# lib/mix/tasks/import_from_mssql.ex
defmodule Mix.Tasks.ImportFromMssql do
  use Mix.Task

  import Ecto.Query
  require Logger

  alias Kiroku.{Repo, LegacyRepo, Repository}
  alias Kiroku.LegacyThesis
  alias Kiroku.Content

  @shortdoc "Imports legacy theses from MSSQL into Kiroku PostgreSQL"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    # Start LegacyRepo explicitly — it is NOT in the application supervision tree
    {:ok, _} = LegacyRepo.start_link([])

    opts = parse_opts(args)
    batch_size = Keyword.get(opts, :batch_size, 100)
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run, do: Logger.info("DRY RUN — no database writes will occur")

    total = LegacyRepo.one(from t in LegacyThesis, select: count(t.IDControl))
    Logger.info("Found #{total} legacy theses to import")

    results = import_all(batch_size, dry_run)

    Logger.info("""
    Import complete.
      Inserted:  #{results.inserted}
      Updated:   #{results.updated}
      Skipped:   #{results.skipped}
      Errors:    #{results.errors}
    """)
  end

  defp import_all(batch_size, dry_run) do
    accumulator = %{inserted: 0, updated: 0, skipped: 0, errors: 0}

    LegacyRepo.transaction(fn ->
      from(t in LegacyThesis, order_by: t.IDControl)
      |> LegacyRepo.stream(max_rows: batch_size)
      |> Stream.chunk_every(batch_size)
      |> Enum.reduce(accumulator, fn chunk, acc ->
        Enum.reduce(chunk, acc, fn record, inner_acc ->
          case import_record(record, dry_run) do
            {:ok, :inserted} -> Map.update!(inner_acc, :inserted, &(&1 + 1))
            {:ok, :updated}  -> Map.update!(inner_acc, :updated,  &(&1 + 1))
            {:ok, :skipped}  -> Map.update!(inner_acc, :skipped,  &(&1 + 1))
            {:error, reason} ->
              Logger.error("Failed IDControl=#{record.IDControl}: #{inspect(reason)}")
              Map.update!(inner_acc, :errors, &(&1 + 1))
          end
        end)
      end)
    end, timeout: :infinity)
    |> case do
      {:ok, results} -> results
      {:error, reason} ->
        Logger.error("Transaction failed: #{inspect(reason)}")
        accumulator
    end
  end

  defp import_record(record, dry_run) do
    attrs = build_item_attrs(record)
    handle = attrs[:handle]

    # Skip records with no title
    if is_nil(attrs[:title]) or attrs[:title] == "" do
      {:ok, :skipped}
    else
      if dry_run do
        Logger.debug("DRY RUN: would import handle=#{handle}, title=#{attrs[:title]}")
        {:ok, :skipped}
      else
        case Repository.import_item(attrs) do
          {:ok, item} ->
            create_bitstreams_for_record(item, record)
            create_keywords_for_record(item, record)
            {:ok, :inserted}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # ── Item attrs builder ─────────────────────────────────────────────────────

  defp build_item_attrs(r) do
    title    = prefer_clean(r.JudulBersih, r.Judul)
    abstract = prefer_clean(r.AbstrakBersih, r.Abstrak)
    status   = map_status(r.stPublikasi, r.Verifikasi, r.Validasi)
    handle   = build_handle(r.idpustaka, r.IDControl)

    %{
      handle:              handle,
      idpustaka:           r.idpustaka,
      title:               title,
      abstract:            abstract,
      language:            map_language(r.Bahasa),
      student_id:          r.MhsNPM,
      date_submitted:      date_from_datetime(r.UploadTgl),
      subject_classification: r.TagPustaka,
      item_type:           :skripsi,
      status:              status,
      discoverable:        status == :published,
      access_level:        :open,
      embargo_open_date:   r.EmbargoDate,
      base_url:            r.LinkPath,
      institution:         institution_name(),
      # collection_id is nil for import — assign later via admin UI or a second pass
      collection_id:       nil
    }
  end

  # ── Bitstream creator ──────────────────────────────────────────────────────

  defp create_bitstreams_for_record(item, r) do
    link_path = r.LinkPath

    file_map = [
      {r.FileCover,      :THUMBNAIL,      1, :open},
      {r.FileAbstrak,    :ORIGINAL,       1, :inherit},
      {r.FileFullText,   :ORIGINAL,       2, :inherit},
      {r.FileBab1,       :CHAPTER,        1, :inherit},
      {r.FileBab2,       :CHAPTER,        2, :inherit},
      {r.FileBab3,       :CHAPTER,        3, :inherit},
      {r.FileBab4,       :CHAPTER,        4, :inherit},
      {r.FileBab5,       :CHAPTER,        5, :inherit},
      {r.FileBab6,       :CHAPTER,        6, :inherit},
      {r.FileDaftarIsi,  :SUPPLEMENTAL,   1, :inherit},
      {r.FilePustaka,    :SUPPLEMENTAL,   2, :inherit},
      {r.FileLampiran,   :SUPPLEMENTAL,   3, :inherit},
      {r.FilePresentasi, :SUPPLEMENTAL,   4, :inherit},
      {r.FilePengesahan, :ADMINISTRATIVE, 1, :restricted},
      {r.FileSurat,      :ADMINISTRATIVE, 2, :restricted},
      {r.FileSuratIsi,   :ADMINISTRATIVE, 3, :restricted},
    ]

    Enum.each(file_map, fn {file_col, bundle, seq, access} ->
      if not is_nil(file_col) and file_col != "" do
        full_url = build_file_url(link_path, file_col)

        attrs = %{
          item_id:      item.id,
          filename:     Path.basename(file_col),
          bundle_name:  bundle,
          sequence:     seq,
          description:  legacy_file_description(bundle, seq),
          storage_type: :url,
          storage_url:  full_url,
          access_level: access,
          embargo_open_date: item.embargo_open_date
        }

        case Content.create_bitstream(attrs) do
          {:ok, _} -> :ok
          {:error, reason} ->
            Logger.warning("Bitstream failed for item #{item.id} #{bundle}/#{seq}: #{inspect(reason)}")
        end
      end
    end)
  end

  # ── Keyword creator ────────────────────────────────────────────────────────

  defp create_keywords_for_record(item, r) do
    keywords = parse_keywords(r.Keywords)

    keywords
    |> Enum.with_index(0)
    |> Enum.each(fn {kw, idx} ->
      Repo.insert!(%Kiroku.Repository.ItemKeyword{
        item_id:  item.id,
        keyword:  kw,
        language: :id,
        position: idx
      }, on_conflict: :nothing)
    end)
  end

  # ── Helper functions ───────────────────────────────────────────────────────

  defp prefer_clean(nil, fallback), do: fallback
  defp prefer_clean("", fallback),  do: fallback
  defp prefer_clean(clean, _),      do: clean

  defp build_file_url(nil, file_col),  do: file_col
  defp build_file_url("", file_col),   do: file_col
  defp build_file_url(base, file_col) do
    base = String.trim_trailing(base, "/")
    file = String.trim_leading(file_col, "/")
    "#{base}/#{file}"
  end

  defp date_from_datetime(nil),  do: nil
  defp date_from_datetime(dt),   do: DateTime.to_date(dt)

  defp map_language("Indonesia"),   do: :id
  defp map_language("Indonesian"),  do: :id
  defp map_language("English"),     do: :en
  defp map_language("Inggris"),     do: :en
  defp map_language(_),             do: :id

  defp map_status(1, 1, 1), do: :published
  defp map_status(1, 1, _), do: :under_review
  defp map_status(1, _, _), do: :submitted
  defp map_status(_, _, _), do: :submitted

  defp build_handle(nil, id),  do: "123456789/legacy-#{id}"
  defp build_handle("", id),   do: "123456789/legacy-#{id}"
  defp build_handle(h, _),     do: h

  defp parse_keywords(nil), do: []
  defp parse_keywords(""),  do: []
  defp parse_keywords(raw) do
    raw
    |> String.split(~r/[;,]/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp legacy_file_description(:THUMBNAIL, _),      do: "Cover image"
  defp legacy_file_description(:ORIGINAL, 1),       do: "Abstract"
  defp legacy_file_description(:ORIGINAL, _),       do: "Full text"
  defp legacy_file_description(:CHAPTER, seq),      do: "Bab #{seq}"
  defp legacy_file_description(:SUPPLEMENTAL, 1),   do: "Daftar isi"
  defp legacy_file_description(:SUPPLEMENTAL, 2),   do: "Daftar pustaka"
  defp legacy_file_description(:SUPPLEMENTAL, 3),   do: "Lampiran"
  defp legacy_file_description(:SUPPLEMENTAL, 4),   do: "Presentasi sidang"
  defp legacy_file_description(:ADMINISTRATIVE, 1), do: "Lembar pengesahan"
  defp legacy_file_description(:ADMINISTRATIVE, 2), do: "Surat pengantar"
  defp legacy_file_description(:ADMINISTRATIVE, 3), do: "Surat pengantar (isi)"
  defp legacy_file_description(_, _),               do: "Document"

  defp institution_name do
    Application.get_env(:kiroku, :institution_name, "Universitas")
  end

  defp parse_opts(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [batch_size: :integer, dry_run: :boolean])
    opts
  end
end
```

---

## 5. Configuration

```elixir
# config/config.exs
config :kiroku, :institution_name, "Universitas Indonesia"   # adjust as needed
```

---

## 6. Schema Requirement: `import_changeset/2` on `Item`

The `Item` schema needs `import_changeset/2` that doesn't require `collection_id` (already defined in plan 01):

```elixir
# Existing in lib/kiroku/repository/item.ex — confirm it is present:
def import_changeset(item, attrs) do
  item
  |> cast(attrs, @required_fields ++ @optional_fields)
  |> validate_required([:title])
  |> unique_constraint(:handle)
end
```

And `Repository.import_item/1` uses upsert:

```elixir
# Existing in lib/kiroku/repository.ex — confirm it is present:
def import_item(attrs) do
  %Item{}
  |> Item.import_changeset(attrs)
  |> Repo.insert(
    on_conflict: {:replace_all_except, [:id, :inserted_at]},
    conflict_target: :legacy_id
  )
end
```

---

## 7. Running the Import

### One-time full import:

```bash
MSSQL_HOST=your-mssql-host MSSQL_DB=your-db MSSQL_USER=sa MSSQL_PASS=secret \
  mix import_from_mssql
```

### Dry run (no writes):

```bash
mix import_from_mssql --dry-run
```

### Custom batch size:

```bash
mix import_from_mssql --batch-size 500
```

### After import — assign collections:

Many imported items will have `collection_id: nil`. Use the admin panel
(`/admin/items`) to bulk-assign them to collections based on `faculty` / `department` / `program_study`.
Alternatively, write a second mix task that reads `TagPustaka` or `faculty` and
looks up or creates the matching collection.

---

## 8. Important Constraints

1. **Never run in production without a backup first.**
2. **The import is idempotent** — re-running it upserts on `handle`. Safe to run again after fixing bugs.
3. **Bitstreams are duplicated on re-run** — they use `insert`, not upsert. Truncate `bitstreams` where `item_id IN (select id from items where base_url IS NOT NULL)` before re-running if needed.
4. **File URLs from `LinkPath` + file columns must be publicly reachable** or the files remain inaccessible until migrated to S3.
5. **`embargo_open_date` on `Bitstream` rows** is copied from the item's embargo date at import time. If the item is later re-embargoed or embargo is lifted, update bitstreams accordingly.
