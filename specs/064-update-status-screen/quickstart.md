# Phase 1 — Quickstart: Verifying Spec 064

## Preconditions

- Checked out `064-update-status-screen` in the `flutter_work_order_spec064` worktree.
- Flutter SDK installed; dev server reachable.
- Backend + Supabase in a post-spec-061 state (7 canonical systems). If unavailable, use a pre-migration DB — behavior is still correct, just with more cards.

## Steps

### 1. Static check (SC-005)

```bash
cd frontend
flutter analyze lib/screens/system_status_screen.dart
```

Expect: zero new warnings attributable to this change.

### 2. Launch the app

```bash
cd frontend
flutter run -d chrome
```

Navigate to **System Status**.

### 3. Verify flat grid (SC-001, User Story 1)

- Count the cards. Post-migration: exactly 7.
- Confirm zero expandable group rows / caret / chevron anywhere in the systems area.
- Confirm cards wrap 3 per row (unchanged grid layout, FR-008).

### 4. Verify full names (SC-002, User Story 2)

- For each card, read the name. No card reads a substring like "Sector A" — every card shows the full `systemName` returned by the API.

### 5. Verify no SAT badge (SC-003, User Story 2)

- Visually scan every card. No yellow "SAT" pill anywhere.

### 6. Report / Resolve / Edit / Delete regression (SC-004, User Story 1 + 3)

For **an OK card**:
- Tap card → Report Issue sheet opens with the correct system name pre-filled in the subheader.
- Pick a date, enter a note, submit. Expect success snackbar; card flips to "Issue" with red indicator.

For **an Issue card**:
- Tap card → Issue Details sheet opens with edit/resolve actions.
- Tap Resolve. Expect card to flip back to OK; a new entry appears in Recent Issues with `resolvedAt`.

For **Recent Issues section** (User Story 3):
- Confirm repointed rows display "AIDA-NG" (or the stored canonical name for your data).
- Open a history card's overflow menu → Edit → confirm sheet opens.
- Open overflow menu → Delete → confirm dialog appears; accept and confirm row disappears.

### 7. Uptime report regression

- Tap the uptime report entry point (unchanged by this spec).
- Confirm it renders per-system rows as before. No change expected.

### 8. Pre-migration fallback sanity (optional)

If pointed at a pre-061 DB:
- Confirm all rows render as peer cards (no grouping).
- Confirm names display verbatim (e.g., a card literally reading "AIDA-NG - Sector A" is acceptable for this spec).

## Pass criteria

All seven sections above succeed. `flutter analyze` clean. No user-visible regression in report / resolve / edit / delete / uptime flows.
