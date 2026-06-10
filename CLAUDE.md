# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repository

This is a **design-phase project** — no code exists yet. The only artifact is `DESIGN.md`, the authoritative specification for Kronicle, a personal storybuilding ideas vault. Per the doc's own header: read DESIGN.md first before building anything, and when the design changes, update DESIGN.md. There are no build, lint, or test commands yet.

## What Kronicle is (from DESIGN.md)

Two clients, one backend:

- **Backend**: Cloudflare Workers + Hono + D1 (SQLite) + Drizzle ORM, media in R2, AI proxied to DeepSeek. Auth is a single static bearer token (personal tool, no user accounts).
- **Web**: SvelteKit on Cloudflare Workers. The token never reaches the browser — all API calls go through SvelteKit server routes.
- **Mobile**: Flutter (Android), online-first with in-memory response caching.

## Core design decisions to preserve

These are settled (see "Resolved Decisions" in DESIGN.md — 20 numbered entries with rationale):

- **Unified data model**: one `entities` table (8 types: character, location, faction, lore, story, chapter, event, ability) + one `relationships` table. Type-specific fields live in a `metadata` JSON column; `status` (stub/draft/canon/rejected) is a real indexed column. `parent_id` enables nesting; deleting an entity with children is blocked.
- **Immutable opaque IDs + renameable slugs.** Slug renames atomically rewrite `[[wikilinks]]` across all content server-side.
- **Wikilinks `[[slug]]` are render-only** — they never create relationship rows. Backlinks are computed at read time via `LIKE`.
- **Status loop is the product**: capture → stub → draft → canon/rejected. Quick capture (name → stub) must stay one step.
- **AI never writes without explicit approval.** AI endpoints return suggestions/proposals only. The chat endpoint (`POST /api/ai/chat`) is stateless with a server-side tool loop: read tools execute freely, write tools are intercepted and returned as proposal objects the client applies through normal REST endpoints. The AI tool set excludes deletes, slug, and status changes; AI-created entities land as `draft`.
- **Every content-changing save snapshots a revision** (last 20 per entity) — losing prose is the worst possible failure; the editor also autosaves with a localStorage backup.
- **Eras are validated**: `metadata.era` must match an existing era lore entity's slug.

## Build order

Phases in DESIGN.md: (1) Worker API + SvelteKit web CRUD, (2) Flutter app + timeline, (3) graph/export/AI/revisions including per-entity AI chat, (4) vault-wide AI chat. Don't build both clients simultaneously.

## Conventions

- Personal-scale pragmatism is the doc's explicit ethos: `LIKE` search over FTS, read-time backlinks over stored rows, simple cache invalidation over clever. Match that bar — don't propose infrastructure the scale doesn't need.
- DESIGN.md style: h2/h3 sections, tables for schemas and decisions, code blocks for endpoint contracts, prose with rationale. New settled choices go in the "Resolved Decisions" table; open questions go in "Remaining (decide during implementation)". Update the dated changelog line at the top.
