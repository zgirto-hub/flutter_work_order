# Research: Version-File Based PWA Update Detection

**Feature**: 017-pwa-version-update | **Date**: 2026-04-05

## R1: Why replace service worker event detection?

**Decision**: Replace SW `updatefound`/`statechange` events with version.json polling as the sole detection mechanism.

**Rationale**: iOS Safari has well-documented inconsistencies with service worker lifecycle events. The `updatefound` event sometimes does not fire, or fires at unexpected times (e.g., after the page has already been reloaded). The current codebase already has a version.json fallback specifically for iOS (called after a 5-second delay). By making version.json the primary mechanism, we eliminate the complexity of maintaining two detection paths and get consistent behavior across all browsers.

**Alternatives considered**:
- Keep dual detection (SW events primary, version.json fallback): Rejected — adds complexity, the fallback already works reliably, and maintaining two code paths creates more edge cases.
- Use `navigator.serviceWorker.controller` change detection: Rejected — still depends on SW lifecycle which is unreliable on iOS.
- Use `BroadcastChannel` to signal from SW to page: Rejected — adds another browser API dependency, not supported in older iOS Safari versions.

## R2: version.json content and releaseId format

**Decision**: Use Unix timestamp (seconds since epoch) as the `releaseId` field. Keep existing `version` and `build` fields for backward compatibility.

**Rationale**: The current deploy script already generates version.json with `{"version":"x.y.z","build":"NNN","release":"TIMESTAMP"}`. The `release` field (renamed to `releaseId` for clarity) is the appropriate comparison key because it changes on every deployment, even if the version/build numbers are the same (e.g., config-only deploys). Unix timestamps are monotonically increasing, simple to compare, and human-readable.

**Alternatives considered**:
- Use git commit SHA: Rejected — not available during build without extra tooling, and not monotonically comparable.
- Use version+build string: Rejected — doesn't change for config-only deploys; string comparison is more fragile than numeric comparison.
- Use UUID: Rejected — not human-readable, no ordering guarantee.

## R3: Cache-busting strategy for version.json

**Decision**: Triple-layer cache prevention: (1) `fetch()` with `cache: 'no-store'` header, (2) timestamp query parameter `?_t=Date.now()`, (3) nginx `Cache-Control: no-store, must-revalidate` response headers.

**Rationale**: Different browsers and intermediaries respect different cache-control mechanisms. Using all three provides defense in depth. The current codebase already uses the query parameter approach for the version check fallback. Adding the fetch header and a dedicated nginx location block ensures no layer can serve stale content.

**Alternatives considered**:
- Only query parameter: Rejected — some CDNs/proxies strip query parameters.
- Only no-store header on fetch: Rejected — intermediate proxies may ignore client cache directives.
- ETag/If-None-Match: Rejected — adds unnecessary roundtrip complexity for a ~50 byte file.

## R4: Seeding strategy (initial page load)

**Decision**: Fetch version.json once on page load (in the IIFE block) and store the `releaseId` in a JavaScript variable. If the fetch fails, set the seeded value to `null` and skip update comparisons until a successful check.

**Rationale**: Seeding at page load establishes the "known current version" baseline. This is simpler than reading a `<meta>` tag (which requires deploy-time stamping and has a different value format) or embedding the releaseId in the HTML (which would require template processing). A failed seed is handled gracefully — the app still works, update detection just becomes unavailable until the next successful check re-seeds.

**Alternatives considered**:
- Read from `<meta name="app-version">`: Rejected — this contains the semver string, not the releaseId timestamp. Would need a second meta tag or a change to the stamping format.
- Embed in `flutter_bootstrap.js`: Rejected — that file is a Flutter template with specific placeholders.
- Use `localStorage` for persistence: Rejected — adds state management complexity. In-memory is sufficient since a page reload naturally re-seeds.

## R5: Dart interop API design

**Decision**: The Dart `UpdateService` exposes three methods: `checkForUpdate()` returning a `Future<UpdateStatus>` enum (available/upToDate/error), `registerUpdateCallback(void Function() callback)` for background listeners, and `applyUpdate()` to trigger the reload overlay. The stub file mirrors these signatures with no-op implementations.

**Rationale**: The existing codebase uses top-level functions with conditional imports (`pwa_update_stub.dart` / `pwa_update_web.dart`). Maintaining this pattern (top-level functions with conditional import) is simpler than introducing a class, and aligns with the existing codebase style. The key change is replacing the current five functions (applyPWAUpdate, checkSwUpdate, triggerSwUpdateCheck, registerSwUpdateCallback, checkVersionUpdate) with three cleaner ones that map to the version-file approach.

**Alternatives considered**:
- Singleton class `UpdateService`: Rejected (YAGNI) — top-level functions with conditional import already work well in this codebase.
- Keep all five existing functions: Rejected — `checkSwUpdate()` and `triggerSwUpdateCheck()` are SW-specific and no longer needed.

## R6: Service worker cache-bypass rule

**Decision**: In the deploy script's generated service worker, add an explicit check in the fetch handler: if the request URL contains `version.json`, always fetch from network (bypass cache entirely, do not store response).

**Rationale**: The current SW already has a network-first path for API requests and version.json (lines 104-107 of deploy_frontend.sh). This just formalizes and makes the version.json bypass explicit and unconditional (not just network-first, but network-only with no cache fallback).

**Alternatives considered**:
- Remove version.json from SW scope entirely (via `navigationPreloadEnabled`): Rejected — not widely supported.
- Use SW `ignoreSearch` in cache match: Rejected — doesn't solve the fundamental caching issue.

## R7: Nginx exact-match location block

**Decision**: Add `location = /version.json` with `Cache-Control: no-store, must-revalidate` headers, placed before the generic regex-based no-cache block to ensure it takes priority.

**Rationale**: The current nginx config already includes version.json in a regex match block that sets no-cache headers. An exact-match `location =` block is more efficient (nginx processes exact matches first) and makes the intent explicit. The spec requires this as a dedicated rule.

**Alternatives considered**:
- Keep existing regex block only: Works but doesn't satisfy the spec requirement for a dedicated block, and regex matching is slightly less efficient.
- Use `map` directive: Rejected — overkill for a single file.
