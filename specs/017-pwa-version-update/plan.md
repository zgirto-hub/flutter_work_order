# Implementation Plan: Version-File Based PWA Update Detection

**Branch**: `017-pwa-version-update` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/017-pwa-version-update/spec.md`

## Summary

Replace the dual-mechanism PWA update detection (service worker event listeners + version.json fallback) with a single, unified version-file-based approach. The service worker event detection is unreliable on iOS Safari; the version.json polling approach works consistently across all browsers. This refactoring simplifies the detection logic to: (1) seed releaseId on page load, (2) compare on periodic/on-demand checks, (3) notify Dart via callback, (4) apply update with overlay reload. Four files change: deploy script, index.html, nginx config, and Dart interop layer.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend), Bash (deploy script), JavaScript (index.html inline)
**Primary Dependencies**: `dart:js_interop` (web interop), Flutter Material
**Storage**: N/A (in-memory releaseId comparison only)
**Testing**: Manual browser testing (cross-browser: Chrome, Safari, iOS Safari, Firefox)
**Target Platform**: Web (PWA) — all browsers, with emphasis on iOS Safari reliability
**Project Type**: Web application (Flutter PWA)
**Performance Goals**: Update check completes within 2 seconds
**Constraints**: version.json must never be served from cache; single-fire reload guard
**Scale/Scope**: Single version.json file (~50 bytes), checked per-user periodically

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **Pass (with exclusion)** | No backend API or DB migration needed — this is a client-side detection mechanism operating on a static file (version.json) generated at deploy time. Backend/DB layers are excluded because no server-side logic or data storage is involved. |
| II. Explicit Over Automatic | **Pass** | Update checks are explicit: triggered by periodic timer or on-demand user action. No silent auto-updates. |
| III. Role-Based Access Control | **Pass** | N/A — version.json is public information (deployment timestamp). No auth required. |
| IV. Server-First File Storage | **Pass** | N/A — no file uploads involved. version.json is a deploy artifact, not user content. |
| V. Client-Side Computation | **Pass** | Version comparison is performed client-side. Aligns with principle. |
| VI. Audit Everything | **Pass** | N/A — update detection is not a user-facing action requiring audit logging. The actual update apply is a page reload (browser-level), not an application action. |
| VII. Simplicity & YAGNI | **Pass** | Replacing complex SW event detection + fallback with single simple mechanism. Reduces code complexity. |

**Technology Constraints check**:
- `backend/version.json` not affected — this feature generates `build/web/version.json` (frontend deploy artifact, different file).

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/017-pwa-version-update/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
scripts/
└── deploy_frontend.sh          # Modified: version.json generation (already exists, refine releaseId field)

frontend/
├── web/
│   └── index.html              # Modified: replace SW event detection with version-file seeding + check
├── lib/
│   └── services/
│       ├── pwa_update_web.dart  # Modified: new UpdateService wrapping version-file JS functions
│       └── pwa_update_stub.dart # Modified: stub for new UpdateService API

nginx_flutter_app.conf          # Modified: add exact-match location for version.json
server/nginx/flutter_app.conf   # Modified: same change (server copy)
```

**Structure Decision**: This feature modifies existing files only — no new files or directories. The changes span the deploy pipeline (script), web runtime (index.html JS), server config (nginx), and Dart interop layer.

## Complexity Tracking

> No violations. Table not needed.
