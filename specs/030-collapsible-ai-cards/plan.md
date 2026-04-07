# Implementation Plan: Collapsible AI Cards on Dashboard

**Branch**: `030-collapsible-ai-cards` | **Date**: 2026-04-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/030-collapsible-ai-cards/spec.md`

## Summary

Make the existing `AiInsightsCard` and `NlInputCard` ("AI Work Order") on the dashboard render collapsed by default, showing only an icon + title + chevron header. Tapping the header smoothly expands the card to reveal its existing full content; tapping again collapses it. Each card's expansion state is independent, lives only in `DashboardScreenState` (no persistence), and existing functionality (filters, dictation, generation, insights refresh) is unchanged once expanded.

Technical approach: introduce a small, reusable `CollapsibleSection` widget (or two `bool` state fields + `AnimatedSize`/`AnimatedCrossFade` inline) in `frontend/lib/screens/dashboard_screen.dart`. The internal `AiInsightsCard` and `NlInputCard` widgets are kept alive across collapse so in-flight work and typed text are preserved (Flutter automatically preserves State as long as the widget remains in the tree — the body is hidden via animation, not removed).

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x
**Primary Dependencies**: Flutter Material (existing), `AiInsightsCard` (existing), `NlInputCard` (existing)
**Storage**: N/A — UI state only, in-memory, not persisted
**Testing**: Manual UI verification on dashboard; existing widget tests (none specific to these cards)
**Target Platform**: Flutter Web (PWA) + mobile builds — same code path
**Project Type**: Mobile/web frontend (Flutter)
**Performance Goals**: Expand/collapse animation < 300 ms; no jank at 60 fps
**Constraints**: Must preserve in-flight AI generation, insights loading, and typed input across collapse/expand cycles
**Scale/Scope**: Two card instances on a single screen (`dashboard_screen.dart`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ N/A | Frontend-only UI tweak; no backend, DB, model, service, or navigation changes. Layer exclusion is justified: pure presentational state. |
| II. Explicit Over Automatic | ✅ Pass | Expansion is user-initiated by tap; no automatic open/close behavior. |
| III. Role-Based Access Control | ✅ Pass | No permission changes. Existing role gating around `AiInsightsCard` (admin/supervisor only) is preserved. |
| IV. Server-First File Storage | ✅ N/A | No files involved. |
| V. Client-Side Computation Where Possible | ✅ Pass | UI state lives entirely on the client. |
| VI. Audit Everything | ✅ N/A | Toggling collapse is ephemeral UI state, not an auditable domain event. |
| VII. Simplicity & YAGNI | ✅ Pass | No new packages, no abstractions beyond what is needed for two cards. |

**Result**: PASS — no violations; Complexity Tracking section unused.

## Project Structure

### Documentation (this feature)

```text
specs/030-collapsible-ai-cards/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
└── checklists/
    └── requirements.md  # Spec quality checklist
```

No `data-model.md` (no entities), no `contracts/` (no external interfaces).

### Source Code (repository root)

```text
frontend/
└── lib/
    └── screens/
        └── dashboard_screen.dart   # MODIFIED — wrap AiInsightsCard and NlInputCard with collapsible headers; add _aiInsightsExpanded, _aiWorkOrderExpanded state fields
```

**Structure Decision**: Single-file change inside the existing Flutter frontend at `frontend/lib/screens/dashboard_screen.dart`. No new files are required; if the inline approach grows beyond ~40 lines, extract a private `_CollapsibleCard` widget in the same file (still no new files).

## Complexity Tracking

> No constitution violations. Section intentionally empty.
