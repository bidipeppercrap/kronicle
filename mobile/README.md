# Kronicle — Flutter (Android) client

The mobile client for Kronicle. Online-first; talks to the same Worker API as
the web app. Built for Phase 2 (quick capture, browse, read, basic editing,
timeline, search) and Phase 4 (the route-aware AI chat). See `../DESIGN.md`.

## Prerequisites

- Flutter (stable) — built against 3.44.
- The Worker API running and reachable. For local dev: `cd ../worker && npx wrangler dev`
  (binds `127.0.0.1:8787`; the AI chat needs `DEEPSEEK_API_KEY` in `worker/.dev.vars`).

## Configuration

The app embeds the bearer token — an accepted risk for a personal device
(DESIGN.md, Auth). There is no in-app login; Cloudflare Access gates the *web*
app, not the phone. Supply the API URL and token with `--dart-define`:

| Define | Default | Notes |
|--------|---------|-------|
| `KRONICLE_API_URL` | `http://10.0.2.2:8787` | `10.0.2.2` is the host's `127.0.0.1` from the **Android emulator**. |
| `KRONICLE_API_TOKEN` | `dev-token` | Matches `worker/.dev.vars`. |

- **Emulator → local Worker:** defaults work as-is.
- **Physical device → local Worker:** pass your machine's LAN IP, e.g.
  `--dart-define=KRONICLE_API_URL=http://192.168.1.x:8787`.
- **Deployed Worker:** `--dart-define=KRONICLE_API_URL=https://kronicle-api.<account>.workers.dev`
  and the production `API_TOKEN`.

Cleartext HTTP to `10.0.2.2`/LAN IPs works in debug builds (Flutter's debug
manifest permits cleartext). A release build pointed at a plain-HTTP host would
need a network-security config; pointing release at the HTTPS Worker avoids that.

## Run

```bash
flutter pub get
flutter run \
  --dart-define=KRONICLE_API_URL=http://10.0.2.2:8787 \
  --dart-define=KRONICLE_API_TOKEN=dev-token
```

```bash
flutter analyze
flutter test
flutter build apk --release --dart-define=KRONICLE_API_URL=… --dart-define=KRONICLE_API_TOKEN=…
```

## Layout

```
lib/
  config.dart            # --dart-define base URL + token
  nav.dart               # navigator + messenger keys, openEntity/openEditor helpers
  api/                   # models.dart, api_client.dart (bearer auth + in-memory cache)
  theme/theme.dart       # warm-editorial Material 3 (light/dark, status colors, flat)
  state/chat_context.dart# route-aware focus stack, editor bridge, refresh bus
  shell/app_shell.dart   # bottom-nav: Home · Entities · Timeline · Search
  widgets/               # status chip, entity tile, markdown (wikilinks), async view
  screens/               # home, list, detail, editor, timeline, search, pickers
  chat/                  # controller (SSE + proposals), panel, host (bubble), diff
assets/fonts/            # Literata, Inter, iA Writer Quattro (bundled, SIL OFL)
```

## Notes

- **Caching** is in-memory, keyed by request URL, with the TTLs from DESIGN.md
  (detail ~7 min, list ~90 s, timeline ~2 min, search uncached). Any write
  clears the whole cache.
- **AI chat** streams over SSE from `POST /api/ai/chat`; write tools arrive as
  proposals (diff/change cards) that apply through the normal REST endpoints —
  nothing changes without an explicit Apply.
- **Fonts** are bundled APK assets (no `google_fonts`, no Google requests),
  mirroring the web's self-hosted decision.
