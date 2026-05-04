# Agent Briefing — Kiroku Institutional Repository

## Read This Entire File Before Reading Any Other Document

---

## 0. What You Are Building

You are building **Kiroku** — a lean institutional repository (DSpace / EPrints replacement) for an Indonesian university. It stores academic works (theses, journal articles, creative works, etc.) submitted by students and staff.

The design goal is **efficient, lean, stable, and reliable**. No heavy abstraction layers. Straightforward Phoenix + Ecto patterns that any Elixir developer can read and maintain.

The stack is:

- **Elixir + Phoenix 1.8** (web framework — LiveView for all interactive UI)
- **Ecto + PostgreSQL** (plain Ecto schemas and contexts, no ORM abstraction layer)
- **phx_gen_auth** (authentication — sessions and token-based password reset)
- **Oban** (plain background jobs — embargo lifting, email delivery)
- **Custom REST + OAI-PMH controllers** (hand-written, DSpace 7 compatible)
- **Plain Ecto + TDS** (MSSQL — legacy read-only import only, never the primary database)

The legacy database (`tbtMhsUploadThesis` on MSSQL) is **never migrated or replaced**. It is read once during the import task, then left untouched forever.

---

## 1. Document Reading Order

Read the plan documents in this exact order:

**Step 1 →** `01_institutional_repository.md`
Architecture document. Defines the project structure, all Ecto schemas, context modules, authentication, routing, controllers, LiveViews, background workers, and the import task. Establish your full mental model of the system from this document before writing any code.

**Step 2 →** `02_metadata_and_files.md`
Field and file reference. Defines what data each of the 10 item types collects (metadata fields) and what files each type uploads (bitstreams). Use this to extend the `Item` schema columns, add `ItemExaminer` and `ItemTeamMember` schemas, and configure field visibility in the submission UI.

Do not start writing any code until you have read both documents in full.

---

## 2. The Phoenix + Ecto Mental Model

This project uses **plain Phoenix contexts and Ecto schemas**. There is no framework abstraction layer over Ecto.

| Pattern              | Implementation                                        |
| -------------------- | ----------------------------------------------------- |
| Schema module        | `Ecto.Schema` with `schema "table_name" do`           |
| Data operations      | Context module functions calling `Repo.*`             |
| Validation           | `Ecto.Changeset` inside schema changesets             |
| DB schema changes    | `mix ecto.gen.migration describe_what_changed`        |
| Query building       | `Ecto.Query` (`from`, `where`, `join`, `select`)      |
| Authorization        | `Kiroku.Access.Authorization.can?/3` helper           |
| Auth (user sessions) | `phx_gen_auth`-style `UserAuth` plug + session tokens |
| Background jobs      | Plain `Oban.Worker` modules                           |
| Admin panel          | Hand-written admin LiveViews under `/admin`           |
| REST API             | Hand-written Phoenix controllers under `/api/v1`      |

When in doubt, reach for the simplest Ecto/Phoenix approach first.

---

## 3. Hard Rules — Never Violate These

**Rule 1: Migrations are written by hand with `mix ecto.gen.migration`.**
After every schema change (new column, new table, new index), generate a migration:

```bash
mix ecto.gen.migration describe_what_changed
```

Edit the generated file, then run `mix ecto.migrate`. Keep migrations minimal and reversible where possible.

**Rule 2: `LegacyRepo` is read-only, plain Ecto, forever.**
`Kiroku.LegacyRepo` is a plain `Ecto.Repo` with the TDS (MSSQL) adapter. `Kiroku.LegacyThesis` is a plain `Ecto.Schema`. Neither is ever written to or converted to the primary PostgreSQL schema. The import task reads from it exactly once and then is done.

**Rule 3: The `file_abstract` bitstream is never embargoed.**
The abstract PDF (`bundle: :ORIGINAL`, `sequence: 1`) must never be blocked by embargo logic even when the item's full text is embargoed. Enforce this in `BitstreamController` and `EmbargoLifterWorker` by checking `sequence == 1` before applying restrictions.

**Rule 4: `THUMBNAIL` bundle is always `:open`.**
Cover images (`bundle: :THUMBNAIL`) must always have `access_level: :open`. Never set them to `:inherit`, `:restricted`, or `:closed`. Enforce this in the `Bitstream` changeset and in the submission wizard.

**Rule 5: `ADMINISTRATIVE` and `LICENSE` bundles are always `:restricted`.**
Approval letters, originality statements, acceptance letters, ethics approvals, NDA documents, indexing proofs, and all administrative files must always have `access_level: :restricted`. This is hardcoded in the `Bitstream` changeset — it does not inherit from the item and cannot be changed in the UI.

**Rule 6: Authorization checks happen in LiveViews and controllers — not in context functions.**
Context functions are pure data operations. They do not check user permissions. Authorization is always done by calling `Kiroku.Access.Authorization.can?/3` in the LiveView `handle_event`, or in a `plug` in controllers, before calling any context function.

---

## 4. Ecto + Context Patterns — Use These Exactly

```elixir
# Read single record by primary key
Repo.get!(Item, id)
Repo.get(Item, id)  # returns nil instead of raising

# Read by unique field
Repo.get_by!(Item, handle: "123456789/42")
Repo.get_by(Item, handle: "123456789/42")

# Read with preloads
item = Repo.get!(Item, id) |> Repo.preload([:item_keywords, :item_authors, :bitstreams])

# Read list via context
Repository.list_published_items()
Repository.search_items(%{term: "neural", department: "0410", page: 1})

# Create via context (returns {:ok, record} | {:error, changeset})
Repository.create_item(attrs)

# Update via context
Repository.update_item(item, attrs)

# Delete via context
Repository.delete_item(item)

# Authorization check in LiveView / controller
if Authorization.can?(current_user, :publish_item, item) do
  Repository.publish_item(item)
else
  {:error, :unauthorized}
end

# Phoenix form (standard Ecto-based forms)
changeset = Item.changeset(%Item{}, %{})
form = to_form(changeset, as: "item")
```

---

## 5. Context Module Structure

There are 5 context modules. Every schema belongs to exactly one context.

```
Kiroku.Repository   → Community, Collection, Item,
                       ItemKeyword, ItemAuthor, ItemAdvisor,
                       ItemExaminer, ItemTeamMember, ItemMetadata

Kiroku.Accounts     → User, UserToken

Kiroku.Content      → Bitstream

Kiroku.Access       → RbacPolicy, Authorization

Kiroku.Analytics    → ViewEvent
```

`ItemExaminer` and `ItemTeamMember` are new schemas not present in the original legacy codebase. They must be created from scratch. Full schema definition is in `02_metadata_and_files.md` Section 14.

---

## 6. The 10 Item Types

The `item_type` field on `Item` uses `Ecto.Enum` with these values:

```
:skripsi              → S1/S2/S3 academic thesis
:memorandum_hukum     → Legal memorandum (Fakultas Hukum)
:studi_kasus          → Case study (Bisnis/Kedokteran/Psikologi/Hukum)
:laporan_proyek       → Project report (Teknik/Vokasi/Arsitektur)
:karya_kreatif        → Creative work (Seni/Desain/Sastra/Musik/Film)
:karya_teknologi      → Technological work (Informatika/Teknik Terapan)
:jurnal_nasional      → Sinta-accredited national journal article
:jurnal_internasional → Scopus/WoS international journal article
:prosiding            → International conference proceedings
:capstone             → Capstone / MBKM project
```

Field visibility in the submission UI is driven by `item_type`. The helper module `KirokuWeb.Live.Helpers.FieldVisibility` handles this — see `02_metadata_and_files.md` Section 15.

---

## 7. Bitstream (File) Rules Summary

Every uploaded file = one row in the `bitstreams` table.

| Bundle           | Default `access_level` | Override allowed?          |
| ---------------- | ---------------------- | -------------------------- |
| `ORIGINAL`       | `:inherit`             | Yes                        |
| `THUMBNAIL`      | `:open`                | **No — always open**       |
| `CHAPTER`        | `:inherit`             | Yes                        |
| `SUPPLEMENTAL`   | `:inherit`             | Yes                        |
| `ADMINISTRATIVE` | `:restricted`          | **No — always restricted** |
| `LICENSE`        | `:restricted`          | **No — always restricted** |
| `MEDIA`          | `:inherit`             | Yes                        |
| `SOURCE`         | `:inherit`             | Yes                        |

The `file_abstract` (`bundle: :ORIGINAL`, `sequence: 1`) is the one `ORIGINAL` file that is **never embargoed**, even when the item has an active `embargo_open_date`.

---

## 8. Authentication & Authorization

**Authentication** is handled by `phx_gen_auth`-style session tokens. The `UserAuth` plug manages session loading and enforcement. Passwords are hashed with `Bcrypt`. Sign-in, registration, and password-reset routes are standard Phoenix routes under `KirokuWeb.Router`.

**Authorization** has two layers that must not be confused:

Layer 1 — **`Kiroku.Access.Authorization.can?/3`**: Called in LiveViews (`handle_event`) and controller plugs before any context function is invoked. Returns `true` or `false` based on the current user's `user_type` and the item/bitstream being accessed.

Layer 2 — **`RbacPolicy` Ecto schema**: Dynamic grants stored in the `rbac_policies` table. Queried by `Authorization.can?/3` for fine-grained item/bitstream access decisions (e.g. a restricted item that has been explicitly granted to a specific user). Managed by `Kiroku.Access.PolicyManager.apply_access_level/2`.

**User types** (`:member`, `:submitter`, `:reviewer`, `:admin`, `:superadmin`) are the primary axis for authorization decisions. Checks are plain `case` or `cond` expressions in `Authorization` — no DSL.

---

## 9. Migration Workflow — Every Time

Follow this exact sequence after any schema change:

```bash
# 1. Generate migration
mix ecto.gen.migration describe_what_changed

# 2. Edit the generated file in priv/repo/migrations/
#    Add the columns, tables, indexes, or constraints manually.

# 3. Apply
mix ecto.migrate

# 4. If seeds need to run (first time or new reference data added)
mix run priv/repo/seeds.exs
```

Never skip step 2. Migrations are written by hand — they do exactly what you write and nothing more.

---

## 10. Import Task Behaviour

The `mix kiroku.import_from_mssql` task reads from `Kiroku.LegacyRepo` (plain Ecto, MSSQL/TDS adapter) and writes to PostgreSQL using plain context functions.

Key behaviours:

- Calls internal context functions directly — no authorization check needed (this is a trusted system task, not a user action)
- Uses `Repository.import_item/1`, `Content.import_bitstream/1`, etc. — dedicated import-flavoured context functions that skip embargo enforcement and other submission-wizard logic
- Skips already-imported items by checking `legacy_id` against existing records with `Repo.get_by(Item, legacy_id: id)`
- Calls `PolicyManager.apply_access_level(item, :open)` after each item is persisted
- All enum values from the legacy table (raw strings like `"Indonesia"`, `"published"`) are mapped to atoms before calling any changeset

Import context functions must `cast` all fields that the import task writes. If a field is missing from the changeset's `cast` list, it is silently ignored and the data is lost.

---

## 11. What Needs Atoms, What Needs Strings

`Ecto.Enum` fields store the atom's string representation in the database and cast back to atoms automatically. The legacy MSSQL data uses raw strings. The import task is responsible for all conversions before calling any changeset.

| Raw value in legacy data                   | Ecto atom                |
| ------------------------------------------ | ------------------------ |
| `"Indonesia"` / `"Indonesian"`             | `:id` (language)         |
| `"English"`                                | `:en` (language)         |
| `true` + `true` (stPublikasi + Verifikasi) | `:published` (status)    |
| `false` (stPublikasi)                      | `:withdrawn` (status)    |
| `false` (Verifikasi only)                  | `:under_review` (status) |
| `nil` / unknown                            | `:submitted` (status)    |
| `"url"` storage type                       | `:url`                   |
| `"s3"` storage type                        | `:s3`                    |
| `"ORIGINAL"` bundle                        | `:ORIGINAL`              |

`Ecto.Enum` will also accept the string form (e.g. `"published"`) in a changeset cast, but always prefer passing atoms from the import task to make intent explicit.

---

## 12. Common Mistakes to Avoid

- **Bypassing context functions and calling `Repo.*` directly in LiveViews or controllers.** All data operations go through context modules (`Repository.*`, `Content.*`, etc.). Direct `Repo.*` calls are only acceptable inside context module implementations and the import task.

- **Putting authorization logic inside context functions.** Context functions are pure data operations. Authorization is always done in the LiveView or controller before calling the context. Call `Authorization.can?/3` first — then call the context function.

- **Forgetting to add new fields to the import context function's `cast` list.** If a field is added to the `Item` schema but not included in `cast` in `Repository.import_item/1`, it will be silently ignored during import and the legacy data will be lost.

- **Generating one migration per schema change in the same session.** If you have pending changes across multiple schemas, write one migration that covers all of them. Do not generate a separate migration for each schema — keep the migration history clean.

- **Querying `Ecto.Enum` fields with raw strings.** Always use atoms in `Ecto.Query` `where` clauses: `where: i.status == :published`, not `== "published"`.

- **Putting supplementary/rare fields as columns on `items`.** If a field only applies to one or two item types and is rarely queried, it goes in `item_metadata_extras` as a `schema.element.qualifier` row, not as a column. The reference is `02_metadata_and_files.md` Section 14.

- **Allowing the admin panel to expose `ADMINISTRATIVE` or `LICENSE` bundle files.** The admin LiveView must never render a UI to change `access_level` on these bundles. Enforce this in the `Bitstream` changeset (hardcode the value) — do not rely solely on the UI.

---

## 13. Execution Checklist

When given a task, follow this sequence before writing a single line of code:

1. Identify which context module(s) and Ecto schema(s) are affected.
2. Identify whether you need a new field, a new association, a new schema, or a new context function.
3. If adding fields or a table → plan the migration that will follow.
4. If adding a schema → ensure `Item` has the corresponding `has_many` association and the context module exports the necessary CRUD functions.
5. Write the schema / changeset / context function change.
6. Run `mix ecto.gen.migration describe_your_change`.
7. Write the migration body (add_column, create table, add index, etc.).
8. Run `mix ecto.migrate`.
9. If the change affects the import task, update the import context function's `cast` list.
10. If the change affects the submission UI, update `FieldVisibility` and the form LiveView.
