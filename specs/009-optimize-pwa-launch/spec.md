# Feature Specification: Optimize iPhone PWA Launch Performance

**Feature Branch**: `009-optimize-pwa-launch`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "why Launching the App on iPhone PWA takes a lot of time ~30 sec, also updating the App. How to make faster"

## Clarifications

### Session 2026-04-03

- Q: Should Calibri font files (3.2 MB) be removed to reduce payload? → A: Keep Calibri — do not optimize fonts. Skip font payload reduction entirely.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Server Compression for App Assets (Priority: P1)

A user launches the app on iPhone (as a PWA from the home screen). The server delivers all app assets (scripts, styles, fonts, images) in compressed form, dramatically reducing download time. Currently the main application bundle is sent uncompressed at 7.4 MB; with compression it would be ~1.7 MB — a 4x reduction.

**Why this priority**: Server compression is the single highest-impact, lowest-risk optimization. It reduces transfer size by 75%+ with zero code changes to the app itself. Without compression, every other optimization has diminished impact because the bottleneck is raw download time.

**Independent Test**: Open the PWA on iPhone over a 4G connection. Measure time from tap to interactive screen. Compare before/after compression is enabled.

**Acceptance Scenarios**:

1. **Given** a user opens the PWA on iPhone, **When** the app assets are downloaded, **Then** the main application bundle transfers at ~1.7 MB instead of 7.4 MB.
2. **Given** the server is configured with compression, **When** a browser requests any text-based or binary asset, **Then** the response includes appropriate compression encoding.
3. **Given** compression is enabled, **When** the app loads, **Then** there is no functional difference — all features work identically.

---

### User Story 2 - Fix Service Worker Caching for Faster Repeat Launches (Priority: P2)

The current service worker immediately unregisters itself and caches nothing. Repeat visits and app updates require re-downloading all assets from scratch. A proper caching strategy would make second and subsequent launches near-instant and make updates download only changed files.

**Why this priority**: Without caching, every launch is a cold start. Fixing this makes repeat launches dramatically faster and reduces bandwidth. This also fixes the slow update experience — only changed files need downloading.

**Independent Test**: Launch the PWA on iPhone, wait for it to fully load. Close and reopen it. Measure the repeat launch time — it should be under 5 seconds.

**Acceptance Scenarios**:

1. **Given** the service worker caches app assets on first load, **When** the user reopens the app, **Then** the app loads from cache and appears interactive within 5 seconds.
2. **Given** a new version is deployed, **When** the user next opens the app, **Then** only changed assets are downloaded (not the full 10+ MB payload).
3. **Given** the device is offline or on a flaky connection, **When** the user opens the previously loaded app, **Then** the app shell and cached screens load from local storage.

---

### User Story 3 - Optimize App Initialization Sequence (Priority: P3)

The app currently blocks rendering until network-dependent initialization completes (authentication service, environment config). By showing meaningful content earlier and deferring non-critical initialization, users see the app faster even when network conditions are poor.

**Why this priority**: Even with a smaller download, the app blocks on sequential network calls before showing any content. Parallelizing and deferring these gives a perceived performance boost.

**Independent Test**: Launch the app on a throttled 3G connection. The splash screen or login prompt should appear within 3 seconds of Flutter engine load, regardless of authentication service response time.

**Acceptance Scenarios**:

1. **Given** the app is launched, **When** the authentication service is slow to respond, **Then** the user sees a splash screen or loading indicator within 3 seconds — not a blank white screen.
2. **Given** non-critical services (push notifications, analytics) are deferred, **When** the app loads, **Then** these services initialize in the background without blocking the first screen.
3. **Given** the environment config loads quickly, **When** the authentication service eventually responds, **Then** the app transitions smoothly to the appropriate screen (login or dashboard).

---

### Edge Cases

- What happens when the service worker cache becomes corrupted or stale? The app must have a fallback to network fetch and a mechanism to clear the cache.
- How does the app behave when an update is available but the user is on a very slow connection? The update should not block the current cached version from loading.
- What happens on devices with very limited storage (e.g., low-storage iPhone)? The service worker cache should have a size limit and eviction policy.
- How does the optimization affect non-iPhone platforms (Android, desktop browsers)? All optimizations must be cross-platform compatible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The web server MUST serve all text-based and binary assets with compression, reducing transfer sizes by at least 60%.
- **FR-002**: The service worker MUST cache critical app assets (scripts, fonts, images) on first load for instant repeat launches.
- **FR-003**: The service worker MUST support incremental updates — only changed files are re-downloaded when a new version is deployed.
- **FR-004**: The app MUST show a splash screen or loading indicator within 3 seconds of the rendering engine starting, regardless of network conditions.
- **FR-005**: Non-critical third-party services (push notifications) MUST be initialized after the first screen is visible, not during startup.
- **FR-006**: All optimizations MUST be backward-compatible — no functional regressions in any app feature.
- **FR-007**: The app MUST properly handle cache invalidation when a new version is deployed, ensuring users get the latest version.
- **FR-008**: Font files (including Calibri) MUST NOT be removed or modified — they are intentionally kept as-is.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Cold start time on iPhone PWA (4G connection) drops from ~30 seconds to under 10 seconds.
- **SC-002**: Repeat launch time (app already cached) drops to under 5 seconds on iPhone.
- **SC-003**: App update (new version deployed) completes in under 15 seconds, downloading only changed files.
- **SC-004**: Total initial download payload is reduced by at least 40% via compression (fonts excluded from optimization).
- **SC-005**: Zero functional regressions — all existing features work identically after optimization.
- **SC-006**: The splash screen or loading indicator appears within 3 seconds of engine start on a 3G-throttled connection.

## Assumptions

- The primary target device is iPhone running iOS Safari as a home-screen PWA; Android and desktop are secondary but must not regress.
- The app is deployed behind an Nginx reverse proxy on a single Linux server; server-side changes are limited to Nginx configuration and deploy scripts.
- The current ~30 second load time includes both download time (large uncompressed payload) and initialization time (sequential blocking network calls).
- Font files (Calibri and Google Fonts) are kept as-is — no font removal or replacement is in scope.
- Service worker caching will use a "cache-first, network-fallback" strategy with version-based cache invalidation.
- The Flutter build process and renderer choice (canvaskit) will not change — optimizations focus on delivery and initialization, not the rendering engine.
