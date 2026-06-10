# Spelltest Grimoire — Design Document

> Written 2026-06-09. Updated: dual-platform (web + Android) with shared API.
> This is the reference for building the app.
> When building, read this first. When the design changes, update this.

---

## Overview

Two apps, one backend. A **SvelteKit web app** and a **Flutter Android app** — both talking to the same **Cloudflare Workers API** backed by **D1 (SQLite)**. Both platforms do full read and write. The convenience split is natural (keyboard on desktop, pocket on phone) but neither platform is restricted. AI writing assistance via the same API. Export to portable Markdown from either platform.

```
┌─────────────────────┐     ┌─────────────────────┐
│  SvelteKit (Web)    │     │  Flutter (Android)   │
│  Cloudflare Pages   │     │  APK on device       │
└────────┬────────────┘     └────────┬────────────┘
         │  REST API                 │  REST API
         └───────────┬───────────────┘
                     │
         ┌───────────▼───────────────┐
         │  Cloudflare Workers API   │
         │  /api/entities            │
         │  /api/relationships       │
         │  /api/ai/*                │
         │  /api/export              │
         └───────────┬───────────────┘
                     │
         ┌───────────▼───────────────┐
         │  Cloudflare D1 (SQLite)   │
         │  entities                 │
         │  relationships            │
         │  media                    │
         └───────────────────────────┘
```

---

## Data Model — Unified Graph on Relational Tables

### Why unified

A location, a character, and a faction all share the same core shape: an id, a name, a type, some prose content, and relationships to other entities. One entity table + one relationship table is simpler than separate tables per type and more flexible — any entity can relate to any other without schema changes. A `parent_id` column enables nesting (chapters under stories, buildings under cities, sub-factions).

### Entity types

| Type | Purpose |
|------|---------|
| `character` | Named individuals with unique abilities |
| `location` | Towns, cities, forests, regions, buildings |
| `faction` | Groups, guilds, covens, families |
| `lore` | Magic systems, history, religions, artifacts, creatures |
| `story` | Narrative arcs — a collection of chapters |
| `chapter` | A single chapter/scene within a story (nested under parent story) |
| `event` | A point on the timeline — character births, battles, discoveries |
| `ability` | A unique power — rooted in a principle, wielded by characters |

### Tables

#### entities

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | Slug, e.g. `guli`, `bangsur-town`, `palm-of-destruction` |
| `type` | TEXT | `character`, `location`, `faction`, `lore`, `story`, `chapter`, `event`, `ability` |
| `parent_id` | TEXT FK → entities.id | For nesting: chapter → story, building → city, sub-faction → faction. Null for top-level |
| `name` | TEXT | Display name |
| `summary` | TEXT | Short blurb (1–2 sentences), used in list views and cards |
| `content` | TEXT | Full Markdown prose — backstory, description, story text |
| `metadata` | JSON | Type-specific fields, status, extra attributes (see below) |
| `created_at` | TEXT | ISO timestamp |
| `updated_at` | TEXT | ISO timestamp |

#### relationships

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `source_id` | TEXT FK → entities.id | The entity declaring the relationship |
| `target_id` | TEXT FK → entities.id | The entity being pointed to |
| `type` | TEXT | Relationship verb (see table below) |
| `label` | TEXT | Human-readable edge label, e.g. "childhood friend" |
| `metadata` | JSON | Extra context, e.g. `{"joined_year": 342, "left_year": 350}` |

**Direction rule:** relationships are single-source. You declare "Guli was born in Bangsur Town" once as `source: guli, target: bangsur-town, type: born_in`. The API returns relationships from both directions when querying.

#### Relationship types

| Type | From → To | Meaning |
|------|-----------|---------|
| `born_in` | character → location | Birthplace |
| `resides_in` | character → location | Current residence |
| `member_of` | character → faction | Faction membership |
| `leader_of` | character → faction | Leads the faction |
| `possesses` | character → ability | Character wields this ability |
| `friend_of` | character → character | Friendship |
| `rival_of` | character → character | Rivalry / enmity |
| `related_to` | any → any | Generic connection (catch-all) |
| `appears_in` | character → chapter | Character appears in this chapter |
| `setting_of` | location → chapter | Chapter takes place here |
| `occurs_at` | event → location | Event happened here |
| `involves` | event → character | Character participated in event |
| `depicts` | story/chapter → event | Story depicts this timeline event |
| `causes` | event → event | Causal chain: this event caused that event |
| `headquarters_of` | location → faction | Faction is based here |

#### media

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `entity_id` | TEXT FK → entities.id | Owning entity |
| `url` | TEXT | URL (R2 key or base64 data URI for small images) |
| `media_type` | TEXT | `portrait`, `illustration`, `reference`, `logo` |
| `alt_text` | TEXT | Accessibility / caption |

---

### Status system

Every entity has a `status` in its metadata:

| Status | Meaning |
|--------|---------|
| `canon` | Confirmed part of the main story. Fully integrated. |
| `draft` | Under consideration. May or may not become canon. |
| `rejected` | Explicitly not canon. Alternate idea, abandoned concept. |
| `stub` | Placeholder — name/idea exists, no prose yet. Needs writing. |

---

### Metadata conventions (JSON column)

All entities share `status`. Adding a field is a UI change, not a migration.

**Character:**
```json
{ "status": "canon", "gender": "male", "species": "human", "age": 22, "is_npc": false }
```

**Location:**
```json
{ "status": "canon", "location_type": "town", "climate": "temperate", "population": 500 }
```

**Faction:**
```json
{ "status": "canon", "category": "godlike-coven", "member_count": 4 }
```

**Lore:**
```json
{ "status": "draft", "category": "magic-system", "era": "age-of-awakening" }
```

**Story:**
```json
{ "status": "draft", "chapter_count": 2, "is_complete": false }
```

**Chapter:**
```json
{ "status": "draft", "order": 1 }
```

**Event (timeline):**
```json
{ "status": "canon", "date": "Year 342, 3rd Moon, 15th Day", "era": "age-of-conflict", "order_index": 42, "precision": "exact" }
```

**Ability:**
```json
{ "status": "canon", "principle": "destruction", "category": "palm-based", "range": "contact" }
```

---

### NPCs vs. Characters

A town may have 500 residents. Only named, story-relevant characters become entities. The 500 is just `metadata.population`.

---

### Abilities — first-class entities

Every Spell Test character has a unique ability rooted in a "principle." Abilities are their own entity type (`character → possesses → ability`). They have full Markdown `content` for mechanics, origin, and limitations.

The principle behind all abilities (the "principle of power") is described once in a `lore` entity — not repeated per ability. Each ability's metadata tags which principle it stems from (e.g. `"principle": "destruction"`), linking back to that lore entry conceptually.

---

### Nesting via `parent_id`

- `chapter` entities nest under their parent `story`
- Sub-locations (buildings) nest under parent locations (cities)
- Sub-factions nest under parent factions

---

### Timeline — chronological precision

Events (`type: event`) are the backbone of the timeline:
- Character births, deaths, major life moments
- Battles, discoveries, faction foundings
- Story chapter occurrences

Relationships: `occurs_at` (location), `involves` (character), `causes` (event → event), `depicts` (story → event).

The Timeline view renders all `canon` events sorted by `metadata.order_index`, grouped by `era`.

---

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Database** | Cloudflare D1 (SQLite at edge) | Free: 5 GB, 5M reads/day. Single source of truth for both clients |
| **Backend API** | Cloudflare Workers + Hono | Routing, validation, CORS middleware. Free: 100K requests/day |
| **Web frontend** | SvelteKit → Cloudflare Pages | Your existing stack. Desktop-first editing experience |
| **Mobile app** | Flutter (Android) | Your existing stack. Phone-first reading experience |
| **ORM (Worker)** | Drizzle | Already used in `bidipeppercrap-api` |
| **HTTP (Flutter)** | `dio` | Interceptors for caching, retry, auth token injection |
| **State (Flutter)** | Riverpod | Modern. Swap if your projects use Provider/BLoC/GetX |
| **Markdown (Flutter)** | `flutter_markdown` | Renders prose with custom link handling |
| **AI** | Same Worker (`/api/ai/*`) → DeepSeek | One proxy, both clients share it |
| **Media** | Cloudflare R2 | Free: 10 GB. Portraits, illustrations, logos. Keeps DB lean |
| **Auth** | Simple static token in headers | Personal tool, not public |

### Why Cloudflare

- D1 + Workers + Pages are all under one free tier umbrella
- You already deploy to Cloudflare (`bidipeppercrap-api` has `wrangler.json`)
- Zero cold starts, global edge, generous limits for a solo tool

---

## API Design

The Worker serves a REST API. Both clients consume the same endpoints.

### Entities

```
GET    /api/entities?type=character&status=canon&search=guli&limit=50&offset=0
GET    /api/entities/:id                    → entity + relationships + media
POST   /api/entities                        → create
PUT    /api/entities/:id                    → update
DELETE /api/entities/:id                    → cascade: removes relationships & media
```

### Relationships

```
GET    /api/entities/:id/relationships      → all relationships for this entity (both directions)
POST   /api/relationships                   → { source_id, target_id, type, label, metadata }
DELETE /api/relationships/:id
```

### Media

```
GET    /api/entities/:id/media
POST   /api/media                           → multipart upload or base64
DELETE /api/media/:id
```

### AI

```
POST   /api/ai/polish                       → { content, notes, entity_type, metadata }
POST   /api/ai/expand                       → { summary, entity_type, metadata }
POST   /api/ai/suggest-relationships        → { entity_id, target_id }
```

### Timeline & Search

```
GET    /api/timeline?era=age-of-conflict&status=canon
GET    /api/search?q=guli&type=character
GET    /api/export                          → returns zip of Markdown files + grimoire.json
```

### Auth

All requests include header: `Authorization: Bearer <static-token>`. Worker validates it. Simple, no user accounts.

---

## App Screens

### Web (SvelteKit)

| Route | Purpose |
|-------|---------|
| `/` | Dashboard — recent entities, quick stats |
| `/entities` | List with type tabs, status filter, search, sort |
| `/entities/[id]` | Detail — metadata sidebar, rendered Markdown, auto-linked mentions, media gallery, relationships, children |
| `/entities/[id]/edit` | Editor — metadata form, Markdown editor, AI buttons, relationship picker |
| `/entities/new?type=character` | Create |
| `/timeline` | Chronological feed grouped by era |
| `/graph` | Force-directed relationship graph |
| `/search` | Full-text across all entities |
| `/export` | Download zip |

### Mobile (Flutter)

| Screen | Purpose |
|--------|---------|
| **Home** | Dashboard — recent, stats, tap to jump |
| **Entity List** | Type tabs, status filter, search |
| **Entity Detail** | Full read: metadata cards, Markdown, auto-links, media, relationships, children |
| **Entity Editor** | Form + Markdown field + AI buttons + relationship picker |
| **Timeline** | Vertical feed grouped by era, tap to detail |
| **Graph** | Interactive graph, pinch-zoom, tap to navigate |
| **Search** | Full-text grouped by type |
| **Export** | Generate → share sheet |

---

## Offline & Caching Strategy

Both apps are online-first. D1 is the single source of truth. Network latency to Cloudflare's edge is 20-80ms from Indonesia on mobile — near-instant for list and detail views.

### Response caching (Flutter)

The Flutter app caches API responses to eliminate repeated network calls:

| Cache scope | TTL | Rationale |
|-------------|-----|-----------|
| Entity detail + relationships + media | 5-10 min | Prose changes rarely. Most reads hit cache. |
| Entity list (filtered) | 1-2 min | Stale lists are acceptable for short windows |
| Timeline | 2 min | Events are stable |
| Search results | no cache | Always fresh |

Cache is in-memory (a Map keyed by request URL). Cleared on app restart. Edits and creates invalidate the relevant cache entries immediately — you never see stale data you just wrote.

**Result:** the app feels local. Scrolling through your characters, jumping between entities, re-reading lore — all cache hits. The network only wakes when you edit or when a cache entry expires.

### True offline (no signal)

- Export from web → download zip → import into Flutter app
- Flutter app renders entities from the imported zip
- This is a v1.5 feature — not in the initial build

### Full sync (future)

- Flutter app gets a local SQLite mirror
- Periodic sync via `GET /api/entities?updated_since=<timestamp>`
- Conflict resolution: server wins (web edits are authoritative)

---

## Export (Portability)

Available from both web (download) and Flutter (share sheet).

**Format:** zip containing one Markdown file per entity (YAML frontmatter + prose) + `grimoire.json` manifest + all media files. Lossless round-trip — can be re-imported into a fresh D1 instance.

---

## Resolved Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Principles are a `lore` entity, not separate entities | Described once. Abilities tag which principle they stem from |
| 2 | Media in Cloudflare R2, not base64 in DB | Keeps the database lean. R2 free tier: 10 GB |
| 3 | Hono for the Worker API framework | Routing, validation, CORS out of the box |
| 4 | `dio` for Flutter HTTP | Interceptors for caching, retry, auth token injection |
| 5 | Shared D1 backend with response caching | Real-time sync between platforms, cache makes it feel local |

## Remaining (decide during implementation)

| # | Question | Options |
|---|----------|---------|
| 1 | Graph rendering on mobile | `CustomPainter` widget vs. WebView + D3. Prototype both, pick what performs |
| 2 | Multi-device sync | Not in v1. Export/import covers the gap. Revisit when phone ↔ desktop real-time is needed |
