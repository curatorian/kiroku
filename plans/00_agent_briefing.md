# Agent Briefing — Institutional Repository (Ash Framework)
## Read This Entire File Before Reading Any Other Document

---

## 0. What You Are Building

You are building an **institutional repository** — a DSpace replacement — for an Indonesian university. It stores academic works (theses, journal articles, creative works, etc.) submitted by students and staff.

The stack is:
- **Elixir + Phoenix** (web framework)
- **Ash Framework** (domain/resource layer — replaces plain Ecto contexts)
- **AshPostgres** (data layer — PostgreSQL as primary database)
- **AshAuthentication** (auth — replaces Guardian + phx_gen_auth)
- **AshAdmin** (admin panel — auto-generated, zero custom code needed)
- **AshJsonApi** (REST API — DSpace 7 compatible, auto-generated)
- **AshOban** (background jobs via Oban)
- **Plain Ecto + TDS** (MSSQL — legacy read-only import only, never touches Ash)

The legacy database (`tbtMhsUploadThesis` on MSSQL) is **never migrated or replaced**. It is read once during the import task, then left untouched forever.

---

## 1. Document Reading Order

You will be given two reference documents. Read them in this exact order:

**Step 1 →** `ash_institutional_repository.md`
This is the architecture document. It defines the project structure, all Ash domains, all Ash resources, authentication, routing, controllers, LiveViews, background workers, and the import task. Establish your full mental model of the system from this document before doing anything.

**Step 2 →** `05_metadata_and_files_ash_edition.md`
This is the field and file reference. It defines what data each of the 10 item types collects (metadata fields) and what files each type uploads (bitstreams). Use this to extend the `Item` resource attributes, add the new `ItemExaminer` and `ItemTeamMember` resources, and configure field visibility in the submission UI.

Do not start writing any code until you have read both documents in full.

---

## 2. The Single Most Important Mental Shift

**Ash is not Ecto with extra steps. It is a completely different model.**

| If you think of doing this... | Do this instead |
|-------------------------------|----------------|
| Write a context function | Define a named action inside the resource |
| `Repo.insert(changeset)` | `Ash.create!(Resource, attrs, actor: user)` |
| `Repo.get(Resource, id)` | `Ash.get!(Resource, id, actor: user)` |
| Write an `Ecto.Changeset` | Use `accept`, `validate`, `change` inside an action |
| Write a migration by hand | Run `mix ash.generate_migrations` |
| Add an `Ecto.Query` in a context | Use `Ash.Query.filter` / `Ash.Query.for_read` |
| Write an authorization function | Write a `policy` block inside the resource |
| Use Guardian for JWT | Use `AshAuthentication` — it is already configured |
| Build an admin LiveView | Add an `admin do` block to the resource — AshAdmin generates it |

When in doubt, look for the Ash way to do something before reaching for plain Elixir/Ecto/Phoenix patterns.

---

## 3. Hard Rules — Never Violate These

**Rule 1: Never write Ecto migrations by hand.**
After every resource change (new attribute, new relationship, new identity), run:
```bash
mix ash.generate_migrations --name describe_what_changed
```
Review the generated file, then run `mix ash.migrate`. Never create a migration file manually.

**Rule 2: `authorize?: false` is intentional — never "fix" it.**
The seeds file and the import Mix task (`mix import_from_mssql`) use `authorize?: false` on every Ash call. This is correct. These are trusted internal operations that must bypass policy checks. Do not add actors or change this flag.

**Rule 3: `RbacPolicy` ≠ Ash policies.**
`InstitutionalRepository.Access.RbacPolicy` is a database table (an Ash resource) that stores RBAC grant records. It is completely separate from Ash's built-in `Ash.Policy.Authorizer` and the `policies do ... end` blocks inside resources. Never confuse them. When the docs say "policy" in the context of a `policies do` block, that is Ash's authorization DSL. When they say `RbacPolicy`, that is the database grant table.

**Rule 4: `LegacyRepo` stays plain Ecto. Forever.**
`InstitutionalRepository.LegacyRepo` is a plain `Ecto.Repo` with the TDS (MSSQL) adapter. `LegacyThesis` is a plain `Ecto.Schema`. Neither is or ever becomes an Ash resource. Do not attempt to convert them.

**Rule 5: The abstract file is never embargoed.**
The `file_abstract` bitstream (bundle: `ORIGINAL`, sequence: 1) must never be affected by embargo logic, even when the full text is embargoed. Treat it as always accessible at the item's `access_level`. Enforce this explicitly in the `BitstreamController` and the `EmbargoLifterWorker`.

**Rule 6: THUMBNAIL bundle is always `:open`.**
Cover images (`file_cover`, bundle: `THUMBNAIL`) are always `access_level: :open`. Never set them to `:inherit`, `:restricted`, or `:closed`. Enforce this as a default in the `Bitstream` resource and submission wizard.

**Rule 7: ADMINISTRATIVE and LICENSE bundles are always `:restricted`.**
Approval letters, originality statements, acceptance letters, ethics approvals, NDA documents, indexing proofs, and all other administrative files must always be `access_level: :restricted`. This is hardcoded — it does not inherit from the item and cannot be changed by staff in the UI.

---

## 4. Ash Call Patterns — Use Exactly These

```elixir
# Read single record by ID
Ash.get!(Item, id, actor: current_user)
Ash.get!(Item, id, authorize?: false)           # trusted internal calls only

# Read single record by filter
Ash.get!(Item, Ash.Query.filter(Item, handle: "123456789/0"), authorize?: false)

# Read list — default action
Ash.read!(Item, actor: current_user)

# Read list — named action with arguments
Item
|> Ash.Query.for_read(:search, %{term: "neural", department: "0410"}, actor: current_user)
|> Ash.read!()

# Read with preloads
Ash.get!(Item, id, load: [:item_keywords, :item_authors, :bitstreams], actor: actor)

# Create — default action
Ash.create!(Item, %{title: "My Thesis", collection_id: cid}, actor: current_user)

# Create — named action
Ash.create!(Item, %{...attrs}, action: :import, authorize?: false)

# Update — named action
Ash.update!(item, %{}, action: :publish, actor: current_user)

# Update — default action with attrs
Ash.update!(item, %{title: "New Title"}, actor: current_user)

# Destroy
Ash.destroy!(item, actor: current_user)

# Bulk destroy
Item
|> Ash.Query.filter(status: :draft)
|> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

# Count
Ash.count!(Item, authorize?: false)

# AshPhoenix form in LiveView
form = AshPhoenix.Form.for_create(Item, :create, as: "item", actor: current_user)
form = AshPhoenix.Form.for_update(item, :update, as: "item", actor: current_user)
form = AshPhoenix.Form.validate(form, params)
{:ok, record} = AshPhoenix.Form.submit(form, params: params)
```

---

## 5. Resource & Domain Structure

There are 5 Ash domains. Every resource belongs to exactly one domain.

```
InstitutionalRepository.Repository   → Community, Collection, Item,
                                        ItemKeyword, ItemAuthor, ItemAdvisor,
                                        ItemExaminer, ItemTeamMember, ItemMetadata

InstitutionalRepository.Accounts     → User, Token, Group, GroupMembership

InstitutionalRepository.Content      → Bitstream

InstitutionalRepository.Access       → RbacPolicy

InstitutionalRepository.Analytics    → ViewEvent
```

`ItemExaminer` and `ItemTeamMember` are **new resources** not present in the original legacy codebase. They must be created from scratch. Full resource code is in `05_metadata_and_files_ash_edition.md` Section 14.

---

## 6. The 10 Item Types

The `item_type` attribute on `Item` uses these atom values exactly:

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

Field visibility in the submission UI is driven entirely by `item_type`. The helper module `InstitutionalRepositoryWeb.Live.Helpers.FieldVisibility` handles this — see `05_metadata_and_files_ash_edition.md` Section 15.

---

## 7. Bitstream (File) Rules Summary

Every uploaded file = one row in `bitstreams` table via the `Bitstream` Ash resource.

| Bundle | Default `access_level` | Override allowed? |
|--------|----------------------|-------------------|
| `ORIGINAL` | `:inherit` | Yes |
| `THUMBNAIL` | `:open` | **No — always open** |
| `CHAPTER` | `:inherit` | Yes |
| `SUPPLEMENTAL` | `:inherit` | Yes |
| `ADMINISTRATIVE` | `:restricted` | **No — always restricted** |
| `LICENSE` | `:restricted` | **No — always restricted** |
| `MEDIA` | `:inherit` | Yes |
| `SOURCE` | `:inherit` | Yes |

The `file_abstract` (`ORIGINAL`, sequence 1) is the one `ORIGINAL` file that is **never embargoed**, even when the item has an active `embargo_open_date`.

---

## 8. Authentication & Authorization

**Authentication** is handled entirely by `AshAuthentication`. Do not use Guardian, `phx_gen_auth`, or Bcrypt directly. The `User` resource has `extensions: [AshAuthentication]`. Sign-in and registration routes are generated by `AshAuthentication.Phoenix.Router` via `ash_authentication_live_session` and `sign_in_route`.

**Authorization** has two layers that must not be confused:

Layer 1 — **Ash policies** (`policies do ... end` inside each resource): These run on every Ash action. They define who can perform what action based on `actor` attributes. Always pass `actor:` when calling Ash in controllers and LiveViews.

Layer 2 — **`RbacPolicy` database table**: Dynamic grants stored in the `rbac_policies` table. Consulted by custom `Ash.Policy.Check` modules (`CanRead`, `CanReadBitstream`). Managed by `PolicyManager.apply_access_level/2`. This is for fine-grained item/bitstream access that cannot be expressed as static actor-attribute rules.

**User types** (`:member`, `:submitter`, `:reviewer`, `:admin`, `:superadmin`) drive most policy decisions via `actor_attribute_equals(:user_type, "admin")` checks.

---

## 9. Migration Workflow — Every Time

Follow this exact sequence after any resource change:

```bash
# 1. Generate migration
mix ash.generate_migrations --name describe_your_change

# 2. Review the generated file in priv/repo/migrations/

# 3. Apply
mix ash.migrate

# 4. If seeds need to run (first time or new groups added)
mix run priv/repo/seeds.exs
```

Never skip step 2. Always read the generated migration before applying — Ash may generate index drops or column renames that need review.

---

## 10. Import Task Behaviour

The `mix import_from_mssql` task reads from `LegacyRepo` (plain Ecto, MSSQL) and writes to Ash resources using the `:import` named action on each resource.

Key behaviours:
- Always uses `authorize?: false` — never passes an actor
- Uses the `:import` named action (not `:create`) on `Item`, `Bitstream`, `ItemKeyword`, `ItemAuthor`, `ItemAdvisor`, `ItemExaminer`, `ItemTeamMember`
- Skips already-imported items by checking `legacy_id` against existing records
- Calls `PolicyManager.apply_access_level(item, :open)` after each item is created
- All enum values from the legacy table (strings like `"Indonesia"`, `"published"`) are mapped to atoms before writing to Ash

All `:import` actions must exist on every resource that the import task writes to. If an `:import` action is missing, the task will fail.

---

## 11. What Needs Atoms, What Needs Strings

Ash attributes that use `:atom` type store atoms in the database (as strings internally, cast by Ash). The legacy MSSQL data uses raw strings. The import task is responsible for all conversions.

| Raw value in legacy data | Ash atom |
|--------------------------|----------|
| `"Indonesia"` / `"Indonesian"` | `:id` (language) |
| `"English"` | `:en` (language) |
| `true` + `true` (stPublikasi + Verifikasi) | `:published` (status) |
| `false` (stPublikasi) | `:withdrawn` (status) |
| `false` (Verifikasi only) | `:under_review` (status) |
| `nil` / unknown | `:submitted` (status) |
| `"url"` storage type | `:url` |
| `"s3"` storage type | `:s3` |
| `"ORIGINAL"` bundle | `:ORIGINAL` |

Never pass a raw string where an Ash attribute expects an atom. The attribute will reject it.

---

## 12. Common Mistakes to Avoid

- **Writing `Repo.insert/update/delete` anywhere in new code.** Use `Ash.create/update/destroy` instead. The only place `Repo.*` is acceptable is inside `LegacyRepo` calls in the import task.

- **Forgetting `actor:` in controller/LiveView Ash calls.** Every Ash call in a request context must pass `actor: socket.assigns.current_user` or `actor: conn.assigns.current_user`. Omitting it causes policy failures.

- **Adding `:import` action to a resource but forgetting to list it in `accept`.** The `:import` action must `accept` all fields the import task writes. If a field is missing from `accept`, it is silently ignored and the data is lost.

- **Generating migrations after changing only one resource.** `mix ash.generate_migrations` sees all resources at once. If you have pending changes across multiple resources, one run generates one migration covering all of them. Do not run it multiple times for the same set of changes.

- **Using `Ash.Query.filter` with string values for atom attributes.** Always pass atoms: `Ash.Query.filter(Item, status: :published)` not `status: "published"`.

- **Putting supplementary/rare fields as columns on `items`.** If a field only applies to one or two item types and is rarely queried, it goes in `item_metadata_extras` as a `schema.element.qualifier` row, not as a column. The key reference is in `05_metadata_and_files_ash_edition.md` Section 17.

- **Letting the admin panel expose ADMINISTRATIVE bundle files.** AshAdmin must not allow staff to change `access_level` on `ADMINISTRATIVE` or `LICENSE` bundle bitstreams. This must be enforced at the `Bitstream` resource policy level, not just in the UI.

---

## 13. Execution Checklist

When given a task, follow this sequence before writing a single line of code:

1. Identify which Ash domain and resource(s) are affected.
2. Identify whether you need a new attribute, a new relationship, a new action, a new resource, or a new policy.
3. If adding attributes → plan the migration that will follow.
4. If adding a resource → confirm it is registered in its domain and that `Item` has the corresponding `has_many` relationship.
5. Write the resource / attribute / action / policy change.
6. Run `mix ash.generate_migrations --name your_change`.
7. Review the generated migration.
8. Run `mix ash.migrate`.
9. If the change affects the import task, update the `:import` action's `accept` list.
10. If the change affects the submission UI, update `FieldVisibility` and the form LiveView.
