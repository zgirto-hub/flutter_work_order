# Tasks: Collapsible AI Cards on Dashboard

**Feature**: 030-collapsible-ai-cards
**Spec**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Quickstart**: [quickstart.md](quickstart.md)

Single-file frontend change. All tasks edit [frontend/lib/screens/dashboard_screen.dart](../../frontend/lib/screens/dashboard_screen.dart).

---

## Phase 1: Setup

*(none — no new files, no new packages)*

## Phase 2: Foundational

- [X] T001 Add private widget `_CollapsibleCard` to `frontend/lib/screens/dashboard_screen.dart`

  - **What**: Append a new private `StatelessWidget` named `_CollapsibleCard` at the bottom of the file (next to `_StatCard`, `_QuickAction`, `_RecentActivityRow`).
  - **Signature**:
    ```dart
    class _CollapsibleCard extends StatelessWidget {
      final IconData icon;
      final String title;
      final bool expanded;
      final VoidCallback onTap;
      final Widget child;

      const _CollapsibleCard({
        required this.icon,
        required this.title,
        required this.expanded,
        required this.onTap,
        required this.child,
      });

      @override
      Widget build(BuildContext context);
    }
    ```
  - **Behavior**:
    - Outer `Container` using `AppColors.bgSurface`, `BorderRadius.circular(14)`, `Border.all(color: AppColors.border, width: 0.5)`.
    - Header row: `InkWell` (with matching `borderRadius`) wrapping a `Padding` (`EdgeInsets.symmetric(horizontal: 14, vertical: 12)`) containing a `Row`: `Icon(icon, size: 16, color: AppColors.accent)` → `SizedBox(width: 10)` → `Expanded(Text(title, style: 13/w600/AppColors.textPrimary))` → `AnimatedRotation(turns: expanded ? 0.5 : 0.0, duration: 200ms, child: Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textTertiary))`.
    - Body: `AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: expanded ? 1.0 : 0.0, child: Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 4), child: child))))`.
    - Wrap the outer `Container` with `Semantics(button: true, expanded: expanded, label: title, container: true, child: …)`.
  - **Inputs/outputs**: pure presentational; no side effects.
  - **Dependencies**: none.
  - **Acceptance**:
    - File compiles (`flutter analyze` passes).
    - Class is private (`_` prefix), not exported.
    - No changes anywhere else in the file yet.

## Phase 3: User Story 1 — Cards collapsed by default (P1)

**Goal**: AI Insights and AI Work Order render header-only on dashboard load.
**Independent test**: Open dashboard as admin/supervisor → both cards show only their headers.

- [X] T002 [US1] Add expansion state fields to `DashboardScreenState` in `frontend/lib/screens/dashboard_screen.dart`

  - **What**: In the state field block of `DashboardScreenState` (near `_loading`, `_refreshing`), add:
    ```dart
    bool _aiInsightsExpanded = false;
    bool _aiWorkOrderExpanded = false;
    ```
  - **Dependencies**: T001 (so the widget that consumes them exists).
  - **Acceptance**: Fields exist, default `false`, no other state altered.

- [X] T003 [US1] Wrap `AiInsightsCard` with `_CollapsibleCard` in `frontend/lib/screens/dashboard_screen.dart`

  - **What**: In `build`, locate the existing block:
    ```dart
    if (widget.userRole == 'admin' || widget.userRole == 'supervisor') ...[
      const SizedBox(height: 12),
      AiInsightsCard(email: _email, userRole: widget.userRole),
    ],
    ```
    Replace the `AiInsightsCard(...)` line with:
    ```dart
    _CollapsibleCard(
      icon: Icons.auto_awesome,
      title: 'AI Insights',
      expanded: _aiInsightsExpanded,
      onTap: () => setState(() => _aiInsightsExpanded = !_aiInsightsExpanded),
      child: AiInsightsCard(email: _email, userRole: widget.userRole),
    ),
    ```
  - **Dependencies**: T001, T002.
  - **Acceptance**: Dashboard renders with collapsed AI Insights header for admin/supervisor; reporter role unaffected (block still gated).

- [X] T004 [US1] Wrap `NlInputCard` with `_CollapsibleCard` in `frontend/lib/screens/dashboard_screen.dart`

  - **What**: In `build`, locate:
    ```dart
    const SizedBox(height: 12),
    NlInputCard(
      controller: _nlController,
      isGenerating: _isGenerating,
      onGenerate: _generateAiWorkOrder,
    ),
    ```
    Replace the `NlInputCard(...)` widget (keep the `SizedBox(height: 12)`) with:
    ```dart
    _CollapsibleCard(
      icon: Icons.auto_awesome,
      title: 'AI Work Order',
      expanded: _aiWorkOrderExpanded,
      onTap: () => setState(() => _aiWorkOrderExpanded = !_aiWorkOrderExpanded),
      child: NlInputCard(
        controller: _nlController,
        isGenerating: _isGenerating,
        onGenerate: _generateAiWorkOrder,
      ),
    ),
    ```
  - **Dependencies**: T001, T002.
  - **Acceptance**: Dashboard renders with collapsed AI Work Order header for all roles.

## Phase 4: User Story 2 — Tap-to-expand (P1)

*(implicitly satisfied by T001 + T003 + T004 — `_CollapsibleCard` already animates expand/collapse via `AnimatedSize` + `AnimatedRotation`. No additional code tasks.)*

## Phase 5: User Story 3 — Reset on launch (P3)

*(satisfied automatically: state lives in `DashboardScreenState`, defaults to `false` on every `initState`. No code tasks.)*

## Phase 6: Polish

- [X] T005 Manual verification per `quickstart.md` test plan

  - **What**: Run `flutter run -d chrome` (or any target) and execute every checkbox under "Manual test plan" in [quickstart.md](quickstart.md).
  - **Dependencies**: T001–T004.
  - **Acceptance**: All manual test items pass; no analyzer warnings introduced.

---

## Dependencies

```text
T001 → T002 → T003
            ↘ T004
T003,T004 → T005
```

## Parallel opportunities

- T003 and T004 are independent edits to different `build` blocks; they can be done in parallel after T001 + T002.

## MVP scope

T001 + T002 + T003 + T004 deliver the full feature (US1 + US2 + US3 are all satisfied by these four edits). T005 is verification only.

---

# Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/dashboard_screen.dart
Task: Append a new private `StatelessWidget` named `_CollapsibleCard` at the END of the file (after the existing `_RecentActivityRow` class and before or after the `StringCapitalize` extension — keep file order sensible). The widget renders a collapsible card chrome around a child widget. It must NOT modify any existing class. It must use the existing `AppColors` already imported via `../theme/app_theme.dart`.

Header layout: an `InkWell` (borderRadius matching the outer 14px) wrapping a `Padding(EdgeInsets.symmetric(horizontal: 14, vertical: 12))` containing a `Row` with: `Icon(icon, size: 16, color: AppColors.accent)`, `SizedBox(width: 10)`, `Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)))`, then `AnimatedRotation(turns: expanded ? 0.5 : 0.0, duration: const Duration(milliseconds: 200), child: Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textTertiary))`.

Body: `AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut, child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: expanded ? 1.0 : 0.0, child: Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 4), child: child))))`.

Outer: `Container(decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 0.5)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [header, body]))`. Wrap the entire returned widget in `Semantics(button: true, container: true, label: title, child: …)` and pass `expanded` via the `Semantics` properties as well using the `expanded` named arg.

Signatures required:
class _CollapsibleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;
  const _CollapsibleCard({required this.icon, required this.title, required this.expanded, required this.onTap, required this.child});
  @override
  Widget build(BuildContext context);
}

Constraints: Use only imports already present in the file. Do not add new top-level imports. Do not modify any other class, function, or import. Match the existing code style (2-space indent, trailing commas, const where possible).

Acceptance criteria:
- `flutter analyze frontend/lib/screens/dashboard_screen.dart` reports no new errors or warnings.
- Class is private (underscore prefix).
- No other section of the file is changed.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/dashboard_screen.dart
Task: In class `DashboardScreenState`, add two new private boolean state fields next to the existing `_loading`/`_refreshing` fields (around line 45-57):
  bool _aiInsightsExpanded = false;
  bool _aiWorkOrderExpanded = false;

Signatures required:
  bool _aiInsightsExpanded = false;
  bool _aiWorkOrderExpanded = false;

Constraints: Add the fields ONLY in `DashboardScreenState`. Do not touch `initState`, `dispose`, or any other method. Do not add any imports.

Acceptance criteria:
- The two fields exist with default value `false`.
- No other state, method, or field is modified.
- File still compiles.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/dashboard_screen.dart
Task: In the `build` method of `DashboardScreenState`, find the existing role-gated block:

  if (widget.userRole == 'admin' || widget.userRole == 'supervisor') ...[
    const SizedBox(height: 12),
    AiInsightsCard(
      email: _email,
      userRole: widget.userRole,
    ),
  ],

Replace the `AiInsightsCard(...)` widget with a `_CollapsibleCard` wrapping it:

  _CollapsibleCard(
    icon: Icons.auto_awesome,
    title: 'AI Insights',
    expanded: _aiInsightsExpanded,
    onTap: () => setState(() => _aiInsightsExpanded = !_aiInsightsExpanded),
    child: AiInsightsCard(
      email: _email,
      userRole: widget.userRole,
    ),
  ),

Signatures required: (none — uses the existing _CollapsibleCard from T001 and the state field from T002)

Constraints: Do not change the role gate. Do not change the surrounding `SizedBox(height: 12)`. Do not modify any other widget tree node.

Acceptance criteria:
- `AiInsightsCard` is now a child of `_CollapsibleCard`.
- The role gate (`admin || supervisor`) is preserved unchanged.
- Tapping the header toggles `_aiInsightsExpanded` via `setState`.
- File compiles, no analyzer warnings introduced.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/dashboard_screen.dart
Task: In the `build` method of `DashboardScreenState`, find the existing block:

  const SizedBox(height: 12),
  NlInputCard(
    controller: _nlController,
    isGenerating: _isGenerating,
    onGenerate: _generateAiWorkOrder,
  ),

Replace the `NlInputCard(...)` widget with a `_CollapsibleCard` wrapping it (keep the `SizedBox(height: 12)` exactly as is):

  _CollapsibleCard(
    icon: Icons.auto_awesome,
    title: 'AI Work Order',
    expanded: _aiWorkOrderExpanded,
    onTap: () => setState(() => _aiWorkOrderExpanded = !_aiWorkOrderExpanded),
    child: NlInputCard(
      controller: _nlController,
      isGenerating: _isGenerating,
      onGenerate: _generateAiWorkOrder,
    ),
  ),

Signatures required: (none — uses the existing _CollapsibleCard from T001 and the state field from T002)

Constraints: Do not modify `_nlController`, `_isGenerating`, `_generateAiWorkOrder`, or any other widget. Keep the preceding `SizedBox(height: 12)`. Do not introduce any new role gate.

Acceptance criteria:
- `NlInputCard` is now a child of `_CollapsibleCard` titled 'AI Work Order'.
- Tapping the header toggles `_aiWorkOrderExpanded` via `setState`.
- The card's existing controller, generation flow, and language toggle continue to work when expanded.
- File compiles, no analyzer warnings introduced.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: (no code edits — verification only)
Task: Run `flutter analyze` and then perform every manual test listed under "Manual test plan" in specs/030-collapsible-ai-cards/quickstart.md. Report any failures with screenshots or step-by-step reproduction. Do not modify code.

Signatures required: none

Constraints: Verification only. If a test fails, STOP and report — do not attempt fixes in this task.

Acceptance criteria:
- `flutter analyze` reports zero new errors/warnings vs. main.
- All manual test plan checkboxes pass.
--- END PROMPT T005 ---
