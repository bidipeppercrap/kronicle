# Kronicle — Flutter (Android) client

The mobile client for Kronicle. Online-first; talks to the same Worker API as
the web app. Built for Phase 2 (quick capture, browse, read, basic editing,
timeline, search) and Phase 4 (the route-aware AI chat). See `../DESIGN.md`.

## Prerequisites

- Flutter (stable) — built against 3.44.
- The Worker API running and reachable. For local dev: `cd ../worker && npx wrangler dev`
  (binds `127.0.0.1:8787`; the AI chat needs `DEEPSEEK_API_KEY` in `worker/.dev.vars`).

## Configuration

The server URL and bearer token are entered **in-app** (Settings) and stored
with `flutter_secure_storage` — the token is encrypted at rest behind the
Android Keystore, and **the APK embeds no secret**, so the build can be
distributed. On a fresh install the app opens onto a connect screen; tap the
gear on Home to change it later. There is still no in-app login: each install
holds its own token; Cloudflare Access gates the *web* app, not the phone
(DESIGN.md, Auth).

`--dart-define` values remain as **dev seeds** only — they pre-fill an
unconfigured install so `flutter run` against the local Worker works without
typing anything. A distributed release passes no defines, so the fields start
empty.

| Define (dev seed) | Suggested value | Notes |
|--------|---------|-------|
| `KRONICLE_API_URL` | `http://10.0.2.2:8787` | `10.0.2.2` is the host's `127.0.0.1` from the **Android emulator**. |
| `KRONICLE_API_TOKEN` | `dev-token` | Matches `worker/.dev.vars`. |

- **Emulator → local Worker:** seed with the defines above, or type them in Settings.
- **Physical device → local Worker:** use your machine's LAN IP, e.g.
  `http://192.168.1.x:8787`.
- **Deployed Worker:** `https://kronicle-api.<account>.workers.dev` and the
  production `API_TOKEN`.

Cleartext HTTP to `10.0.2.2`/LAN IPs works in debug builds (Flutter's debug
manifest permits cleartext). A release build talking to a plain-HTTP host would
need a network-security config; pointing release at the HTTPS Worker avoids that.

`minSdk` is pinned to 23 — the floor for the encrypted-storage backend.

## Run

Start an Android emulator first (the defaults assume one — `10.0.2.2` is the
emulator's route to the host's `127.0.0.1`). List the available AVDs and launch
one, or start it from Android Studio's Device Manager:

```bash
flutter emulators                 # list configured emulators
flutter emulators --launch <id>   # boot one, e.g. Pixel_7_API_34
flutter devices                   # confirm the emulator is attached
```

With the emulator running, install dependencies and start the app:

```bash
flutter pub get
flutter run \
  --dart-define=KRONICLE_API_URL=http://10.0.2.2:8787 \
  --dart-define=KRONICLE_API_TOKEN=dev-token
```

```bash
flutter analyze
flutter test
# Distributable build — no token baked in; recipients connect via Settings.
flutter build apk --release
```

## Layout

```
lib/
  config.dart            # base URL + token: secure-storage backed, dart-define seeds
  nav.dart               # navigator + messenger keys, openEntity/openEditor helpers
  api/                   # models.dart, api_client.dart (bearer auth + in-memory cache)
  theme/theme.dart       # warm-editorial Material 3 (light/dark, status colors, flat)
  state/chat_context.dart# route-aware focus stack, editor bridge, refresh bus
  shell/app_shell.dart   # bottom-nav: Home · Entities · Timeline · Search
  widgets/               # status chip, entity tile, markdown (wikilinks), async view
  screens/               # home, list, detail, editor, timeline, search, settings, pickers
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
