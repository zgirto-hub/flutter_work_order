# Feature Specification: Version-File Based PWA Update Detection

**Feature Branch**: `017-pwa-version-update`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "Version-file based PWA update detection replacing service worker event listeners. The solution consists of four changes: (1) deploy script writes version.json with releaseId, cache bypass in SW; (2) index.html seeds releaseId, exposes checkForAppUpdate/registerUpdateCallback/applyPWAUpdate; (3) nginx no-store location block for version.json; (4) Dart UpdateService wraps JS functions via web interop."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Update Notification (Priority: P1)

A user has the PWA open in their browser. A new version is deployed to the server. The application periodically checks for updates in the background. When a new version is detected (the remote releaseId differs from the seeded releaseId), the user is notified that an update is available so they can apply it at their convenience.

**Why this priority**: This is the core value of the feature — reliably detecting that a newer version exists without depending on inconsistent service worker lifecycle events, especially on iOS Safari.

**Independent Test**: Deploy a new version to the server (generating a new releaseId), then verify the running app detects the change and fires the update callback within the configured check interval.

**Acceptance Scenarios**:

1. **Given** the app is open and a new version has been deployed, **When** the background check runs, **Then** the registered update callback fires indicating an update is available.
2. **Given** the app is open and no new version has been deployed, **When** the background check runs, **Then** no update callback fires and the app continues normally.
3. **Given** the app is open and the version.json fetch fails (network error), **When** the background check runs, **Then** the check returns an error status and does not falsely report an update or crash the app.

---

### User Story 2 - On-Demand Update Check (Priority: P1)

A user or the app triggers an explicit update check (e.g., from a settings page or on app resume). The system fetches version.json with cache-busting headers, compares the releaseId to the seeded value, and returns whether an update is available, up-to-date, or an error occurred.

**Why this priority**: Equally critical to background detection — users and the Dart layer need a synchronous-style return value to drive UI decisions such as showing an update banner.

**Independent Test**: Call checkForUpdate from the Dart layer and verify it returns `available` when a new version exists, `upToDate` when versions match, and `error` when the fetch fails.

**Acceptance Scenarios**:

1. **Given** the server has a newer releaseId than the seeded value, **When** checkForUpdate is called, **Then** it returns `available`.
2. **Given** the server releaseId matches the seeded value, **When** checkForUpdate is called, **Then** it returns `upToDate`.
3. **Given** version.json is unreachable or returns malformed content, **When** checkForUpdate is called, **Then** it returns `error`.

---

### User Story 3 - Apply Update with Visual Feedback (Priority: P2)

When the user chooses to apply an available update, the app shows an animated overlay indicating the update is in progress, then reloads the page. The reload is guarded by a single-fire flag to prevent double-reload if triggered multiple times.

**Why this priority**: Provides a polished user experience during the reload transition and prevents confusing double-reload behavior.

**Independent Test**: Trigger applyUpdate twice in rapid succession and verify the overlay appears once and the page reloads exactly once.

**Acceptance Scenarios**:

1. **Given** an update is available, **When** the user triggers applyUpdate, **Then** an animated overlay is displayed and the page reloads after a brief delay.
2. **Given** applyUpdate has already been triggered, **When** applyUpdate is called again, **Then** the second call is ignored (no double reload).

---

### User Story 4 - Fresh Version Seeding on Page Load (Priority: P2)

When the app first loads, it fetches version.json once to seed the current releaseId into memory. All subsequent update checks compare against this seeded value. This ensures a reliable baseline without depending on build-time constants.

**Why this priority**: Foundation for all update detection — without correct seeding, comparisons would fail or produce false positives.

**Independent Test**: Load the app and verify the seeded releaseId matches the value in the deployed version.json file.

**Acceptance Scenarios**:

1. **Given** the app is loading for the first time, **When** the page finishes loading, **Then** version.json is fetched and the releaseId is stored in memory.
2. **Given** version.json is unreachable on initial load, **When** the page finishes loading, **Then** the app still loads normally but update detection is gracefully disabled until the next successful check.

---

### User Story 5 - Deploy Script Generates Version File (Priority: P1)

During deployment, the deploy script writes a version.json file containing a unique releaseId (Unix timestamp) into the web build folder before uploading to the server. The service worker is configured to always bypass the cache for version.json fetch requests.

**Why this priority**: Without the version file being generated during deployment and the service worker bypassing cache for it, the entire update detection mechanism has no signal to work with.

**Independent Test**: Run the deploy script and verify version.json exists in the build output with a valid Unix timestamp releaseId, and that the service worker fetch handler does not cache version.json responses.

**Acceptance Scenarios**:

1. **Given** a deployment is executed, **When** the build completes, **Then** version.json is present in the build folder with a `releaseId` field containing a Unix timestamp.
2. **Given** the service worker intercepts a fetch for version.json, **When** the request is processed, **Then** it bypasses the cache and fetches from the network.

---

### Edge Cases

- What happens when the user is offline and an update check runs? The check should return an error status without disrupting the app.
- What happens if the seeded releaseId is null (initial fetch failed)? Update checks should treat this as an inconclusive state and not report a false update.
- What happens if version.json returns malformed content (missing releaseId, invalid JSON)? The check should return an error status rather than crashing.
- What happens if the server returns a cached (stale) version.json despite cache-busting? The nginx no-store headers and query-string cache buster provide defense in depth; a stale response would simply result in no update detected (safe failure mode).
- What happens if the user navigates away during the reload overlay? The overlay is purely visual and the reload proceeds regardless — no state corruption occurs.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The deploy process MUST generate a version.json file in the web build folder containing a `releaseId` field with a unique Unix timestamp value before uploading to the server.
- **FR-002**: The service worker MUST bypass its cache for all fetch requests to version.json, always forwarding them to the network.
- **FR-003**: The web page MUST fetch version.json on initial load and store the releaseId in memory as the baseline for comparison.
- **FR-004**: The web page MUST expose a checkForAppUpdate function that fetches version.json with no-store cache headers and a timestamp cache-buster query parameter, compares the fetched releaseId against the seeded value, and returns the comparison result.
- **FR-005**: The web page MUST expose a registerUpdateCallback function that accepts a callback to be invoked when checkForAppUpdate detects a version mismatch.
- **FR-006**: The web page MUST expose an applyPWAUpdate function that displays an animated overlay and reloads the page, guarded by a single-fire flag to prevent double reload.
- **FR-007**: The server MUST serve version.json with no-store and must-revalidate cache headers via a dedicated configuration rule that takes priority over generic static asset caching.
- **FR-008**: The application MUST provide an UpdateService that wraps the three JS functions (checkForUpdate, registerUpdateCallback, applyUpdate) via web interop, with a stub implementation for non-web platforms.
- **FR-009**: The checkForUpdate method MUST return one of three states: available, upToDate, or error.
- **FR-010**: The existing service-worker-event-based update detection logic MUST be replaced by the version-file-based approach.

### Key Entities

- **Version File (version.json)**: Contains a `releaseId` (Unix timestamp) that uniquely identifies each deployment. Served from the web root with no-cache headers.
- **Seeded ReleaseId**: The in-memory baseline releaseId fetched on page load, used as the reference point for all subsequent update comparisons.
- **Update State**: The result of an update check — one of available (version mismatch detected), upToDate (versions match), or error (fetch failed or malformed response).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Update detection works reliably across all major browsers including iOS Safari, where service worker events are unreliable.
- **SC-002**: Users are notified of a new deployment within the configured background check interval after a new version is published.
- **SC-003**: The update check completes within 2 seconds under normal network conditions.
- **SC-004**: The version.json file is never served from browser or intermediary cache — every fetch returns the current server-side content.
- **SC-005**: Applying an update results in exactly one page reload regardless of how many times the apply action is triggered.
- **SC-006**: The app continues to function normally when version.json is unreachable — no crashes, no false update notifications.

## Assumptions

- The existing polling/timer mechanism that periodically triggers update checks will be reused; this feature replaces only the detection mechanism, not the scheduling.
- The deploy script already generates version.json with a releaseId field (confirmed in current codebase) — this feature refines and formalizes that behavior and removes the service-worker-event approach.
- The nginx configuration is managed as part of this project and can be updated with a new location block.
- The service worker is generated/replaced by the deploy script at build time, so cache-bypass rules can be embedded during the build step.
- The existing applyPWAUpdate overlay UI and behavior are retained; the implementation is refactored but the user-facing experience remains the same.
- Non-web platforms (mobile/desktop) will continue to use stub implementations that return no-op results.
