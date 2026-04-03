# Tasks: Optimize iPhone PWA Launch Performance

**Input**: Design documents from `/specs/009-optimize-pwa-launch/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by 3 independent user stories. Each story can be deployed separately.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

---

## Context for the Implementor

**IMPORTANT — Read this before making any changes.**

The app is a Flutter Web PWA deployed behind Nginx on a single Linux server. It currently takes ~30 seconds to launch on iPhone because:

1. **No server compression**: 18+ MB of assets sent uncompressed (would be ~6.5 MB with gzip)
2. **Broken service worker**: The service worker unregisters itself and caches nothing — every launch re-downloads everything
3. **Blocking initialization**: OneSignal SDK and Supabase auth block rendering

**Key files**:
- `nginx_flutter_app.conf` — Nginx server config (deployed to server, not a build artifact)
- `scripts/deploy_frontend.sh` — Build + deploy script that generates `flutter_service_worker.js`
- `frontend/web/index.html` — HTML entry point with OneSignal SDK and Flutter bootstrap
- `frontend/lib/main.dart` — Dart entry point with dotenv and Supabase init

**Constraints**:
- Do NOT remove or modify font files (Calibri must stay)
- Do NOT change the Flutter renderer (canvaskit stays)
- All changes must work on iOS Safari, Android Chrome, and desktop browsers

---

## Phase 1: Setup

**Purpose**: No setup needed — all changes are to existing files.

---

## Phase 2: Foundational

**Purpose**: No foundational work needed — all 3 user stories are independent.

---

## Phase 3: User Story 1 - Enable Server Compression (Priority: P1) 🎯 MVP

**Goal**: Add gzip compression to Nginx so all assets are served compressed, reducing transfer size by ~65%.

**Independent Test**: After deploying the updated Nginx config, use browser DevTools (Network tab) to verify that `main.dart.js` response headers include `Content-Encoding: gzip` and the transfer size is ~1.7 MB instead of 7.4 MB.

### Implementation for User Story 1

- [X] T001 [US1] Add gzip compression directives to `nginx_flutter_app.conf`. Insert the following block at the top of the `server { }` block (after `client_max_body_size 50M;` on line 5, before the first `location` block):

```nginx
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/wasm
        application/octet-stream
        font/ttf
        font/woff
        font/woff2
        image/svg+xml;
```

This enables gzip for all major asset types. `gzip_comp_level 6` is the recommended balance of compression ratio vs CPU. `gzip_min_length 1024` skips tiny files where compression overhead exceeds savings.

- [ ] T002 [US1] Deploy the updated Nginx config to the server. SSH into the server and:
  1. Copy the updated `nginx_flutter_app.conf` to the Nginx config directory (typically `/etc/nginx/sites-available/` or `/etc/nginx/conf.d/`)
  2. Test the config: `sudo nginx -t`
  3. Reload Nginx: `sudo systemctl reload nginx`

- [ ] T003 [US1] Verify compression is working. Open the app in Chrome on a desktop or iPhone, open DevTools > Network tab. Check these assets:
  - `main.dart.js`: Should show `Content-Encoding: gzip`, transfer size ~1.7 MB (was 7.4 MB)
  - `canvaskit.wasm`: Should show gzip encoding, transfer size ~2.75 MB (was 6.9 MB)
  - Any `.json` file: Should show gzip encoding
  - Any `.ttf` font: Should show gzip encoding

**Checkpoint**: Server compression is live. Total download payload reduced from ~18 MB to ~6.5 MB. Cold start should already be noticeably faster.

---

## Phase 4: User Story 2 - Fix Service Worker Caching (Priority: P2)

**Goal**: Replace the self-unregistering service worker with a cache-first service worker that precaches critical assets. Repeat launches load from cache instantly.

**Independent Test**: Open the PWA on iPhone. Wait for full load. Close the app completely. Reopen it. It should load from cache in under 5 seconds without any network requests for cached assets.

### Implementation for User Story 2

- [X] T004 [US2] In `scripts/deploy_frontend.sh`, replace the service worker generation block (lines 53-68) that currently writes a self-unregistering worker. Replace the content between `cat > build/web/flutter_service_worker.js <<'SWEOF'` and `SWEOF` with a cache-first service worker. The new worker should:

  1. Define a cache name using the `RELEASE_ID` variable (already available in the script): `const CACHE_NAME = 'flutter-cache-${RELEASE_ID}';`
  2. On `install`: Open the cache and add critical assets: `['/', '/index.html', '/main.dart.js', '/flutter_bootstrap.js', '/manifest.json']`. Call `self.skipWaiting()`.
  3. On `activate`: Delete all old caches whose name doesn't match the current `CACHE_NAME`. Call `self.clients.claim()`.
  4. On `fetch`: Use cache-first strategy — try the cache first, fall back to network. If the network succeeds, clone the response and put it in the cache for next time. Only cache same-origin GET requests (skip cross-origin and non-GET).

  **IMPORTANT**: The `RELEASE_ID` is a shell variable that must be interpolated into the JS. Since the heredoc currently uses `<<'SWEOF'` (single-quoted = no interpolation), you need to change it to `<<SWEOF` (unquoted = allows `$RELEASE_ID` interpolation). Escape any `$` signs in the JS that are NOT shell variables (like `$request` in event handlers) with `\$`.

  Here is the complete replacement service worker to write:

```bash
cat > build/web/flutter_service_worker.js <<SWEOF
'use strict';

const CACHE_NAME = 'flutter-cache-$RELEASE_ID';
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/flutter_bootstrap.js',
  '/manifest.json'
];

self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(PRECACHE_URLS);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(cacheNames) {
      return Promise.all(
        cacheNames
          .filter(function(name) { return name !== CACHE_NAME; })
          .map(function(name) { return caches.delete(name); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(event) {
  if (event.request.method !== 'GET') return;
  if (!event.request.url.startsWith(self.location.origin)) return;

  event.respondWith(
    caches.match(event.request).then(function(cached) {
      if (cached) return cached;
      return fetch(event.request).then(function(response) {
        if (response.ok) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) {
            cache.put(event.request, clone);
          });
        }
        return response;
      });
    })
  );
});
SWEOF
```

- [ ] T005 [US2] Verify that the deploy script still works correctly by doing a dry run:
  1. Run the build portion of `deploy_frontend.sh` locally (just `flutter build web` + the service worker generation)
  2. Check that `build/web/flutter_service_worker.js` contains the new caching code
  3. Verify the `RELEASE_ID` is correctly interpolated into the `CACHE_NAME` constant (should look like `flutter-cache-20260403143022` or similar)
  4. Verify no `$` signs were incorrectly interpolated (the JS should not have any unresolved shell variables)

- [ ] T006 [US2] Deploy the app using the updated `deploy_frontend.sh`. After deployment:
  1. Open the PWA on iPhone
  2. Wait for full load
  3. Check DevTools > Application > Service Workers — verify the new SW is registered and active
  4. Check DevTools > Application > Cache Storage — verify `flutter-cache-XXXX` exists with cached assets
  5. Close and reopen the app — verify it loads from cache (Network tab should show "(ServiceWorker)" for cached assets)

**Checkpoint**: Service worker is caching assets. Repeat launches are near-instant. Updates only re-download changed assets.

---

## Phase 5: User Story 3 - Optimize App Initialization Sequence (Priority: P3)

**Goal**: Defer OneSignal SDK initialization and optimize the startup sequence so the splash screen appears within 3 seconds, even on slow networks.

**Independent Test**: Throttle the network to 3G in DevTools. Launch the app. The splash screen (ticket card animation) should appear within 3 seconds. OneSignal and Supabase should initialize in the background.

### Implementation for User Story 3

- [X] T007 [US3] In `frontend/web/index.html`, defer the OneSignal SDK loading so it does not compete with Flutter during startup. Move the OneSignal `<script>` tag (line 5) from the `<head>` to just before `</body>`. This ensures Flutter's bootstrap scripts load and execute first, and OneSignal loads after the DOM is ready.

  Current (line 5 in `<head>`):
  ```html
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
  ```

  Move to just before `</body>`:
  ```html
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
  ```

  Also move the entire inline `<script>` block (lines 6-79) containing `window.OneSignalDeferred`, `oneSignalRequestPermission`, `oneSignalSubscribe`, `oneSignalUnsubscribe`, `setAppBadge`, and the notification event listener — move all of it to just before `</body>` as well, AFTER the OneSignal SDK script tag.

  **IMPORTANT**: The `webauthn.js` script (line 4) can stay in `<head>` — it's tiny (3.8 KB) and uses `defer`.

- [X] T008 [US3] In `frontend/lib/main.dart`, optimize the startup sequence. Currently line 15 has `await dotenv.load(fileName: '.env');` which blocks before `runApp()`. The `.env` file is loaded from assets (bundled in the build), so it's a local I/O read, but it still delays the first frame.

  Option A (recommended): Move `dotenv.load()` into the `_initSupabase()` method so it runs alongside the FutureBuilder splash screen instead of blocking before it:

  Change `main()` from:
  ```dart
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    await dotenv.load(fileName: '.env');
    runApp(MyApp());
  }
  ```

  To:
  ```dart
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    runApp(MyApp());
  }
  ```

  And change `_initSupabase()` from:
  ```dart
  Future<void> _initSupabase() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }
  ```

  To:
  ```dart
  Future<void> _initSupabase() async {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }
  ```

  This way `runApp()` executes immediately, the splash screen renders, and dotenv + Supabase init happen in parallel with the splash animation.

- [ ] T009 [US3] Verify the optimized startup:
  1. Run the app locally (`flutter run -d chrome`)
  2. Verify the splash screen (ticket card animation) appears immediately
  3. Verify login/auth still works after Supabase finishes initializing
  4. Verify push notifications still work (OneSignal)
  5. Throttle to 3G in DevTools and verify splash appears within 3 seconds

**Checkpoint**: Splash screen renders immediately. OneSignal loads after Flutter. Supabase init happens behind the splash.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T010 Deploy the full set of changes and run end-to-end verification on iPhone PWA:
  1. Cold start on 4G: measure time — target under 10 seconds
  2. Repeat launch (cached): measure time — target under 5 seconds
  3. Splash visibility: confirm appears within 3 seconds on 3G
  4. App update: deploy a new version, verify only changed files download
  5. All features work: login, work orders, files, calendar, settings, push notifications

- [ ] T011 Verify no regressions on other platforms:
  1. Android Chrome: app loads and works correctly
  2. Desktop Chrome: app loads and works correctly
  3. Desktop Firefox: app loads and works correctly

- [ ] T012 Run `quickstart.md` verification checklist: confirm all 10 items pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **US1 (Phase 3)**: No dependencies — can start immediately. **Deploy this first** for immediate impact.
- **US2 (Phase 4)**: No dependencies on US1 — can run in parallel. However, deploying US1 first means cached assets will already be compressed.
- **US3 (Phase 5)**: No dependencies on US1 or US2 — can run in parallel.
- **Polish (Phase 6)**: Depends on all 3 stories being deployed.

### Parallel Opportunities

All 3 user stories modify different files and can be implemented in parallel:

```
# These can all run simultaneously:
US1: nginx_flutter_app.conf (server config only)
US2: scripts/deploy_frontend.sh (deploy script only)
US3: frontend/web/index.html + frontend/lib/main.dart (app code only)
```

### Recommended Deployment Order

Deploy US1 first (Nginx gzip) because:
- It has the highest single impact (~65% transfer reduction)
- It requires no code changes — just a config update + Nginx reload
- It benefits US2 immediately (cached assets will be smaller)

Then deploy US2 + US3 together in the next deploy cycle.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001-T003 (Nginx gzip config)
2. **STOP and VALIDATE**: Check compression headers, measure cold start improvement
3. Expected: cold start drops from ~30s to ~12-15s (download time halved+)

### Full Delivery

1. Deploy US1 → Gzip compression live (~65% transfer reduction)
2. Deploy US2 + US3 → Service worker caching + deferred init
3. End-to-end validation T010-T012
4. Expected: cold start < 10s, repeat launch < 5s, splash < 3s

### Summary

**Total files to modify**: 4 (`nginx_flutter_app.conf`, `deploy_frontend.sh`, `index.html`, `main.dart`)
**Total implementation tasks**: 9 (T001-T009)
**Total verification tasks**: 3 (T010-T012)
**Total tasks**: 12
**Parallel opportunities**: All 3 stories can run in parallel (different files)

---

## Notes

- Do NOT modify font files — Calibri stays as-is per user decision
- Do NOT change the Flutter renderer (canvaskit) or build configuration
- The `release_id` in `deploy_frontend.sh` is already generated — reuse it for SW cache versioning
- The `_SplashScreen` widget in `main.dart` already exists and shows while Supabase initializes — we just need to make it render sooner by removing the `dotenv.load()` blocking call
- OneSignal uses the `OneSignalDeferred` pattern which queues calls until the SDK loads — moving the script tag won't break functionality
- iOS Safari limits service worker cache to ~50 MB per origin — our ~18 MB of assets fits comfortably
