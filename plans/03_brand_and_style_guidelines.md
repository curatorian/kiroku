# Brand & Style Guidelines
## Kiroku — Institutional Knowledge Repository
### Inspired by Patchouli Knowledge · Voile, the Magic Library

---

## 0. Design Philosophy

> *"What is written is remembered. What is remembered, endures."*

**Kiroku** (記録) — Japanese for *record*, *documentation*, *archive*. Every thesis, every journal article, every creative work deposited here becomes a permanent record. The name carries weight without pretension. It works in Indonesian academic contexts, international contexts, and sits naturally beside its sibling system, Voile.

The visual identity draws from **Patchouli Knowledge** — Scholar of the Scarlet Devil Mansion, keeper of the Voile Magic Library. Her world communicates:

- **Depth without clutter** — vast shelves, dim candlelight, organized stillness
- **Power through patience** — seven elements mastered, not rushed
- **Beauty in the scholarly** — books as sacred objects, knowledge as craft
- **The magical made systematic** — magic circles that are also diagrams, spells that are also formulas

The UI should feel like stepping into **Kiroku** — the magic library that Kiroku lives within. Dark, purposeful, rich in detail, but always readable and navigable. Every decorative element earns its place.

---

## 1. Project Identity

### Name

```
Full name:    Kiroku — Institutional Knowledge Repository
Kanji:        記録
Short name:   Kiroku
System name:  kiroku   (lowercase — URLs, CLI, config keys, mix.exs app name)
Tagline:      "Every work recorded. Every scholar remembered."
Alt tagline:  "The permanent record of scholarly knowledge."
```

### Relationship to Voile

Kiroku and Voile are **sibling systems** in the same institutional software family.
They share a design language but are distinct products with distinct identities.

| | Voile | Kiroku |
|---|---|---|
| **Purpose** | GLAM Management System | Institutional Repository |
| **Metaphor** | The library itself — collection, cataloguing, circulation | The archive — permanent preservation of scholarly works |
| **Primary user** | Librarians, curators, staff | Students, faculty, researchers, the public |
| **Patchouli ref** | Voile, the Magic Library (the place) | Patchouli's books and records (the knowledge within) |

Shared: color system, typography, icon style, motion system, component patterns.
Distinct: Kiroku uses the **記** kanji glyph in its icon; Voile uses the open book.

---

## 2. Color System

Patchouli's palette is built around **purple and violet as the foundation**, with
**triadic ribbon accents** of red, golden yellow, and cornflower blue.

### 2.1 Primary Palette — The Violet Scale

| Token | Name | Hex | Usage |
|-------|------|-----|-------|
| `--color-void` | Library Void | `#0D0817` | Deepest background. Page root. |
| `--color-grimoire` | Grimoire | `#1A1030` | Card backgrounds, sidebars. |
| `--color-dusk` | Dusk Violet | `#2D1B69` | Elevated surfaces, headers. |
| `--color-patchouli` | Patchouli | `#7B4FA6` | **Primary brand color.** Buttons, links, active states. |
| `--color-lavender` | Soft Lavender | `#9B7EC8` | Secondary interactive. Hover states. |
| `--color-wisteria` | Wisteria | `#C4A8E0` | Labels, subtle UI elements. |
| `--color-lilac` | Lilac Mist | `#E8DFF5` | Light surface tints. Primary text on dark. |

### 2.2 Accent Palette — The Ribbon Triad

Patchouli's ribbon has three stripes: red, yellow, blue.
Used sparingly — semantic and decorative only.

| Token | Name | Hex | Usage |
|-------|------|-----|-------|
| `--color-ribbon-red` | Ribbon Red | `#C4415A` | Error, danger, embargo warnings, fire element |
| `--color-ribbon-crimson` | Deep Crimson | `#8B2340` | Hover on red. Critical alerts. |
| `--color-ribbon-gold` | Ribbon Gold | `#D4A017` | Warning, badges, sun/moon element |
| `--color-ribbon-amber` | Amber Glow | `#E8C547` | Highlight, selection, open access indicator |
| `--color-ribbon-blue` | Ribbon Blue | `#4A7BC4` | Info, links in body text, water element |
| `--color-ribbon-sky` | Sky Sapphire | `#7AABD8` | Hover on blue. Secondary info. |

### 2.3 Neutral Palette — Paper & Ink

| Token | Name | Hex | Usage |
|-------|------|-----|-------|
| `--color-ink` | Deep Ink | `#1C1420` | Body text on light backgrounds |
| `--color-quill` | Quill Grey | `#6B5F78` | Secondary text, captions, metadata labels |
| `--color-dust` | Book Dust | `#9E93AB` | Disabled states, placeholders |
| `--color-parchment` | Old Parchment | `#F5F0E8` | Light mode page background |
| `--color-vellum` | Vellum | `#EDE8DC` | Light mode card surfaces |
| `--color-ivory` | Ivory | `#FAF7F2` | Light mode input backgrounds |

### 2.4 Semantic Colors

| Token | Value | Meaning |
|-------|-------|---------|
| `--color-success` | `#5A9E72` | Published, verified, open access |
| `--color-warning` | `--color-ribbon-gold` | Embargoed, pending review |
| `--color-error` | `--color-ribbon-red` | Rejected, withdrawn, error |
| `--color-info` | `--color-ribbon-blue` | Draft, informational, restricted |
| `--color-neutral` | `--color-dust` | Closed, disabled, archived |

### 2.5 Dark Mode Surface Stack (Default)

```
Page background:  --color-void       #0D0817
Base surface:     --color-grimoire   #1A1030
Raised surface:   --color-dusk       #2D1B69   (cards, panels)
Overlay:          #3D2880                      (modals, popovers)
Border:           rgba(155,126,200,0.15)
Subtle border:    rgba(155,126,200,0.08)
```

### 2.6 Light Mode Surface Stack (Print / Accessibility)

```
Page background:  --color-parchment  #F5F0E8
Base surface:     --color-ivory      #FAF7F2
Raised surface:   --color-vellum     #EDE8DC
Border:           rgba(45,27,105,0.12)
```

---

## 3. Typography

### 3.1 Type Stack

| Role | Font | Notes |
|------|------|-------|
| **Display / Wordmark** | *IM Fell English* | Old printed book feel. Wordmark and H1 hero only. |
| **Headings H2–H4** | *Cormorant Garamond* | Elegant old-style serif. Scholarly and refined. |
| **Body Text** | *Source Serif 4* | Legible serif for abstracts and long copy. |
| **UI / Interface** | *Inter* | Labels, buttons, nav, inputs. Never body copy. |
| **Code / Identifiers** | *JetBrains Mono* | Handles, DOIs, NIM/NPM, file paths. |

All five are available free on **Google Fonts**.

```css
/* app.css */
@import url('https://fonts.googleapis.com/css2?family=IM+Fell+English:ital@0;1&family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&family=Source+Serif+4:ital,wght@0,400;0,600;1,400&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');
```

### 3.2 Type Scale

```
--text-xs:    0.75rem  / 12px  — captions, timestamps, metadata micro-labels
--text-sm:    0.875rem / 14px  — secondary body, table cells, UI labels
--text-base:  1rem     / 16px  — primary body text, abstract reading
--text-lg:    1.125rem / 18px  — lead text, item titles in card list
--text-xl:    1.25rem  / 20px  — section headings (H4)
--text-2xl:   1.5rem   / 24px  — page section titles (H3)
--text-3xl:   1.875rem / 30px  — major headings (H2)
--text-4xl:   2.25rem  / 36px  — page titles (H1)
--text-5xl:   3rem     / 48px  — hero / display (IM Fell only)
--text-6xl:   3.75rem  / 60px  — wordmark only
```

### 3.3 Font Assignment Rules

- *IM Fell English* → wordmark, hero H1, pull quotes from abstracts only
- *Cormorant Garamond* → H2, H3, H4; item title on detail page; collection/community names
- *Source Serif 4* → abstract text, body copy, item title in search cards
- *Inter* → nav labels, buttons, form fields, metadata labels, badges, tables
- *JetBrains Mono* → handle paths, DOI values, NIM/NPM in admin views

---

## 4. Logo & Wordmark

### 4.1 Primary Wordmark

```
  記  Kiroku
  ──────────   ← 1px rule in --color-patchouli, full wordmark width
  ◆  ◇  ◆     ← 4px diamonds: ribbon-red · ribbon-gold · ribbon-blue
```

- **記** kanji sits left of the Latin text, slightly larger, in `--color-patchouli`
- **Kiroku** in *IM Fell English* italic, `--color-lilac` on dark / `--color-dusk` on light
- The rule and diamonds are part of the full wordmark — never omit them in this variant

### 4.2 Wordmark Variants

| Variant | When to Use |
|---------|-------------|
| **Full** — `記 Kiroku` + rule + diamonds | Header, documents, about page |
| **Compact** — `記 Kiroku` only | Collapsed sidebar, small header |
| **Mark only** — `記` alone | Favicon, app icon, OG watermark |

### 4.3 App Icon / Favicon

The **記** kanji rendered as a clean geometric SVG — designed with consistent `1.5` stroke weight matching Lucide icons. A small crescent moon arc sits in the upper-right corner.

```
記 glyph:   --color-patchouli  #7B4FA6
Moon arc:   --color-ribbon-gold #D4A017
Background: transparent (icon) · --color-void (OG image)

favicon.ico:    16×16, 32×32
apple-touch:    180×180
og:image:       1200×630 — 記 centered, wordmark below, moon phases at bottom
```

### 4.4 Co-existence with Voile

When both systems appear together in a system switcher, documentation, or navigation:

```
[記 Kiroku]  ◇  [Voile]
 Repository       Library System
```

Use a `◇` diamond or thin `|` divider. Never use the same mark for both.

### 4.5 Forbidden Modifications

- Never stretch or distort the wordmark
- Never substitute another font for *IM Fell English*
- Never omit the ribbon diamonds from the full variant
- Never render 記 from a web font — always the custom SVG mark
- Never place below `120px` wide or on backgrounds lighter than `--color-dusk` in dark contexts

---

## 5. Iconography & Decorative Elements

### 5.1 Functional Icons

All icons use **Lucide** (already in stack).

- Stroke width: `1.5` (lighter than Lucide default `2` — more refined)
- Inline size: `16px` · Standalone: `20px` · Header actions: `24px`
- Color: always inherit from context — never hardcode separately
- Style: outline only, never filled

### 5.2 Element Symbols — Item Type Watermarks

One thematic watermark per item type, drawn from Patchouli's seven elements.
Applied as `opacity: 0.07` SVG in the top-right corner of item cards.

| Element | Item Type | Symbol |
|---------|-----------|--------|
| **Wind / Wood** | `:skripsi` | Trefoil leaf / feather quill |
| **Fire** | `:karya_teknologi` | Upward flame triangle |
| **Water** | `:jurnal_internasional` | Wave arc / crescent drop |
| **Earth** | `:laporan_proyek` | Diamond / layered square grid |
| **Moon** | `:memorandum_hukum` | Crescent moon with single star |
| **Sun** | `:jurnal_nasional` | Sun disc with eight short rays |
| **Metal** | `:karya_kreatif` | Six-pointed star polygon |
| **Open Book** | `:studi_kasus` · `:prosiding` · `:capstone` | Stylized open book |

Hard limits: opacity never above `0.10`. Never on top of a cover image above `0.04`.

### 5.3 The Ribbon Stripe

A persistent `9px` horizontal bar (3 stripes × 3px) in the fixed order:
`--color-ribbon-red` → `--color-ribbon-gold` → `--color-ribbon-blue`

Used as:
- Horizontal accent **directly below the site header** on every page
- **Left border** on active sidebar nav items (vertical, tricolor split, `3px` total width)
- Decorative underline on the homepage hero wordmark

Order is always red → gold → blue. Never rearranged.

### 5.4 Ornamental Borders

Thin ruled section dividers inspired by old book chapter headers.

- Line: `1px solid rgba(123,79,166,0.30)`
- Corner accent: `4px` diamond in `--color-ribbon-gold`
- Used in: item detail page section dividers, top edge of modals, search results header

### 5.5 Moon Phase Divider

Five-phase SVG row (🌑 → 🌓 → 🌕 → 🌗 → 🌑) as a section separator.
Used only on: homepage (between hero and stats), about/info pages.
Never inside data-dense pages (search, tables, admin).

### 5.6 The 記 Watermark

Large, very faint 記 as a background watermark:
- Homepage hero: `opacity: 0.03`, `font-size: 400px`, centered behind hero text
- Empty states and 404: `opacity: 0.05`

Never on pages with dense content.

### 5.7 Forbidden Uses

- Element symbols above `opacity: 0.10`
- Moon phase divider inside cards, tables, or admin views
- Ribbon stripe in any order other than red → gold → blue
- 記 watermark on search, browse, or admin pages
- Stars (⭐) as decoration — reserved for citation/rating data only

---

## 6. Spacing & Layout

### 6.1 Spacing Scale (4px base)

```
--space-1:   4px    --space-6:  24px
--space-2:   8px    --space-8:  32px
--space-3:  12px    --space-10: 40px
--space-4:  16px    --space-12: 48px
--space-5:  20px    --space-16: 64px
                    --space-20: 80px
                    --space-24: 96px
```

### 6.2 Layout Grid

```
Max content width:   1280px
Page padding:        32px desktop / 16px mobile
Column gutter:       24px
Sidebar width:       280px
Item card min-width: 280px
```

### 6.3 Page Shell

```
┌──────────────────────────────────────────────────────┐
│  Header (64px) — 記 Kiroku · nav · search · user    │
├──────────────────────────────────────────────────────┤
│  Ribbon stripe (9px) — red · gold · blue            │
├────────────┬─────────────────────────────────────────┤
│  Sidebar   │  Main Content                           │
│  280px     │  Fluid                                  │
├────────────┴─────────────────────────────────────────┤
│  Footer — links · OAI-PMH · institution · Kiroku    │
└──────────────────────────────────────────────────────┘
```

---

## 7. Component Patterns

### 7.1 Item Card

```
┌──────────────────────────────────────────┐
│  [cover 80×113px]      [element symbol]  │
│  ──────────────────────────────────────  │  ← ornamental rule
│  [TYPE BADGE]                  [YEAR]    │
│  Title of the Work                       │  Cormorant Garamond text-lg
│  Author · Faculty · Degree               │  Inter text-sm --color-quill
│  Abstract excerpt, two lines max...      │  Source Serif 4 text-sm
│  [🔓 Akses Terbuka]  [📥 Unduh]  [🔗]  │
└──────────────────────────────────────────┘
```

- Background: `--color-grimoire`
- Border: `1px solid rgba(155,126,200,0.12)`, radius `8px`
- Hover: border → `rgba(155,126,200,0.35)`, shadow → `0 0 20px rgba(123,79,166,0.15)`
- No-cover placeholder: `--color-dusk` bg + element symbol at `opacity: 0.15`

### 7.2 Item Type Badge

| Item Type | Label | Text Color | Background |
|-----------|-------|-----------|------------|
| `:skripsi` | `SKRIPSI` | `--color-wisteria` | `rgba(45,27,105,0.60)` |
| `:memorandum_hukum` | `MEMO HUKUM` | `--color-ribbon-gold` | `rgba(212,160,23,0.15)` |
| `:studi_kasus` | `STUDI KASUS` | `--color-ribbon-blue` | `rgba(74,123,196,0.15)` |
| `:laporan_proyek` | `LAPORAN PROYEK` | `--color-wisteria` | `rgba(45,27,105,0.60)` |
| `:karya_kreatif` | `KARYA KREATIF` | `--color-ribbon-red` | `rgba(196,65,90,0.15)` |
| `:karya_teknologi` | `KARYA TEKNOLOGI` | `--color-ribbon-blue` | `rgba(74,123,196,0.15)` |
| `:jurnal_nasional` | `JURNAL SINTA` | `--color-ribbon-gold` | `rgba(212,160,23,0.15)` |
| `:jurnal_internasional` | `SCOPUS / WoS` | `--color-ribbon-amber` | `rgba(212,160,23,0.20)` |
| `:prosiding` | `PROSIDING` | `--color-ribbon-sky` | `rgba(74,123,196,0.15)` |
| `:capstone` | `CAPSTONE` | `--color-lavender` | `rgba(155,126,200,0.15)` |

Badge anatomy: `[element icon 12px] [LABEL — Inter text-xs font-semibold tracking-widest uppercase]`

### 7.3 Access Level Indicator

| Status | Icon (Lucide) | Label (ID) | Color |
|--------|--------------|-----------|-------|
| Open | `unlock` | Akses Terbuka | `--color-success` |
| Restricted | `lock` | Akses Terbatas | `--color-ribbon-blue` |
| Embargoed | `clock` | Embargo hingga [tanggal] | `--color-ribbon-gold` |
| Closed | `shield` | Tertutup | `--color-ribbon-red` |

### 7.4 Buttons

**Primary** (Download, Submit, Publish):
```
background:    --color-patchouli
color:         white
border-radius: 6px · padding: 10px 20px
font:          Inter 14px font-semibold
hover:         background --color-lavender + glow shadow
active:        background --color-dusk
```

**Secondary** (Cite, Edit, Browse):
```
background:    transparent
color:         --color-lavender
border:        1px solid rgba(155,126,200,0.40) · border-radius: 6px
hover:         background rgba(155,126,200,0.10)
```

**Ghost** (Cancel, Back):
```
background:    transparent · color: --color-quill · no border
hover:         color --color-wisteria
```

**Danger** (Withdraw, Delete):
```
background:    transparent
color:         --color-ribbon-red
border:        1px solid rgba(196,65,90,0.40) · border-radius: 6px
hover:         background rgba(196,65,90,0.10)
```

### 7.5 Form Inputs

```
background:    rgba(45,27,105,0.30)
border:        1px solid rgba(155,126,200,0.20) · border-radius: 6px
color:         --color-lilac · placeholder: --color-dust
padding:       10px 14px · font: Inter 14px

focus:  border --color-patchouli · box-shadow 0 0 0 3px rgba(123,79,166,0.20)
error:  border --color-ribbon-red · box-shadow 0 0 0 3px rgba(196,65,90,0.15)
```

Textarea: same + `min-height: 120px`, `resize: vertical`

### 7.6 Embargo Banner

```
background:    rgba(212,160,23,0.10)
border:        1px solid rgba(212,160,23,0.30)
border-left:   4px solid --color-ribbon-gold · border-radius: 8px
padding:       16px 20px · icon: clock (Lucide 20px) in --color-ribbon-gold
```

Text (ID): *"Berkas dalam status embargo hingga [tanggal]. Metadata dan abstrak tersedia secara publik."*

### 7.7 Navigation

**Top bar:**
- Background: `--color-grimoire` + `1px solid rgba(155,126,200,0.08)` bottom border
- Below: 9px ribbon stripe
- Wordmark: `記 Kiroku` in *IM Fell English* italic `text-2xl --color-lilac`
- Links: Inter `text-sm` `--color-quill` → `--color-wisteria` hover → `--color-lilac` active
- Active: `2px` underline in `--color-patchouli`

**Sidebar:**
- Background: `--color-grimoire`
- Section headers: Inter `text-xs` uppercase tracking-widest `--color-dust`
- Links: `--color-quill` → `--color-lavender` hover
- Active: `--color-lilac` text + `3px` tricolor left border + `rgba(123,79,166,0.10)` bg

### 7.8 Tables

```
thead:  bg rgba(45,27,105,0.50) · color --color-wisteria
        Inter text-xs font-semibold tracking-wider uppercase
        border-bottom 1px solid rgba(155,126,200,0.20)

tbody:  border-bottom 1px solid rgba(155,126,200,0.06)
        color --color-lilac · Inter text-sm · padding 12px 16px
        hover: bg rgba(155,126,200,0.05)
```

---

## 8. Motion & Interaction

### 8.1 Easing

```
--ease-out:    cubic-bezier(0.00, 0.00, 0.20, 1.00)  — entering
--ease-in:     cubic-bezier(0.40, 0.00, 1.00, 1.00)  — leaving
--ease-inout:  cubic-bezier(0.40, 0.00, 0.20, 1.00)  — transforming
--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1.00)  — playful micro
```

### 8.2 Duration Scale

```
--duration-instant:  80ms   — checkbox, button press
--duration-fast:    150ms   — hover, badge changes
--duration-base:    250ms   — panel slides, card hover
--duration-slow:    400ms   — modal open/close
--duration-lazy:    600ms   — large transitions, skeleton fade
```

### 8.3 Key Transitions

| Interaction | Duration | Easing |
|-------------|----------|--------|
| Button / nav hover | 150ms | `--ease-out` |
| Card hover | 200ms | `--ease-out` |
| Modal open | 250ms `scale(0.96→1)` | `--ease-spring` |
| Modal close | 200ms `scale(1→0.96)` | `--ease-in` |
| Sidebar expand | 300ms | `--ease-inout` |
| Toast / flash | 300ms `translateY` | `--ease-spring` |
| Skeleton shimmer | 1400ms linear | infinite |

### 8.4 Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 9. Page-Specific Design Notes

### 9.1 Homepage

- **Hero**: `--color-void` bg · faint 記 watermark `opacity: 0.03` · centered `記 Kiroku` in *IM Fell English* `text-5xl` · tagline in *Source Serif 4* italic `text-xl`
- **Moon phase divider** — between hero and stats
- **Stats row**: Total Karya · Total Unduhan · Total Koleksi — *Cormorant Garamond* `text-5xl`, *Inter* `text-xs` uppercase labels
- **Recent additions**: horizontal item card scroll
- **Browse by type**: 10-tile grid, each with element symbol + type label + count badge

### 9.2 Item Detail Page

```
[Breadcrumb: Beranda › Fakultas › Koleksi]
[TYPE BADGE]  [ACCESS INDICATOR]  [EMBARGO BANNER if active]

[Title — Cormorant Garamond text-3xl]
[Author · Year · Department · Degree]
[Ornamental divider]

[Abstract — Source Serif 4 text-base]
[Keywords — pill tags in --color-dusk]
[Ornamental divider]

[Two columns:]
  Left  60%:  File list by bundle
  Right 40%:  Metadata table
              Cite (BibTeX / RIS / EndNote)
              Statistics (views · downloads)
              Handle [JetBrains Mono]

[Related items — same collection]
```

File list by bundle:
- `ORIGINAL` → large primary download button
- `CHAPTER` → numbered list with chapter labels
- `SUPPLEMENTAL` → smaller, secondary styling
- `ADMINISTRATIVE` / `LICENSE` → staff only, `lock` icon + *"Akses staf"* in `--color-ribbon-blue`

### 9.3 Search Page

- Full-width search bar + `--color-patchouli` focus ring
- Sidebar facets: Fakultas, Tahun, Tipe Karya, Tingkat Akses, Jenjang — each collapsible
- Results: card view (default) ↔ table view toggle
- Count: *"Ditemukan 1.247 karya"* — *Cormorant Garamond* italic
- Empty state: 記 mark + *"Rak buku sedang lengang. Coba kata kunci lain."*

### 9.4 Admin Panel (AshAdmin)

CSS-level overrides only — never rebuild:
- Backgrounds → `--color-grimoire` / `--color-dusk`
- Primary blue → `--color-patchouli`
- Inputs → Section 7.5 pattern
- Tables → Section 7.8 pattern
- Font → force *Inter* for all AshAdmin chrome

### 9.5 Submission Wizard

```
Step 1 → Pilih Tipe & Koleksi        (drives all subsequent field visibility)
Step 2 → Informasi Bibliografi        (title, abstract, keywords, language)
Step 3 → Orang-orang yang Terlibat   (authors, advisors, examiners, team)
Step 4 → Klasifikasi & Tanggal       (degree, department, dates, type-specific)
Step 5 → Berkas                      (upload per bundle with format guidance)
Step 6 → Akses & Embargo             (access_level, embargo_open_date)
Step 7 → Tinjau & Kirim              (full summary before submission)
```

Progress stepper: horizontal circles. Completed → `--color-patchouli` fill. Current → `--color-lavender` border. Upcoming → `--color-dusk` fill, `--color-quill` text.

---

## 10. Writing Style

### Voice

Scholarly but warm. Like a librarian who takes every submission seriously.
Indonesian is the primary UI language.

### Tone by Context

| Context | Example |
|---------|---------|
| Empty state | *"Rak buku sedang lengang. Jadilah yang pertama menyimpan karya di sini."* |
| Error | *"Judul wajib diisi. Silakan tambahkan judul sebelum melanjutkan."* |
| Success | *"Karya berhasil dikirim. Sedang menunggu tinjauan."* |
| Embargo | *"Berkas dalam embargo hingga 1 Januari 2027. Abstrak dan metadata tersedia secara publik."* |
| Restricted | *"Berkas ini memerlukan autentikasi. Silakan masuk untuk melanjutkan."* |
| Admin | *"Karya dipublikasikan. Kini dapat ditemukan melalui pencarian."* |

### Display Name Conventions

| System value | Tampilan (ID) | Display (EN) |
|-------------|--------------|-------------|
| `:skripsi` | Skripsi | Undergraduate Thesis |
| `:jurnal_internasional` | Jurnal Internasional | International Journal Article |
| `:ORIGINAL` | Dokumen Utama | Primary Document |
| `:ADMINISTRATIVE` | Dokumen Administratif | Administrative Document |
| `:open` | Akses Terbuka | Open Access |
| `:restricted` | Akses Terbatas | Restricted Access |
| `:embargoed` | Dalam Embargo | Under Embargo |
| `:under_review` | Sedang Ditinjau | Under Review |
| `:published` | Dipublikasikan | Published |
| `:withdrawn` | Ditarik | Withdrawn |

---

## 11. Tailwind CSS Configuration

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        void:             '#0D0817',
        grimoire:         '#1A1030',
        dusk:             '#2D1B69',
        patchouli:        '#7B4FA6',
        lavender:         '#9B7EC8',
        wisteria:         '#C4A8E0',
        lilac:            '#E8DFF5',
        'ribbon-red':     '#C4415A',
        'ribbon-crimson': '#8B2340',
        'ribbon-gold':    '#D4A017',
        'ribbon-amber':   '#E8C547',
        'ribbon-blue':    '#4A7BC4',
        'ribbon-sky':     '#7AABD8',
        ink:              '#1C1420',
        quill:            '#6B5F78',
        dust:             '#9E93AB',
        parchment:        '#F5F0E8',
        vellum:           '#EDE8DC',
        ivory:            '#FAF7F2',
      },
      fontFamily: {
        display: ['"IM Fell English"', 'serif'],
        heading: ['"Cormorant Garamond"', 'serif'],
        body:    ['"Source Serif 4"', 'serif'],
        ui:      ['Inter', 'sans-serif'],
        mono:    ['"JetBrains Mono"', 'monospace'],
      },
      boxShadow: {
        'glow-patchouli': '0 0 20px rgba(123,79,166,0.25)',
        'glow-gold':      '0 0 16px rgba(212,160,23,0.20)',
        'card':           '0 2px 8px rgba(13,8,23,0.40)',
        'card-hover':     '0 4px 24px rgba(13,8,23,0.60)',
      },
      borderRadius: {
        card:  '8px',
        badge: '4px',
        pill:  '999px',
      },
    },
  },
}
```

---

## 12. Quick Reference Card

```
PROJECT         Kiroku 記録 — Institutional Knowledge Repository
SIBLING         Voile  — GLAM Management System

PRIMARY         #7B4FA6  Patchouli Purple
DARK SURFACE    #1A1030  Grimoire
PAGE BG         #0D0817  Library Void

RIBBON RED      #C4415A     RIBBON GOLD    #D4A017     RIBBON BLUE    #4A7BC4

DISPLAY FONT    IM Fell English      — wordmark, hero H1 only
HEADING FONT    Cormorant Garamond   — H2 through H4
BODY FONT       Source Serif 4       — abstracts, body copy
UI FONT         Inter                — labels, buttons, navigation
MONO FONT       JetBrains Mono       — handles, DOIs, NIM/NPM

ICONS           Lucide · stroke-width 1.5
MOTION          250ms cubic-bezier(0.00, 0.00, 0.20, 1.00)
RADIUS          8px cards · 6px buttons · 4px badges · 999px pills

ELEMENT MAP
  Wind  →  :skripsi               Fire   →  :karya_teknologi
  Water →  :jurnal_internasional  Earth  →  :laporan_proyek
  Moon  →  :memorandum_hukum      Sun    →  :jurnal_nasional
  Metal →  :karya_kreatif         Book   →  :studi_kasus · :prosiding · :capstone
```
