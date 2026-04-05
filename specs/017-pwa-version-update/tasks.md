# Tasks: Version-File Based PWA Update Detection

**Input**: Design documents from `/specs/017-pwa-version-update/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Target audience**: Another LLM model implementing these tasks, with a human reviewer afterward.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Context for Implementer

This feature replaces the current dual-mechanism PWA update detection (service worker event listeners + version.json fallback) with a single version-file-based approach. The current codebase already has most of the pieces — this is primarily a **refactoring** of existing code, not greenfield development.

**Key design decisions** (from research.md):
- Use `releaseId` (Unix timestamp) as comparison key in version.json
- Triple-layer cache prevention: fetch `cache: 'no-store'` + `?_t=` query param + nginx headers
- Seed releaseId on page load into JS variable; null seed = skip checks
- Three top-level Dart functions replace five existing ones (matches codebase pattern)
- Service worker already bypasses cache for version.json — just formalize it

**Current API (being replaced)**:
- `applyPWAUpdate()` → keep (rename to `applyUpdate` in Dart only)
- `checkSwUpdate()` → remove (was synchronous SW flag check)
- `triggerSwUpdateCheck()` → remove (was SW re-fetch trigger)
- `registerSwUpdateCallback(callback)` → keep (same concept, new implementation)
- `checkVersionUpdate()` → replace with `checkForUpdate()` returning enum

**New API**:
- `checkForUpdate()` → async, returns `UpdateStatus` enum (available/upToDate/error)
- `registerUpdateCallback(callback)` → registers callback fired on version mismatch
- `applyUpdate()` → triggers overlay + reload (same as current applyPWAUpdate)

---

## Phase 1: Setup

**Purpose**: No project setup needed — all files already exist. This phase is empty.

**Checkpoint**: Proceed to Phase 2.

---

## Phase 2: Foundational (Deploy Script + Nginx Config)

**Purpose**: Ensure the server-side infrastructure delivers version.json correctly. These changes MUST be complete before the client-side code can be tested.

**CRITICAL**: No client-side user story work should begin until this phase is complete.

- [ ] T001 [P] [US5] Update version.json generation to use `releaseId` field in `scripts/deploy_frontend.sh`

  **What to change**: In `scripts/deploy_frontend.sh`, find the version.json generation block (around line 148):
  ```bash
  cat > build/web/version.json <<VJEOF
  {"version":"$NEW_VERSION","build":"$BUILD_NUMBER","release":"$RELEASE_ID"}
  VJEOF
  ```
  Change the `"release"` key to `"releaseId"`:
  ```bash
  cat > build/web/version.json <<VJEOF
  {"version":"$NEW_VERSION","build":"$BUILD_NUMBER","releaseId":"$RELEASE_ID"}
  VJEOF
  ```
  That is the ONLY change in this file. The service worker section (lines 52-145) already has the correct version.json cache bypass at lines 103-107 — do NOT modify the service worker section.

- [ ] T002 [P] Add exact-match nginx location block for version.json in `nginx_flutter_app.conf`

  **What to change**: In `nginx_flutter_app.conf`, add a new `location = /version.json` block BEFORE the existing regex-based no-cache block (line 57). Insert it between line 55 (end of API block `}`) and line 57 (comment `# Never cache Flutter's entry-point files`):

  ```nginx
    # version.json — dedicated no-cache rule for PWA update detection
    location = /version.json {
        add_header Cache-Control "no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
        expires 0;
        try_files $uri =404;
    }
  ```

  The existing regex block at line 58 still mentions `version.json` in its pattern — this is fine. Nginx processes exact-match `location =` blocks first, so the new block takes priority. Do NOT remove version.json from the regex pattern (it serves as a fallback for any edge case).

- [ ] T003 [P] Add exact-match nginx location block for version.json in `server/nginx/flutter_app.conf`

  **What to change**: Identical change as T002, applied to `server/nginx/flutter_app.conf`. This is the server-side copy of the nginx config. Insert the same `location = /version.json` block before the regex-based no-cache block.

**Checkpoint**: Server infrastructure is ready. version.json will be generated with `releaseId` field and served with no-cache headers.

---

## Phase 3: US5 + US4 — Version File Generation & Page Load Seeding (Priority: P1/P2)

**Goal**: The deploy script generates version.json with `releaseId`, and the web page seeds it on load.

**Independent Test**: After deploying, open the browser console and verify `window._pwaSeededReleaseId` contains the same value as the `releaseId` in `/version.json`.

### Implementation

- [ ] T004 [US4] Replace the SW event detection IIFE with version-file seeding logic in `frontend/web/index.html`

  **What to change**: In `frontend/web/index.html`, find the entire IIFE block (lines 511-588 — from `<script>` through `})();` then `</script>`):

  ```html
  <script>
    (function() {
      // Event-driven update detection — guarded against loops
      window._swUpdateReady = false;
      ...
      ...
          .catch(function() { return false; });
      };

    })();
  </script>
  ```

  Replace this ENTIRE `<script>` block (lines 511-589) with the following new version-file-based detection logic:

  ```html
  <script>
    (function() {
      // Version-file based update detection (replaces SW event listeners)
      window._pwaSeededReleaseId = null;   // seeded on page load
      window._pwaUpdateCallback = null;    // single callback, not array
      window._pwaUpdateApplied = false;    // guard against re-triggering applyUpdate

      // Seed the current releaseId on page load
      fetch('/version.json?_t=' + Date.now(), { cache: 'no-store' })
        .then(function(res) { return res.json(); })
        .then(function(data) {
          if (data && data.releaseId) {
            window._pwaSeededReleaseId = data.releaseId;
          }
        })
        .catch(function() {
          // Seeding failed — update detection disabled until a successful check
          window._pwaSeededReleaseId = null;
        });

      // Check for app update: fetch version.json, compare releaseId
      // Returns a Promise resolving to 'available', 'upToDate', or 'error'
      window.checkForAppUpdate = function() {
        return fetch('/version.json?_t=' + Date.now(), { cache: 'no-store' })
          .then(function(res) { return res.json(); })
          .then(function(data) {
            if (!data || !data.releaseId) return 'error';
            // If seed was null (failed initial load), seed it now
            if (window._pwaSeededReleaseId === null) {
              window._pwaSeededReleaseId = data.releaseId;
              return 'upToDate';
            }
            if (String(data.releaseId) !== String(window._pwaSeededReleaseId)) {
              // Fire registered callback if present
              if (window._pwaUpdateCallback && !window._pwaUpdateApplied) {
                window._pwaUpdateCallback();
              }
              return 'available';
            }
            return 'upToDate';
          })
          .catch(function() { return 'error'; });
      };

      // Register a callback to be invoked when an update is detected
      window.registerUpdateCallback = function(callback) {
        window._pwaUpdateCallback = callback;
      };
    })();
  </script>
  ```

  **IMPORTANT**: 
  - The `applyPWAUpdate` function in the NEXT `<script>` block (lines 593-668) must be LEFT UNCHANGED. Do NOT modify it.
  - The `<script src="flutter_bootstrap.js" async></script>` line between the two script blocks (line 591) must remain.
  - Only replace the IIFE block (the first of the two `<script>` blocks near the bottom).

**Checkpoint**: Page load seeds releaseId. checkForAppUpdate and registerUpdateCallback are exposed globally. applyPWAUpdate still works unchanged.

---

## Phase 4: US1 + US2 — Background & On-Demand Update Check (Priority: P1)

**Goal**: Dart layer can check for updates (returns available/upToDate/error) and register background callbacks.

**Independent Test**: Open the app, call checkForUpdate from Dart — should return `upToDate`. Deploy a new version, call again — should return `available`.

### Implementation

- [ ] T005 [P] [US1] Rewrite Dart web interop layer in `frontend/lib/services/pwa_update_web.dart`

  **What to change**: Replace the ENTIRE contents of `frontend/lib/services/pwa_update_web.dart` with:

  ```dart
  import 'dart:js_interop';

  @JS('applyPWAUpdate')
  external void _jsApplyPWAUpdate();

  @JS('checkForAppUpdate')
  external JSPromise<JSString> _jsCheckForAppUpdate();

  @JS('registerUpdateCallback')
  external void _jsRegisterUpdateCallback(JSFunction callback);

  /// Possible results of a version update check.
  enum UpdateStatus { available, upToDate, error }

  /// Triggers the reload overlay and reloads the page.
  void applyUpdate() => _jsApplyPWAUpdate();

  /// Checks version.json for a new release.
  /// Returns [UpdateStatus.available], [UpdateStatus.upToDate], or [UpdateStatus.error].
  Future<UpdateStatus> checkForUpdate() async {
    try {
      final result = await _jsCheckForAppUpdate().toDart;
      final value = result.toDart;
      switch (value) {
        case 'available':
          return UpdateStatus.available;
        case 'upToDate':
          return UpdateStatus.upToDate;
        default:
          return UpdateStatus.error;
      }
    } catch (_) {
      return UpdateStatus.error;
    }
  }

  /// Registers a callback invoked when [checkForAppUpdate] detects a version mismatch.
  void registerUpdateCallback(void Function() callback) {
    try {
      _jsRegisterUpdateCallback(callback.toJS);
    } catch (_) {}
  }
  ```

- [ ] T006 [P] [US1] Rewrite Dart stub layer in `frontend/lib/services/pwa_update_stub.dart`

  **What to change**: Replace the ENTIRE contents of `frontend/lib/services/pwa_update_stub.dart` with:

  ```dart
  /// Possible results of a version update check.
  enum UpdateStatus { available, upToDate, error }

  void applyUpdate() {}

  Future<UpdateStatus> checkForUpdate() async => UpdateStatus.error;

  void registerUpdateCallback(void Function() callback) {}
  ```

  Note: The `UpdateStatus` enum must be defined in BOTH files (web and stub) since they are conditionally imported — only one is compiled per platform.

- [ ] T007 [US2] Update `_checkUpdates()` in `frontend/lib/screens/dashboard_screen.dart` to use new API

  **What to change**: In `frontend/lib/screens/dashboard_screen.dart`:

  **Step 1** — Remove the `_swPollTimer` field declaration. Find (around line 48):
  ```dart
  Timer? _swPollTimer;
  ```
  Delete this line entirely.

  **Step 2** — Also remove any `_swPollTimer?.cancel()` call in the `dispose()` method if present.

  **Step 3** — Replace the `_checkUpdates()` method (lines 165-230). Find the current method:
  ```dart
  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateMessage = '';
      _updateAvailable = false;
    });

    if (kIsWeb) {
      // Already flagged by the browser?
      if (checkSwUpdate()) {
        ...
      }
      ...
      return;
    }

    if (mounted) {
      setState(() {
        _updateMessage = 'You are on the latest version';
        _checkingUpdate = false;
      });
    }
  }
  ```

  Replace with:
  ```dart
  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateMessage = '';
      _updateAvailable = false;
    });

    if (kIsWeb) {
      // Register callback for background detection
      registerUpdateCallback(() {
        if (mounted && !_updateAvailable) {
          setState(() {
            _updateAvailable = true;
            _updateMessage = 'A new version is ready to install';
            _checkingUpdate = false;
          });
        }
      });

      // Perform an immediate check
      final status = await checkForUpdate();
      if (mounted) {
        setState(() {
          switch (status) {
            case UpdateStatus.available:
              _updateAvailable = true;
              _updateMessage = 'A new version is available';
            case UpdateStatus.upToDate:
              _updateMessage = 'You are on the latest version';
            case UpdateStatus.error:
              _updateMessage = 'You are on the latest version';
          }
          _checkingUpdate = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _updateMessage = 'You are on the latest version';
        _checkingUpdate = false;
      });
    }
  }
  ```

  **Step 4** — Update the "Tap to update" handler. Find (around line 521):
  ```dart
  onTap: () { if (kIsWeb) applyPWAUpdate(); },
  ```
  Replace with:
  ```dart
  onTap: () { if (kIsWeb) applyUpdate(); },
  ```

- [ ] T008 [US2] Update `_checkUpdates()` in `frontend/lib/screens/settings_page.dart` to use new API

  **What to change**: In `frontend/lib/screens/settings_page.dart`:

  **Step 1** — Remove the `_swPollTimer` field declaration. Find (around line 49):
  ```dart
  Timer? _swPollTimer;
  ```
  Delete this line entirely.

  **Step 2** — Also remove any `_swPollTimer?.cancel()` call in the `dispose()` method if present.

  **Step 3** — Replace the `_checkUpdates()` method (lines 81-145). Find the current method:
  ```dart
  Future<void> _checkUpdates() async {
    setState(() {
      checkingUpdate = true;
      updateMessage = '';
      updateAvailable = false;
    });
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null) {
      ActivityLogService().logUpdateCheck(email);
    }

    if (kIsWeb) {
      if (checkSwUpdate()) {
        ...
      }
      ...
      return;
    }

    setState(() {
      updateMessage = 'You are on the latest version';
      checkingUpdate = false;
    });
  }
  ```

  Replace with:
  ```dart
  Future<void> _checkUpdates() async {
    setState(() {
      checkingUpdate = true;
      updateMessage = '';
      updateAvailable = false;
    });
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null) {
      ActivityLogService().logUpdateCheck(email);
    }

    if (kIsWeb) {
      // Register callback for background detection
      registerUpdateCallback(() {
        if (mounted && !updateAvailable) {
          setState(() {
            updateAvailable = true;
            updateMessage = 'A new version is ready to install';
            checkingUpdate = false;
          });
        }
      });

      // Perform an immediate check
      final status = await checkForUpdate();
      if (mounted) {
        setState(() {
          switch (status) {
            case UpdateStatus.available:
              updateAvailable = true;
              updateMessage = 'A new version is available';
            case UpdateStatus.upToDate:
              updateMessage = 'You are on the latest version';
            case UpdateStatus.error:
              updateMessage = 'You are on the latest version';
          }
          checkingUpdate = false;
        });
      }
      return;
    }

    setState(() {
      updateMessage = 'You are on the latest version';
      checkingUpdate = false;
    });
  }
  ```

  **Step 4** — Update the "Tap to update" handler. Find (around line 669):
  ```dart
  onTap: () { if (kIsWeb) applyPWAUpdate(); },
  ```
  Replace with:
  ```dart
  onTap: () { if (kIsWeb) applyUpdate(); },
  ```

**Checkpoint**: Dart layer can check for updates and register callbacks. Both screens use the new API. The old SW-specific functions are gone.

---

## Phase 5: US3 — Apply Update (Priority: P2)

**Goal**: The applyPWAUpdate JS function continues to work unchanged. The Dart layer calls it via the new `applyUpdate()` name.

**Independent Test**: Trigger `applyUpdate()` — overlay appears, page reloads once. Trigger twice — only one reload.

### Implementation

- [ ] T009 [US3] Verify applyPWAUpdate JS function uses single-fire guard in `frontend/web/index.html`

  **What to verify**: The existing `applyPWAUpdate` function (around lines 593-668 in `frontend/web/index.html`) already sets `window._swUpdateApplied = true` before reloading. However, since we renamed the guard variable in the new IIFE from `_swUpdateApplied` to `_pwaUpdateApplied`, we need to update the applyPWAUpdate function to use the new variable name.

  **What to change**: In the `applyPWAUpdate` function, find:
  ```javascript
  // Guard against re-triggering
  window._swUpdateApplied = true;
  ```
  Replace with:
  ```javascript
  // Guard against re-triggering
  window._pwaUpdateApplied = true;
  ```

  Also add a guard at the TOP of the function. Find:
  ```javascript
  window.applyPWAUpdate = async function() {
    var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  ```
  Replace with:
  ```javascript
  window.applyPWAUpdate = async function() {
    if (window._pwaUpdateApplied) return;  // already applying, prevent double reload
    var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  ```

**Checkpoint**: applyPWAUpdate is guarded against double-reload using the new `_pwaUpdateApplied` flag from the IIFE.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup and validation across all modified files.

- [ ] T010 Remove unused `dart:async` Timer import if no longer needed in `frontend/lib/screens/dashboard_screen.dart`

  **What to check**: After removing `_swPollTimer`, check if `Timer` is still used anywhere else in the file. If `Timer` is no longer referenced, the `dart:async` import can remain (it's likely used for other things like `Future`). Only remove if the linter flags it as unused.

- [ ] T011 Remove unused `dart:async` Timer import if no longer needed in `frontend/lib/screens/settings_page.dart`

  **What to check**: Same as T010 — check if `Timer` is still used after removing `_swPollTimer`. The `dart:async` import is likely still needed for `Future`.

- [ ] T012 Verify no other files reference the old function names (`checkSwUpdate`, `triggerSwUpdateCheck`, `checkVersionUpdate`, `applyPWAUpdate`)

  **What to do**: Search the entire `frontend/lib/` directory for references to:
  - `checkSwUpdate` — should have zero references
  - `triggerSwUpdateCheck` — should have zero references
  - `checkVersionUpdate` — should have zero references
  - `applyPWAUpdate` — should only appear in index.html JS (the function definition), NOT in any Dart files

  If any Dart files still reference these old names, update them to use the new names (`checkForUpdate`, `registerUpdateCallback`, `applyUpdate`).

- [ ] T013 Run quickstart.md testing checklist validation

  **What to do**: Walk through the testing checklist in `specs/017-pwa-version-update/quickstart.md` and verify each item can be tested with the implemented changes. This is a manual verification step — no code changes needed unless issues are found.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — proceed immediately
- **Foundational (Phase 2)**: No dependencies — T001, T002, T003 can all run in parallel
- **US5+US4 (Phase 3)**: Depends on T001 (deploy script). T004 modifies index.html
- **US1+US2 (Phase 4)**: Depends on T004 (index.html JS functions must exist). T005 and T006 can run in parallel. T007 and T008 depend on T005/T006 (new function signatures)
- **US3 (Phase 5)**: Depends on T004 (the new `_pwaUpdateApplied` variable)
- **Polish (Phase 6)**: Depends on all previous phases

### User Story Dependencies

- **US5 (Deploy Script)**: Independent — can start immediately
- **US4 (Page Load Seeding)**: Independent — can start immediately (modifies different file than US5)
- **US1 (Background Check)**: Depends on US4 (needs JS functions from index.html)
- **US2 (On-Demand Check)**: Depends on US4 (same JS functions) — runs in parallel with US1
- **US3 (Apply Update)**: Depends on US4 (needs `_pwaUpdateApplied` variable)

### Within Each Phase

- T001, T002, T003 are all parallel (different files)
- T005, T006 are parallel (different files, same new API)
- T007, T008 depend on T005/T006 (need new function names to exist)
- T010, T011, T012 are parallel (different files/checks)

### Parallel Opportunities

```text
# Phase 2 — all three in parallel:
T001: deploy_frontend.sh (releaseId field)
T002: nginx_flutter_app.conf (exact-match block)
T003: server/nginx/flutter_app.conf (same)

# Phase 4 — web and stub in parallel:
T005: pwa_update_web.dart (new interop)
T006: pwa_update_stub.dart (new stub)

# Phase 4 — both screens in parallel (after T005/T006):
T007: dashboard_screen.dart (new API calls)
T008: settings_page.dart (new API calls)

# Phase 6 — all cleanup in parallel:
T010: dashboard import check
T011: settings import check
T012: old reference search
```

---

## Implementation Strategy

### MVP First (US5 + US4 Only)

1. Complete Phase 2: Deploy script + nginx (T001-T003)
2. Complete Phase 3: index.html seeding + check functions (T004)
3. **STOP and VALIDATE**: Open browser console, verify `window._pwaSeededReleaseId` is set and `window.checkForAppUpdate()` returns `'upToDate'`
4. This validates the entire server → client pipeline before touching Dart code

### Incremental Delivery

1. Phase 2 (T001-T003) → Server infrastructure ready
2. Phase 3 (T004) → JS layer ready, testable in browser console
3. Phase 4 (T005-T008) → Dart layer integrated, app fully functional
4. Phase 5 (T009) → Single-fire guard aligned with new variable names
5. Phase 6 (T010-T013) → Cleanup and validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- The `applyPWAUpdate` JS function name is kept as-is in index.html (it's the global function name). Only the Dart wrapper is renamed to `applyUpdate()`.
- The `UpdateStatus` enum is defined in BOTH web and stub files (required by conditional import pattern).
- `dart:async` import is likely still needed in both screens for `Future` — only remove if linter flags it.
- Total tasks: 13 (3 foundational + 1 index.html + 4 Dart + 1 guard fix + 4 polish)
