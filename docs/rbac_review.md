# RBAC & User Management — Security Review

**Date:** 15 Jul 2026
**Scope:** Role-based access control, user management, authorization policy, API
token authentication, and staff-access enforcement across the Kiroku web app.

---

## 1. Architecture Overview

The system has a well-designed authorization core
(`Kiroku.Access.Authorization`) with a single `can?/3` entry point backed by two
policy layers:

- **Per-user policies** (`rbac_policies`) — grants tied to a specific user +
  resource.
- **Role-scoped policies** (`role_policies`) — grants tied to a `user_type`,
  cached in `:persistent_term` and refreshed on every mutation.

### Role hierarchy

```
:submitter < :internal < :reviewer < :admin < :superadmin
```

Defined as an `Ecto.Enum` in `lib/kiroku/accounts/user.ex:8`. The enum itself
imposes no ordering — the hierarchy is encoded only in pattern guards inside
`Authorization`.

`:superadmin` short-circuits to god-mode at `authorization.ex:63`. Everything
else flows through the `can?/3` clauses (`authorization.ex:63-180`).

### Visibility scopes (`authorization.ex:42-60`)

| Scope   | User types                          | Sees access levels                  |
|---------|-------------------------------------|-------------------------------------|
| `:staff`   | `:reviewer` `:admin` `:superadmin`  | `:open` `:internal` `:restricted` `:closed` |
| `:internal`| `:internal` `:submitter`            | `:open` `:internal`                 |
| `:public`  | anonymous / nil                     | `:open`                             |

### `Authorization.can?/3` clause inventory

| Line | Clause | Grants |
|------|--------|--------|
| 63 | `:superadmin` × anything × anything | **everything** (god mode) |
| 74-75 | `:read` inactive `%Community{}` | staff scope OR policy |
| 77-80 | `:read` `%Community{}` | access_level visible OR policy |
| 84-87 | `:create/:update/:delete` `%Collection{}` | `:admin` only |
| 89 | `:read` `%Collection{}` | `:admin` |
| 91-97 | `:read` `%Collection{}` (inactive/active) | scope-gated OR policy |
| 105-108 | `:read` published+discoverable `%Item{}` | access_level OR policy |
| 114-117 | `:read` unpublished `%Item{}` | `:internal`/`:reviewer`/`:admin` |
| 119-122 | `:read` own item | `submitter_id == user_id` |
| 126-129 | `:create` `%Item{}` | `:submitter`, `:admin` |
| 133-139 | `:update` own draft/submitted `%Item{}` | `:submitter` |
| 141 | `:update` `%Item{}` | `:admin` |
| 145-149 | `:review/:publish/:withdraw/:lift_embargo` `%Item{}` | `:reviewer`, `:admin` |
| 153 | `:delete` `%Item{}` | `:admin` |
| 157-160 | `:manage_users/:manage_communities/:manage_collections` `:global` | `:admin` |
| 175-178 | catch-all fallback | role-policy OR per-user policy |
| 180 | total fallback | `false` (deny) |

Action grant semantics (`authorization.ex:216-224`): `:manage` is a wildcard;
`:review` also grants `:withdraw`/`:lift_embargo`; `:submit`→`:create`;
`:publish`→`:publish`; `:read`→`:read`.

Resource-hierarchy matching (`authorization.ex:229-270`) handles
Community → Collection → Item descent, including Item→Community (when
`item.collection` is preloaded, line 263). Clean and correct.

---

## 2. User / Account Schema

**Files:** `lib/kiroku/accounts/user.ex`, `lib/kiroku/accounts.ex`,
`lib/kiroku/accounts/user_token.ex`

### Changesets

| Changeset | Casts `:user_type`? | Use |
|-----------|---------------------|-----|
| `registration_changeset/3` (line 30) | No (defaults `:submitter`) | Public self-registration |
| `admin_changeset/3` (line 38) | Yes | Admin create/update |
| `role_changeset/2` (line 74) | Yes | Role-only update |
| `oauth_changeset/3` (line 56) | No (defaults `:submitter`) | PAuS OAuth |

### Notes

- Session tokens preload `:rbac_policies` (`accounts.ex:296-301`) so
  `Authorization.can?/3` has grants in memory — one indexed query per auth.
- Password policy: min 12 / max 72 bytes, bcrypt-hashed,
  `Bcrypt.no_user_verify/0` used to prevent timing attacks (`user.ex:120-123`).
  Solid.
- Session validity is 60 days (`user_token.ex:12`).

---

## 3. Roles & Policies

**Files:**

- `lib/kiroku/access/rbac_policy.ex` — per-user policy schema
- `lib/kiroku/access/rbac_policies.ex` — per-user policy context
- `lib/kiroku/access/role_policy.ex` — role-scoped policy schema
- `lib/kiroku/access/role_policies.ex` — role-scoped policy context

### Per-user policies (`rbac_policies`)

Schema (`rbac_policy.ex:11-20`): `belongs_to :user`, fields `resource_type`
(community/collection/item/global), `resource_id`, `action`
(read/submit/review/publish/manage), `notes`.

Context: CRUD + `grant_area_access/4` (line 65, will *upgrade* an existing
policy's action), `revoke_area_access/3` (line 89), `bulk_delete_user_policies/1`
(line 60).

### Role-scoped policies (`role_policies`)

Same shape but keyed on `user_type`. `:superadmin` is excluded from
`@user_types` (line 8) — correct since superadmin short-circuits at
`authorization.ex:63`.

Uses `:persistent_term` cache keyed by `user_type` (lines 14-22), refreshed on
every write (lines 55, 62, 69). `cached_policies_for_type/1` returns `[]` if
cache uninitialized — safe default.

---

## 4. Plugs & on_mount Callbacks

**Files:** `lib/kiroku_web/user_auth.ex`,
`lib/kiroku_web/plugs/api_auth.ex`, `lib/kiroku_web/plugs/setup_guard.ex`,
`lib/kiroku_web/router.ex`

### Browser auth (`user_auth.ex`)

Standard `phx.gen.auth` pattern.

- Plugs: `fetch_current_user/2` (line 96), `require_authenticated_user/2`
  (line 117), `redirect_if_user_is_authenticated/2` (line 130).
- on_mount callbacks: `:mount_current_user`, `:ensure_authenticated`,
  `:redirect_if_user_is_authenticated` (lines 20-47).

### Router structure (`router.ex`)

- `:browser` pipeline runs `fetch_current_user` + `SetupGuard` (lines 6-16).
- **The `/admin` scope (lines 158-204) pipes through only
  `[:browser, :require_authenticated_user]`.**
- **The `:admin` live_session (line 165-166) has only
  `on_mount: [{KirokuWeb.UserAuth, :ensure_authenticated}]`.**

---

## 5. API Token Auth (REST / SWORD)

**Files:** `lib/kiroku/api_token.ex`, `lib/kiroku/api_tokens.ex`,
`lib/kiroku_web/plugs/api_auth.ex`,
`lib/kiroku_web/controllers/sword_v2/deposit_controller.ex`,
`lib/kiroku_web/controllers/api/v1/item_controller.ex`

### How it works

- Token format: `kiroku_<Base64(32 random bytes)>` (`api_tokens.ex:133-135`).
- Stored as **SHA256 hash** (`api_tokens.ex:137-139`); raw value returned once
  at create/rotate (`create_token/2` line 40, `rotate_token/1` line 61).
- `verify_token/1` (line 106) joins `api_tokens` ↔ `users`, updates
  `last_used_at`, and **preloads `:rbac_policies`** (line 121) so
  `Authorization.can?` works for API callers.
- `ApiAuth` plug (`api_auth.ex:18-31`) reads token from
  `Authorization: Bearer <t>` **OR** `?token=<t>` query param.
  Invalid/missing → `current_user: nil`.
- `RequireApiToken` plug (`api_auth.ex:58-70`) halts with 401 JSON if no
  `current_user`.
- Used in pipelines `:authenticated_api` (router.ex:22-26) for `/api/v1/*` and
  `:sword_api` (router.ex:95-99) for `/sword-v2/*`.

### Authorization in API controllers (done correctly)

- `Api.V1.ItemController.create/update/deposit_bitstream` all call
  `Authorization.can?` (item_controller.ex:109, 140, 166). ✓
- `index` uses `visibility_scope` for filtering (line 37). ✓
- `show` checks `can?(:read)` (line 64). ✓
- `bitstreams` filters via `Content.accessible?` (line 91). ✓
- SWORD `deposit` checks `can?(:create)` (deposit_controller.ex:37). ✓

---

## 6. Findings

### CRITICAL — No central admin gate

There is no central admin/role gate. A grep for
`require_admin|require_staff|require_superadmin|:ensure_admin|:require_role`
across `lib/kiroku_web` returns **nothing**. Authentication is enforced
centrally; authorization for admin pages is not. Every admin LiveView must
self-police, and the coverage is wildly inconsistent.

The `router.ex:217-223` comment acknowledges this is the intended design:
*"Staff authorization is enforced inside each LiveView's mount/3."* — but that
contract is only honored by ~7 of ~15 admin LiveViews.

#### Admin LiveView auth-check coverage

| Admin LiveView | Auth check? | Status |
|----------------|-------------|--------|
| `CommunityLive.Index` | `superadmin?` in `handle_params` (index.ex:230) | ✓ protected |
| `CommunityLive.Show` | `superadmin?` in `mount` (show.ex:95) | ✓ protected |
| `RolePolicyLive` | `:superadmin` in `mount` (role_policy_live.ex:204) | ✓ protected |
| `ApiTokenLive` | `superadmin?` in `mount` (api_token_live.ex:8) | ✓ protected |
| `UserLive.RoleManagement` | `:superadmin` in `mount` (role_management.ex:266) | ✓ protected |
| `AdminSyncLive` | `staff?` in `mount` (admin_sync_live.ex:385/610) | ✓ protected |
| `AdminSafLive` | `staff?` in `mount` (admin_saf_live.ex:291/400) | ✓ protected |
| **`DashboardLive`** | **NONE** (dashboard_live.ex:619) | ✗ any user sees admin stats |
| **`UserLive.Index`** | **NONE** (index.ex:238) | ✗ any user lists all users + emails |
| **`UserLive.Show`** | **NONE** (show.ex:388) | ✗ any user views any profile + policies |
| **`CollectionLive.Index`** | **NONE** (index.ex:254) | ✗ any user can create/edit collections |
| **`CollectionLive.Show`** | **NONE** (show.ex:59) | ✗ any user can delete any collection |
| **`ItemLive.Index`** | **NONE** (index.ex:439) | ✗ any user sees all items incl. restricted |
| **`ItemLive.Show`** | **NONE** (show.ex:1010) | ✗ any user can publish/withdraw/delete any item |
| **`ItemLive.Review`** | **NONE** (review.ex:6) | ✗ any user can approve/reject/publish any item |
| **`SettingsLive`** | **NONE** (settings_live.ex:8) | ✗ any user edits storage/mailer/brand/registration |

#### CRITICAL — Exploitable handlers (all reachable by any authenticated user)

- `Admin.ItemLive.Show` events `publish` (show.ex:1040), `withdraw` (1050),
  `lift_embargo` (1063), `delete` (1073), `save_metadata` (1089) — none call
  `Authorization.can?`. A `:submitter` can publish or permanently delete any item
  in the repository. `Repository.*` functions (`repository.ex:1478-1624`)
  perform **no** internal auth.
- `Admin.ItemLive.Review` events `start_review` (205), `submit_review` (227 —
  approve/revision/reject), `withdraw` (278) — none check auth. Any user can
  approve & publish, or reject, any submitted item.
- `Admin.CollectionLive.Show` event `delete` (show.ex:66) — any user can delete
  any collection.
- `Admin.SettingsLive` — any user can flip `allow_submit`/`allow_registration`,
  change storage adapter, mailer config.
- `Admin.UserLive.Index` `create_user` handler (index.ex:285-298) calls
  `Accounts.admin_create_user/1` with **no role filtering** (unlike `save_edit`
  which calls `maybe_restrict_role`). The role dropdown is limited client-side
  via `role_options_for/1`, but a crafted `phx-submit` can set
  `"user_type" => "superadmin"`. **An admin (or any logged-in user) can create a
  superadmin account.** This is direct privilege escalation, and inconsistent
  with `save_edit` which *does* sanitize.

#### CRITICAL — RBAC policy self-grant privilege escalation

`Admin.UserLive.Show` `save_policy` (show.ex:509-526) and `update_policy`
(show.ex:528-545) perform **no authorization check** (`delete_policy` at 547
does check `:superadmin`; these two don't). Since the view itself is reachable
by any authenticated user (no mount check), an attacker can:

1. Navigate to `/admin/users/<own_id>/policies/new`
2. Create `{resource_type: :global, action: :manage}` on themselves
3. `Authorization.can?/3` now returns `true` for *every* resource via
   `policy_allows?` → `action_grants?(:manage, _)` (authorization.ex:216). They
   are effectively superadmin for anything that actually consults the module.

#### MEDIUM — No actor-aware validation in changesets

`admin_changeset` and `role_changeset` accept *any* of the 5 types with no
server-side check that the *actor* is allowed to set that type. All restriction
lives in LiveView glue code (`maybe_restrict_role/2` at `show.ex:592`), which is
easy to forget on new code paths.

#### LOW — `assign_internal_role/1`

`accounts.ex:94-98` has no guard and will *downgrade* an admin/superadmin to
`:internal` if called on them. Safety relies entirely on the caller
(`user_auth_paus_controller.ex:66` correctly matches only
`%User{user_type: :submitter}`). Brittle.

---

### HIGH — Inconsistent `staff?/1` definition

There are **six** different `staff?`/`user_is_staff?` definitions, and they
disagree about whether `:reviewer` counts:

| File:Line | Definition | Includes `:reviewer`? |
|-----------|------------|-----------------------|
| `access/authorization.ex:42-46` (`visibility_scope`) | `[:reviewer, :admin, :superadmin]` → `:staff` | **Yes** |
| `content.ex:146` (`user_is_staff?/1`) | `[:reviewer, :admin, :superadmin]` | **Yes** |
| `kiroku_web/live/my_item_live/index.ex:419` (`staff?/1`) | `[:admin, :superadmin]` | **No** |
| `kiroku_web/controllers/saf_controller.ex:40` (`staff?/1`) | `[:admin, :superadmin]` | **No** |
| `kiroku_web/live/admin_sync_live.ex:612` (`staff?/1`) | `[:admin, :superadmin]` | **No** |
| `kiroku_web/live/admin_saf_live.ex:402` (`staff?/1`) | `[:admin, :superadmin]` | **No** |

A `:reviewer` is treated as staff for visibility/reading restricted content
(authorization.ex, content.ex) but is **NOT** staff for SAF download, MSSQL sync,
SAF import, or the "can submit" override. There is no single source of truth —
each module hardcodes its own list.

---

### HIGH — API token security gaps

- **`?token=` query-param authentication** (`api_auth.ex:42-44`). Bearer tokens
  in URLs leak into web-server access logs, reverse-proxy logs, browser history,
  `Referer` headers to any third-party resource, and shared links. Actively
  advertised to users in `api_token_live.ex:386, 632` ("browser testing").
- **Tokens never expire.** `api_tokens` schema (`api_token.ex:11-19`) has no
  expiry field; `verify_token` does no staleness check. A leaked token is valid
  until manually rotated/deleted.
- **No scoping on tokens.** A token grants the full power of the owning user's
  `user_type` + RBAC policies. A `:superadmin`'s API token is a full god-mode key
  with no expiry.
- **No rate limiting / lockout** on `verify_token` or the API pipelines.

#### HIGH — SWORD `statement/2` has no authorization check

`deposit_controller.ex:50-62`. Any valid API token (even a `:submitter`'s) can
`GET /sword-v2/statement/:item_handle` for *any* item — including withdrawn,
draft, embargoed, or `:closed`/`:restricted` items — and receive lifecycle state
+ metadata. Inconsistent with the REST `show` endpoint which properly checks
`can?(:read)`. The `deposit/2` endpoint right above it is correctly gated.

---

### MEDIUM — Data-integrity & logic issues

- **No unique index on `rbac_policies(user_id, resource_type, resource_id)`.**
  Duplicate policies can accumulate; `get_user_policy_for_resource/3`
  (`rbac_policies.ex:26`) will crash on multiple rows via `Repo.one/1` (rescued
  to `nil` in `grant_area_access`, but raw crash in `show.ex` paths if called
  directly). Compare `role_policy.ex:26` which *does* have a unique index.
- **`RbacPolicy.changeset`** (`rbac_policy.ex:22-27`) does not validate
  `resource_id` exists or matches `resource_type` — the policy editor UI
  (`show.ex:255-283`) takes raw UUID text input with no validation.
- **`onboarding.create_first_superadmin/1`** (`onboarding.ex:74-86`) — TOCTOU
  race on `superadmin_exists?/0`. Two concurrent first-run requests could both
  pass the check before either inserts. Low likelihood (setup runs once) but a
  `unique` constraint isn't enough since multiple superadmins are legal
  post-setup; consider a transactional advisory lock.
- **`:internal` cannot `:create` items** via role rules (`authorization.ex:126`
  only allows `:submitter`/`:admin`). Yet PAuS OAuth promotes academics to
  `:internal`. They need an explicit RBAC `:submit` policy to deposit. Possibly
  intentional, but worth confirming.
- **Per-request DB write** — `verify_token` updates `last_used_at` on *every*
  API call (`api_tokens.ex:119, 125-129`). Under load this is a write-hot row
  per token. Consider throttling the update (e.g., only if >5 min stale).
- **`:persistent_term` cache** is global and never expires; if multiple nodes
  run, each must `refresh_cache` independently after a write. A single-node
  assumption.

---

### LOW

- **Dead code**: `core_components.ex:153` has a stale user_type select
  (`["Admin": "admin", "User": "user"]`) — `:user` isn't even a valid
  `user_type`. Appears unused but should be removed.
- **`String.to_existing_atom/1`** used for resource_type/action
  (`rbac_policies.ex:28,66`, `role_management.ex:488`) is wrapped in
  `rescue ArgumentError`. Safe against atom-table attacks per AGENTS.md guidance.
- **No clause for anonymous `nil` user** on community/collection read. Works
  because `visibility_scope(nil)` → `:public`, and `policy_allows?/1` returns
  false for non-`%User{}`. Functionally fine, just implicit.

---

## 7. What's Done Well

- `Authorization.can?/3` is a clean, correct single entry point with proper
  resource-hierarchy descent (`authorization.ex:229-270`).
- The published-item read guard at `authorization.ex:114` (`status != :published`)
  is a subtle and correct defense — the in-code comment (lines 110-113)
  documents exactly why.
- API controllers consistently call `can?/3` — the REST + SWORD deposit layer is
  the gold standard the admin UI should follow.
- `role_policies` use a unique index (`role_policy.ex:26`) + `:persistent_term`
  cache refreshed on every mutation.
- Password handling: bcrypt + `Bcrypt.no_user_verify/0` timing-attack mitigation
  (`user.ex:120-123`).
- API tokens stored as SHA256 hashes; raw value returned once at create/rotate.
- Session tokens preload `:rbac_policies` so auth has grants in memory.

---

## 8. Recommended Fixes (prioritized)

1. **Add a central admin authorization gate** — a `:require_staff` plug +
   `:ensure_staff`/`:ensure_admin` on_mount callback, applied to the entire
   `/admin` scope and `:admin`/`admin_*` live_sessions. This single change closes
   most of the CRITICAL findings.
2. **Make every mutating LiveView handler call `Authorization.can?/3`** — the
   module already exists and is correct. Especially `ItemLive.Show`/`Review`
   (publish/withdraw/delete/reject), `CollectionLive.Show` (delete),
   `SettingsLive` (all), and `UserLive.Show.save_policy`/`update_policy`.
3. **Fix `UserLive.Index.create_user`** to sanitize `user_type` server-side (it's
   the one create path that skips `maybe_restrict_role`) — currently allows
   creating superadmins.
4. **Gate SWORD `statement/2`** with `Authorization.can?(:read, item)`.
5. **Remove `?token=` query-param auth** (or restrict to read-only GETs) and add
   token expiry + optional scopes.
6. **Consolidate `staff?/1`** into one canonical predicate
   (`visibility_scope(user) == :staff`) and delete the five divergent copies.
7. **Add a unique index on `rbac_policies(user_id, resource_type, resource_id)`**
   and adjust `get_user_policy_for_resource` accordingly.
