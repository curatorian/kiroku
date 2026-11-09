# SEO & Discoverability Review — Kiroku

**Scope:** how search engines (and other crawlers/harvesters) discover and index the public
content of this repository, and which access rules govern each discovery surface.

**Deployment context:** `https://repository.unpad.ac.id`. As of this review, the site serves a
Cloudflare bot challenge (`HTTP 403`, `cf-mitigated: challenge`) to **every** non-browser request —
including `robots.txt` and requests claiming the Googlebot user-agent. This is the primary reason
the site has zero indexed pages in Google. **No change inside Kiroku can fix that**; the zone
needs a verified-bot exemption (`cf.client.bot`) or Bot Fight Mode / Under Attack Mode disabled for
the subdomain. Everything below makes the app itself crawl-worthy and policy-correct so indexing
starts the moment Cloudflare allows crawlers.

---

## 1. Discovery-surface → governing-rule map

Every public discovery surface and the exact predicate that controls what is exposed:

| Surface | Governing rule | Code |
|---|---|---|
| `/sitemap.xml` | Items: `status == :published AND discoverable == true AND access_level == :open`. Communities/collections: `is_active == true AND access_level == :open` | `Repository.sitemap_entries/0` — `lib/kiroku/repository.ex` (~887–914) |
| Browse, Search, facets, homepage listings | Same triple, scoped by `Authorization.visibility_scope/1` (`:public` ⇒ `[:open]`) | `repository.ex` (`search_base_query`, `visibility_filter` ~1436+, 1775–1778); `browse_live.ex:36`, `search_live.ex:38` |
| Item detail page | `Authorization.can?(user, :read, item)` — anonymous requires `:published` + `discoverable` + `:open` | `lib/kiroku/access/authorization.ex:105–108`; `lib/kiroku_web/live/item_live/show.ex:22` |
| Bitstream file download | `Content.accessible?/3` — bundle rules, locked-bitstream set, item-level embargo dates, per-bitstream `access_level` | `lib/kiroku/content.ex:78–123` |
| OAI-PMH (`/api/oai`) | Records: `:published` + `discoverable` + `:open`. Sets: only active/`:open` communities & collections | `Repository.oai_items/1` (~992–1023), `oai_sets/1` (~920–938); `oai_visible?/1` in `lib/kiroku/oai/builder.ex:377–379` |
| Legacy `/handle/*` resolver | 302-redirects to the public LiveView, which then applies the item/community/collection check | `lib/kiroku_web/controllers/handle_controller.ex` |

**Anonymous users therefore never see** draft / submitted / under_review / embargoed-status /
withdrawn items, non-`discoverable` items, or non-`:open` items in any listing, the sitemap, or
OAI-PMH. Communities/collections that are inactive or non-`:open` are likewise hidden.

## 2. Policy notes

- **Embargo = files-only embargo (correct, DSpace-like).** A `:published`/`:open` item with
  `Item.files_embargoed?/1` true shows its full metadata page (title, abstract, citations) while
  non-abstract bitstreams render as "Locked". The abstract bitstream (`ORIGINAL`, sequence 1) is
  never embargoed. Metadata stays public by design; only file bytes are gated.
- **Withdrawal is staff-initiated only.** `withdraw_item_fsm/1` and `reject_item/3`
  (`repository.ex:2010–2036`) set `status: :withdrawn, discoverable: false`. There is **no
  user-requested withdrawal or request-a-copy feature** in the codebase (documented as a future
  feature, not a gap in enforcement).
- **`status: :embargoed` is an orphan state.** No code path ever sets it; only `Embargo.LifterWorker`
  lifts it back to `:published`. Effective embargo enforcement is purely date-based
  (`files_embargoed?/1` inside `Content.accessible?/3`). If the status were ever set (e.g. by import),
  the item's *metadata* would disappear from the public site, sitemap, and OAI — different policy
  from the date-based files-only embargo. Do not rely on the status.
- **Inert schema fields (no code reads/writes them):** `items.withdrawn` boolean (the FSM uses
  `status: :withdrawn` instead), bitstream-level `embargo_open_date`/`embargo_close_date`
  (only item-level dates are enforced), `items.date_available`. Admins should not expect these to work.

## 3. Findings

### Correct today

- Dynamic `robots.txt` with a `Sitemap:` directive and sane `Disallow` list for `/users/`,
  `/admin/`, `/my/` (`lib/kiroku_web/controllers/seo_controller.ex`).
- `sitemap.xml` filtered to public content only (see map above); absolute URLs from
  `Endpoint.url()`.
- Item pages emit Google Scholar `citation_*`, Open Graph, Twitter Card, and Schema.org JSON-LD
  server-side (`lib/kiroku_web/components/seo.ex`).
- Pagination renders real `<a href>` anchors (crawlable), omits `page=1`
  (`lib/kiroku_web/components/kiroku_components.ex:303–400`).
- Thumbnails are generated per item (`ThumbnailWorker`, `Content.get_thumbnail_for_item/1`).
- `Kiroku.Settings.brand_settings()` provides name/tagline/description usable as meta defaults.

### P0 — indexing blockers / access correctness

- **F1 — Bitstream access leak (security).** `BitstreamController.show` checks only
  `Content.accessible?/3` and never the item's visibility — files of `draft`/`submitted` items
  whose bitstream is `:open` (or `:inherit` of an `:open` item… which drafts default to) are
  downloadable by anyone with the two UUIDs (`/items/:item_id/bitstreams/:id` is anonymous-allowed).
  *Fix: require `Authorization.can?(user, :read, item)` first.*
- **F2 — Soft 404 on unknown item handles.** `ItemLive.Show` renders an "Item not found" card with
  HTTP 200; communities/collections already raise `Ecto.NoResultsError` → real 404. Soft 404s pollute
  Search Console coverage reports and can be indexed.
- **F3 — Non-public item URLs silently redirect to `/`.** Restricted / withdrawn / unpublished items
  redirect home with no explanation. *Fix (chosen): DSpace-style tombstone notice page — handle +
  generic notice, no metadata, `noindex, follow`.*
- **F4 — No canonical / noindex infrastructure.** `/search?q=…&faculty=…&year=…` permutations,
  `?locale=id|en` duplicates, and paginated URLs are all crawlable 200s with no canonical link and
  no `meta description` outside item pages. Root layout has only charset/viewport/csrf/title.
- **F5 — robots.txt `Disallow: /api/`** also blocks `/api/oai` for robots-respecting crawlers
  (harvesters ignore robots.txt, so this is SEO-tooling hygiene rather than an outage).
- **F6 — Legacy `/handle/*` resolver answers 302** (temporary) instead of 301 (permanent), weakening
  the SEO inheritance of legacy DSpace URLs.

### P1 — on-page depth

- No `meta description` / canonical / OG defaults on home, browse, search, community, collection,
  oai, api-info pages; homepage falls back to the generic default `<title>`.
- No `og:image` / `twitter:image` on item pages despite thumbnails existing; `BitstreamController`
  sends `content-disposition: attachment` for local files (hostile to social scrapers).
- `<html lang="id">` hardcoded regardless of the active `?locale=`; no canonical locale-stripping.
- No BreadcrumbList JSON-LD on item pages (community ancestor chain is already computed and shown).

### P2/P3 — hygiene / optional

- Sitemap is queried on every request (no cache; fine at current scale, revisit with growth).
- Minor filter omissions in `list_recent_published`, `count_items_for_collection`,
  `list_distinct_values_for_collection` (missing `discoverable` and/or access-level predicates) —
  internal-only or cosmetic surfaces, but cheap to align.

## 4. Remediation implemented (this repository)

- **F1** `BitstreamController.show` now requires `Authorization.can?(user, :read, item)` before
  `Content.accessible?/3`; `THUMBNAIL` bundle serves `content-disposition: inline`.
- **F2/F3** Unknown handles raise a real 404; non-public items render a tombstone notice page with
  `noindex, follow` (via `assigns[:robots_meta]` in the root layout head).
- **F4** `KirokuWeb.SEO.put_page_seo/2` sets canonical / description / robots per page; root layout
  renders them; canonical URLs strip `locale` and `page` params; `<html lang>` follows the locale;
  `/search` is `noindex, follow` + canonical `/search`.
- **F5** robots.txt gains `Allow: /api/oai`.
- **F6** `/handle/*` answers 301.
- **Phase 2** homepage/api-info titles + descriptions, `og:image`/`twitter:image` from thumbnails,
  BreadcrumbList JSON-LD on item pages.

## 5. Operations checklist (outside the app)

1. **Cloudflare (IT):** exempt verified crawlers — WAF rule *Skip* for `cf.client.bot` (or disable
   Bot Fight Mode / Under Attack Mode for the subdomain). Verify in Security → Events that Googlebot
   requests stop being challenged.
2. **Google Search Console:** add the `https://repository.unpad.ac.id` property (DNS verification),
   submit `/sitemap.xml`, use URL Inspection → Request indexing on the homepage and a few key items.
3. **Monitor:** Search Console → Settings → Crawl stats (response codes, Googlebot types) and
   Coverage report; expect soft-404s to drain after F2 lands.
4. Re-test externally after the Cloudflare change: `curl -I https://repository.unpad.ac.id/robots.txt`
   should return 200 text/plain, not 403 challenge.
