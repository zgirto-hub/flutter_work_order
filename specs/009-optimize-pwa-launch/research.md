# Research: Optimize iPhone PWA Launch Performance

**Feature**: 009-optimize-pwa-launch  
**Date**: 2026-04-03

## Research Summary

No NEEDS CLARIFICATION items. Research focused on identifying root causes and selecting optimal approaches for each optimization story.

## Decision 1: Nginx Gzip Configuration

**Decision**: Add gzip compression directives to `nginx_flutter_app.conf` for JS, CSS, WASM, JSON, TTF/WOFF, and SVG assets.

**Rationale**: The current Nginx config has no gzip directives at all. Adding them reduces the 18.5 MB total payload to ~6.5 MB (65% reduction). This is a server-only change with zero risk to app functionality. Gzip is universally supported by all browsers including iOS Safari.

**Key config additions**:
- `gzip on` with `gzip_vary on`
- `gzip_min_length 1024` (skip tiny files)
- Types: `application/javascript`, `application/wasm`, `application/json`, `text/css`, `text/html`, `font/ttf`, `font/woff2`, `image/svg+xml`
- `gzip_comp_level 6` (good balance of compression ratio vs CPU)

**Alternatives considered**:
- Brotli compression: Better ratios but requires nginx module compilation. Not worth the server maintenance complexity for this single-server setup.
- Pre-compressed static files (gzip_static): Would require build-time compression step. Good future enhancement but gzip on-the-fly is simpler to start.

## Decision 2: Service Worker Caching Strategy

**Decision**: Replace the self-unregistering service worker with a version-based cache-first worker generated during deploy.

**Rationale**: The current service worker (`flutter_service_worker.js`) literally unregisters itself on activate — it was written as a cleanup mechanism for a previous broken SW. This means every launch is a full cold start. A proper cache-first strategy with version-based invalidation would make repeat launches near-instant.

**Strategy**: Cache-first with network-fallback:
1. On install: precache critical assets (main.dart.js, canvaskit.wasm, fonts, index.html)
2. On fetch: serve from cache first, fall back to network
3. On new version deploy: deploy script generates a new SW with a new cache version string → browser detects change → old cache is evicted, new assets cached
4. The deploy script already generates `release.json` with a unique `release_id` — use this as the cache version key

**iOS Safari limitations to account for**:
- iOS limits cache storage to ~50 MB per origin (our assets are ~18 MB, well within limit)
- iOS may evict caches after 7 days of inactivity (acceptable — cold start is still faster with compression)
- Service worker `skipWaiting()` + `clients.claim()` for immediate activation

**Alternatives considered**:
- Workbox library: Overkill for this use case; adds another dependency. A simple hand-written SW is ~50 lines.
- Flutter's built-in service worker: Was the original but caused navigation loop issues — that's why it was replaced with the unregister-only version. A custom SW avoids this.

## Decision 3: OneSignal SDK Loading Strategy

**Decision**: Move OneSignal SDK initialization to after Flutter engine has loaded, using a deferred pattern.

**Rationale**: The current `index.html` loads OneSignal SDK from CDN (`cdn.onesignal.com`) and runs `OneSignal.init()` in an inline script block. While the script tag has `defer`, the inline initialization script runs immediately and blocks the main thread for 500ms-1s. Moving this to post-Flutter-load eliminates startup contention.

**Approach**: 
- Keep the `defer` script tag for the SDK
- Wrap `OneSignal.init()` to execute only after Flutter signals readiness (e.g., after `runApp()`)
- The `OneSignalDeferred` pattern already supports this — push init into the queue but delay the actual SDK load

**Alternatives considered**:
- Remove OneSignal entirely from index.html: Would break push notifications. Not acceptable.
- Load OneSignal via Flutter plugin instead of JS SDK: Would require a Flutter package change. Higher risk, no clear benefit.

## Decision 4: Supabase Initialization Timing

**Decision**: Keep current FutureBuilder pattern but ensure splash screen renders immediately.

**Rationale**: The current code already shows a `_SplashScreen` while `_supabaseReady` future is pending. The actual issue is that `.env` loading (`await dotenv.load()`) blocks BEFORE `runApp()` — meaning the Flutter engine doesn't even start rendering until .env is loaded. Moving dotenv to be part of the FutureBuilder chain (or loading it synchronously from bundled assets) would let the splash appear instantly.

**Approach**:
- Potentially move `dotenv.load()` into the FutureBuilder chain alongside Supabase init
- Or use compile-time `--dart-define` for the few env vars needed, eliminating the .env file dependency entirely

**Alternatives considered**:
- Remove dotenv entirely: Would require refactoring env var access. Higher scope than needed.
- Pre-bundle .env in assets: Still requires async load but from local cache. Marginal improvement.

## Current File States

### nginx_flutter_app.conf
- No gzip directives
- Good cache headers for static assets (6M expiry)
- No-cache for entry-point files (correct)
- Missing: gzip, gzip_types, gzip_vary

### deploy_frontend.sh
- Lines 54-68: Overwrites `flutter_service_worker.js` with self-unregistering version
- This is where the caching SW would be generated instead
- `release_id` is already generated and available for cache versioning

### index.html
- Lines 4-5: OneSignal SDK loaded with `defer` but init runs inline
- Lines 99-100: Preload hints for bootstrap and main.dart.js
- Lines 102-105: Google Fonts preconnect + stylesheet

### main.dart
- Lines 12-17: `await dotenv.load()` blocks before `runApp()`
- Lines 56-57: `MediaQuery.textScaler` wrapper
- Lines 62-68: `FutureBuilder` for Supabase (already shows splash while waiting)
