# Kronicle

A personal **storybuilding ideas vault**: capture ideas the moment they strike as stubs, develop them into drafts, then promote them to canon or reject them. See [DESIGN.md](DESIGN.md) for the full specification — read it first, and update it when the design changes.

## Repository layout

| Directory | What it is |
|-----------|------------|
| `worker/` | The API — Cloudflare Workers + Hono + D1 (SQLite) via Drizzle ORM, media in R2, AI proxied to DeepSeek |
| `web/` | The web client — SvelteKit on Cloudflare Workers, talks to the Worker from server routes only (the API token never reaches the browser) |

A Flutter Android client is planned for Phase 2 (see the build phases in DESIGN.md).

## Running the dev servers

You need two terminals: the Worker API first, then the web app.

### 1. Worker API (`worker/`, runs on http://localhost:8787)

```sh
cd worker
npm install
```

Create `worker/.dev.vars` (gitignored) with the local secrets:

```ini
API_TOKEN=dev-token
# Optional — only needed for the AI endpoints (/api/ai/*):
# DEEPSEEK_API_KEY=sk-...
```

Apply the database migrations to the local D1 instance, then start the server:

```sh
npm run db:migrate:local
npm run dev
```

Sanity check: `http://localhost:8787/api/entities` should return JSON (401 without the bearer token is also a good sign — the server is up).

### 2. Web app (`web/`, runs on http://localhost:5173)

```sh
cd web
npm install
```

Copy `web/.env.example` to `web/.env` — the defaults already point at the local Worker:

```ini
API_URL=http://localhost:8787
API_TOKEN=dev-token   # must match worker/.dev.vars
```

Then:

```sh
npm run dev
```

Open http://localhost:5173. The dashboard's quick capture box is the fastest way to confirm the two servers are talking.

## Other commands

| Command | Where | What it does |
|---------|-------|--------------|
| `npm test` | `worker/` | API test suite (vitest, runs against an in-memory D1 with migrations applied) |
| `npm run check` | `web/` | svelte-check / TypeScript validation |
| `npm run build` | `web/` | Production build (Cloudflare adapter) |
| `npm run db:generate` | `worker/` | Generate a new Drizzle migration after editing `src/db/schema.ts` |
| `npm run db:migrate:remote` | `worker/` | Apply migrations to the production D1 database |

## Deployment

Two Cloudflare Workers — deploy the API first, then the web app.

### 1. Worker API (`worker/`)

One-time setup:

```sh
cd worker
wrangler d1 create kronicle          # paste the returned id into worker/wrangler.jsonc (replaces the 0000… placeholder)
wrangler r2 bucket create kronicle-media
wrangler secret put API_TOKEN        # your real production bearer token
wrangler secret put DEEPSEEK_API_KEY # only if you use the /api/ai/* endpoints
```

Each deploy:

```sh
npm run db:migrate:remote            # apply migrations to the production D1
npm run deploy                       # wrangler deploy → kronicle-api.<account>.workers.dev
```

### 2. Web app (`web/`)

One-time setup — edit `web/wrangler.jsonc` and replace `<account>` in the `API_URL` var with the deployed Worker API URL from step 1, then set the token (it's a secret, so it lives outside `wrangler.jsonc`):

```sh
cd web
wrangler secret put API_TOKEN        # must match worker/'s API_TOKEN
```

Each deploy:

```sh
npm run deploy                       # vite build + wrangler deploy → kronicle.<account>.workers.dev
```

`API_URL` and `API_TOKEN` are read server-side only (`$env/dynamic/private`); the token never reaches the browser.

### 3. Lock down the web app — Cloudflare Access (required)

The server-route proxy attaches the API token for *any* visitor to the public URL, so the deployed web app **must** sit behind **Cloudflare Access** (Zero Trust free tier, email allowlist) before you share the URL. It's dashboard-only, zero code — the one-time runbook is in DESIGN.md's Auth section.
