# Tasks: Dashboard AI Work Order Card with Draft Preview

**Input**: Design documents from `/specs/025-dashboard-ai-wo-card/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested — test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Audience**: This task file is designed for an LLM implementer to execute step by step. Each task is self-contained with exact file paths, clear acceptance criteria, and enough context to implement without ambiguity. After implementation, the work will be reviewed by a senior engineer.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Frontend**: `frontend/lib/` (Flutter/Dart)
- **No backend changes** — this feature is entirely client-side, reusing existing endpoints

---

## Phase 1: Setup

**Purpose**: No new dependencies needed. This phase is a prerequisite acknowledgment.

- [x] T001 Verify the current branch is `025-dashboard-ai-wo-card` and that the existing AI parse endpoint (`POST /ai/parse-work-order`) is working by confirming `backend/routers/ai_assist.py` contains the `parse_work_order` route handler. No code changes needed.

---

## Phase 2: Foundational — Extract Shared NL Input Widget (Blocking)

**Purpose**: Extract the NL input card from AddWorkOrderScreen into a shared widget. All user stories depend on this widget existing.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Create `frontend/lib/widgets/nl_input_card.dart` — a new shared `StatefulWidget` named `NlInputCard`. This widget is extracted from the existing NL card code in `frontend/lib/screens/Work_Orders/add_work_order.dart` (methods `_buildNlInputCard()` at line 570, `_buildNlCardContent()` at line 598, `_buildNlCardCollapsed()` at line 587).

  **Constructor parameters**:
  ```dart
  class NlInputCard extends StatefulWidget {
    final TextEditingController controller;  // The NL text input controller (owned by parent)
    final void Function(String text, String language)? onGenerate;  // Callback with text AND language
    final bool isGenerating;  // Loading state (controlled by parent)
    final bool collapsible;   // true = show collapse/expand toggle; false = always expanded
    const NlInputCard({
      super.key,
      required this.controller,
      this.onGenerate,
      this.isGenerating = false,
      this.collapsible = false,
    });
  }
  ```

  **Internal state** (managed by the widget itself):
  - `String _language = 'en';` — the selected dictation/AI language
  - `bool _expanded = true;` — collapse/expand state (only used when `collapsible: true`)
  - `bool _speechAvailable = DictationService.webSpeechApiLikelyAvailable;` — for mic button visibility

  **Imports needed**:
  ```dart
  import 'package:flutter/material.dart';
  import '../services/dictation_service.dart';
  import '../theme/app_theme.dart';
  import 'dictation_button.dart';
  ```

  **initState**: Call `DictationService().initialize().then((v) { if (mounted) setState(() => _speechAvailable = v); });`

  **Build method**: Renders a `Card` with `elevation: 2` containing:
  - If `collapsible`: wrap content in `AnimatedCrossFade` switching between expanded and collapsed states (same as existing code at line 575-582)
  - **Collapsed state** (only when `collapsible: true`): A `ListTile` with `Icon(Icons.auto_awesome, size: 18)`, title "AI Work Order", and expand `IconButton(icon: Icon(Icons.expand_more))`
  - **Expanded state**: A `Padding(padding: EdgeInsets.all(12))` containing a `Column`:
    1. Header row: `Icon(Icons.auto_awesome, size: 18)`, `SizedBox(width: 8)`, `Text("AI Work Order", style: TextStyle(fontWeight: FontWeight.bold))`, `Spacer()`, collapse button (only if `collapsible`)
    2. `SizedBox(height: 12)`
    3. `TextField(controller: widget.controller, maxLines: 3, readOnly: widget.isGenerating, decoration: InputDecoration(hintText: "Describe your work order in a sentence...", border: OutlineInputBorder()))`
    4. `SizedBox(height: 12)`
    5. Row containing:
       - Language chip builder: two `ChoiceChip` widgets for 'EN' and 'AR' (copy the `_buildDictationLanguageChip` pattern from `add_work_order.dart` line 551-568, using `_language` state variable and `AppColors.accent`)
       - `SizedBox(width: 8)`
       - `DictationButton(controller: widget.controller, language: _language, enabled: !widget.isGenerating)` — only show if `_speechAvailable`
       - `Spacer()`
       - Generate button: `ValueListenableBuilder<TextEditingValue>(valueListenable: widget.controller, builder: (ctx, value, _) { final canGenerate = !widget.isGenerating && value.text.trim().isNotEmpty; return ElevatedButton.icon(icon: Icon(widget.isGenerating ? Icons.hourglass_empty : Icons.auto_awesome), label: Text(widget.isGenerating ? "Generating..." : "Generate"), onPressed: canGenerate ? () => widget.onGenerate?.call(widget.controller.text.trim(), _language) : null); })`

  **Key detail**: The `onGenerate` callback passes BOTH the text and the selected language, so the parent knows which language to use for the AI call.

- [x] T003 Create `frontend/lib/widgets/ai_draft_bottom_sheet.dart` — a new file containing the draft preview bottom sheet function and enum.

  **Contents**:
  ```dart
  import 'package:flutter/material.dart';
  import '../theme/app_theme.dart';
  import 'bottom_sheet_widgets.dart';

  enum AiDraftAction { create, edit }
  ```

  **Function** `showAiDraftBottomSheet`:
  ```dart
  Future<AiDraftAction?> showAiDraftBottomSheet({
    required BuildContext context,
    required Map<String, dynamic> draftData,
  })
  ```

  Implementation:
  - Call `showAppBottomSheet<AiDraftAction>(context: context, child: _AiDraftContent(draftData: draftData))` — this uses the existing `showAppBottomSheet` from `frontend/lib/widgets/bottom_sheet_widgets.dart` which provides `BottomSheetContainer` with drag handle and consistent styling.

  **`_AiDraftContent` widget** (private StatelessWidget in the same file):
  - Renders a `Padding(padding: EdgeInsets.all(16))` containing a `Column(mainAxisSize: MainAxisSize.min)`:
    1. Header row: `Icon(Icons.auto_awesome, color: AppColors.accent)`, `SizedBox(width: 8)`, `Text("Draft Work Order", style: theme.textTheme.titleLarge)`
    2. `SizedBox(height: 16)`
    3. `Divider()`
    4. For each non-null field in draftData (`title`, `description`, `location`, `type`, `department`, `status`), render a `_DraftFieldRow`:
       - `Padding(padding: EdgeInsets.symmetric(vertical: 8))`
       - `Row(crossAxisAlignment: CrossAxisAlignment.start)`:
         - `SizedBox(width: 100, child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)))` — label in muted color
         - `SizedBox(width: 12)`
         - `Expanded(child: Text(value, style: theme.textTheme.bodyLarge))` — value in primary color
       - Skip rows where value is null or empty
    5. `SizedBox(height: 20)`
    6. Two buttons in a `Row`:
       - `Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, AiDraftAction.edit), child: Text("Edit")))` — outlined style
       - `SizedBox(width: 12)`
       - `Expanded(child: ElevatedButton(onPressed: titleIsEmpty ? null : () => Navigator.pop(context, AiDraftAction.create), child: Text("Create")))` — disabled if `draftData['title']` is null or empty (title is required)

  **Field labels mapping** (for display):
  ```dart
  final fields = [
    ('Title', draftData['title']),
    ('Description', draftData['description']),
    ('Location', draftData['location']),
    ('Type', draftData['type']),
    ('Department', draftData['department']),
    ('Status', draftData['status']),
  ];
  ```

- [x] T004 Refactor `frontend/lib/screens/Work_Orders/add_work_order.dart` to use the shared `NlInputCard` widget.

  **Add import**:
  ```dart
  import '../../widgets/nl_input_card.dart';
  ```

  **Remove these methods** (they are now in NlInputCard):
  - `_buildNlInputCard()` (around line 570-585)
  - `_buildNlCardCollapsed()` (around line 587-596)
  - `_buildNlCardContent()` (around line 598-656)

  **Keep** `_buildDictationLanguageChip()` (around line 551-568) — it's still used for the language chips above the Title/Description fields for dictation (from feature 022). Do NOT remove it.

  **Keep** `_generateFromNl()` (around line 658-744) — the auto-fill logic is specific to this screen. Do NOT remove it.

  **Replace** the `_buildNlInputCard()` call in `_buildDetailsTab()` (around line 1478: `if (widget.workOrder == null) _buildNlInputCard()`) with:
  ```dart
  if (widget.workOrder == null)
    NlInputCard(
      controller: _nlInputController,
      isGenerating: _isGenerating,
      collapsible: true,
      onGenerate: (text, language) {
        _dictationLanguage = language;
        _generateFromNl();
      },
    ),
  ```

  **Verify**: After this refactoring, the Add Work Order screen's NL card should look and behave exactly as before. The `_generateFromNl()` method still reads from `_nlInputController` and uses `_dictationLanguage` — both are set correctly by the callback.

- [x] T005 Add new prefill parameters to `AddWorkOrderScreen` constructor

  **Add to the class** (near existing `prefillTitle` and `prefillLocation` at line 38-39):
  ```dart
  final String? prefillDescription;
  final String? prefillType;
  final String? prefillStatus;
  final String? prefillDepartment;
  final String? prefillDepartmentId;
  ```

  **Add to constructor** (near existing named parameters at line 46-49):
  ```dart
  this.prefillDescription,
  this.prefillType,
  this.prefillStatus,
  this.prefillDepartment,
  this.prefillDepartmentId,
  ```

  **Apply prefills in initState** (near the existing prefill block around line 219 where `prefillTitle` is applied):
  ```dart
  if (widget.prefillDescription != null) {
    descriptionController.text = widget.prefillDescription!;
  }
  if (widget.prefillLocation != null) {
    locationController.text = widget.prefillLocation!;
  }
  ```
  Note: `prefillLocation` is already applied — just verify it's there. Add for the new fields:
  ```dart
  if (widget.prefillType != null) {
    final allowedTypes = ['Technical', 'Inspection', 'Other'];
    if (allowedTypes.contains(widget.prefillType)) {
      selectedType = widget.prefillType!;
    }
  }
  if (widget.prefillStatus != null) {
    if (_allowedStatuses.contains(widget.prefillStatus)) {
      selectedStatus = widget.prefillStatus!;
    }
  }
  if (widget.prefillDepartment != null) {
    selectedDepartment = widget.prefillDepartment!;
  }
  if (widget.prefillDepartmentId != null && widget.prefillDepartmentId!.isNotEmpty) {
    selectedDepartmentId = widget.prefillDepartmentId!;
  }
  ```

**Checkpoint**: The NlInputCard widget exists as a shared widget. The AiDraftBottomSheet exists. AddWorkOrderScreen uses the shared widget and accepts all prefill params. The Add Work Order screen works exactly as before.

---

## Phase 3: User Story 1 — Generate and Quick-Create from Dashboard (Priority: P1) MVP

**Goal**: User types a sentence on the Dashboard, taps Generate, sees draft bottom sheet, taps Create, work order is submitted.

**Independent Test**: Open Dashboard, type "broken AC unit in room 205, urgent", tap Generate, review draft, tap Create, verify success SnackBar and stats refresh.

### Implementation for User Story 1

- [x] T006 [US1] Add AI Work Order card to `frontend/lib/screens/dashboard_screen.dart`

  **Add imports** at the top of the file:
  ```dart
  import '../widgets/nl_input_card.dart';
  import '../widgets/ai_draft_bottom_sheet.dart';
  import '../services/ai_assist_service.dart';
  import '../services/department_service.dart';
  import '../services/work_order_service.dart';
  import '../models/department.dart';
  import '../models/work_order.dart';
  import 'Work_Orders/add_work_order.dart';
  ```

  **Add state variables** in `DashboardScreenState` (near the other state variables):
  ```dart
  // AI Work Order state
  final TextEditingController _nlController = TextEditingController();
  bool _isGenerating = false;
  List<Department>? _cachedDepartments;
  ```

  **Add to dispose()** (there's an existing dispose method — add `_nlController.dispose();` before `super.dispose()`).

  **Insert the NlInputCard** in the build method's Column, between the AI Insights card block (around line 459) and the `SizedBox(height: 24)` before Quick Actions (around line 461). Add:
  ```dart
  const SizedBox(height: 12),
  NlInputCard(
    controller: _nlController,
    isGenerating: _isGenerating,
    onGenerate: _generateAiWorkOrder,
  ),
  ```

  This places the AI card below stats/AI Insights and above Quick Actions, visible to all roles.

- [x] T007 [US1] Implement `_generateAiWorkOrder()` method in `frontend/lib/screens/dashboard_screen.dart`

  ```dart
  static const List<String> _allowedTypes = ['Technical', 'Inspection', 'Other'];
  static const List<String> _allowedStatuses = ['Pending', 'In Progress', 'Closed'];

  Future<void> _generateAiWorkOrder(String text, String language) async {
    if (text.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please describe your work order in more detail.')),
        );
      }
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Fetch departments on demand (cache for session)
      _cachedDepartments ??= await DepartmentService().fetchDepartments(isActive: true);

      final departmentNames = _cachedDepartments!.map((d) => d.name).toList();

      // Call AI parse
      final response = await AiAssistService().parseWorkOrder(
        text: text,
        language: language,
        departments: departmentNames,
        types: _allowedTypes,
        statuses: _allowedStatuses,
      );

      if (!mounted) return;
      setState(() => _isGenerating = false);

      // Resolve department ID from name
      String? deptId;
      final deptName = response['department'] as String?;
      if (deptName != null) {
        final dept = _cachedDepartments!.where((d) => d.name == deptName).firstOrNull;
        deptId = dept?.id;
      }

      final draftData = <String, dynamic>{
        ...response,
        'departmentId': deptId ?? '',
      };

      // Show draft bottom sheet
      final action = await showAiDraftBottomSheet(
        context: context,
        draftData: draftData,
      );

      if (!mounted || action == null) return;

      if (action == AiDraftAction.create) {
        await _createWorkOrderFromDraft(draftData);
      } else if (action == AiDraftAction.edit) {
        _navigateToEditWithPrefill(draftData);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  ```

- [x] T008 [US1] Implement `_createWorkOrderFromDraft()` method in `frontend/lib/screens/dashboard_screen.dart`

  ```dart
  Future<void> _createWorkOrderFromDraft(Map<String, dynamic> data) async {
    try {
      // Generate job number (same pattern as work_order_home.dart line 758)
      final now = DateTime.now();
      final jobNo = 'WO${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final wo = WorkOrder(
        id: '',
        jobNo: jobNo,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        location: data['location'] ?? '',
        type: data['type'] ?? 'Technical',
        status: data['status'] ?? 'Pending',
        departmentId: data['departmentId'] ?? '',
        departmentName: data['department'] ?? '',
        dateCreated: DateTime.now().toUtc().toIso8601String(),
        dateModified: DateTime.now().toUtc().toIso8601String(),
      );

      await WorkOrderService().addWorkOrder(wo);

      if (!mounted) return;
      _nlController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Work order created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _load(); // Refresh dashboard stats
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create work order: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  ```

  **Important**: Check the `WorkOrder` constructor in `frontend/lib/models/work_order.dart` to ensure you pass the correct parameter names. The model may use different field names — read the constructor and adjust accordingly. Common fields: `id`, `jobNo`, `title`, `description`, `location`, `type`, `status`, `departmentId`, `departmentName`, `dateCreated`, `dateModified`. Some may be positional, some named. Adapt.

  Also check `WorkOrderService().addWorkOrder()` in `frontend/lib/services/work_order_service.dart` to understand what it expects and what it returns. Follow the same pattern used in `add_work_order.dart`'s submit method (around line 1178-1192).

**Checkpoint**: User can type on Dashboard, tap Generate, see draft, tap Create, and the work order is submitted. Success SnackBar appears, stats refresh. This is the MVP.

---

## Phase 4: User Story 2 — Edit Draft Before Submitting (Priority: P2)

**Goal**: User taps "Edit" on the draft bottom sheet and navigates to AddWorkOrderScreen with all fields pre-filled.

**Independent Test**: Generate a draft, tap Edit, verify AddWorkOrderScreen opens with all fields pre-filled.

### Implementation for User Story 2

- [x] T009 [US2] Implement `_navigateToEditWithPrefill()` method in `frontend/lib/screens/dashboard_screen.dart`

  ```dart
  void _navigateToEditWithPrefill(Map<String, dynamic> data) {
    // Generate job number for the new work order
    final now = DateTime.now();
    final jobNo = 'WO${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddWorkOrderScreen(
          autoGeneratedJobNo: jobNo,
          prefillTitle: data['title'],
          prefillDescription: data['description'],
          prefillLocation: data['location'],
          prefillType: data['type'],
          prefillStatus: data['status'],
          prefillDepartment: data['department'],
          prefillDepartmentId: data['departmentId'],
          userRole: widget.userRole,
        ),
      ),
    ).then((result) {
      if (mounted && result != null) {
        _nlController.clear();
        _load(); // Refresh dashboard stats
      }
    });
  }
  ```

  This navigates to AddWorkOrderScreen with all parsed fields pre-filled. When the user submits from there and pops back, the dashboard clears the input and refreshes.

**Checkpoint**: User can generate a draft, tap Edit, and see AddWorkOrderScreen with all fields pre-filled.

---

## Phase 5: User Story 3 — Voice Dictation on Dashboard (Priority: P2)

**Goal**: User speaks into the mic on the Dashboard AI card, then taps Generate.

**Independent Test**: Tap mic on Dashboard AI card, speak, verify transcription, tap Generate, verify draft appears.

### Implementation for User Story 3

- [x] T010 [US3] Verify the `DictationButton` works on the Dashboard's `NlInputCard`. The `NlInputCard` (created in T002) already includes a `DictationButton` with `controller: widget.controller` and `language: _language`. Since `_nlController` is passed from the Dashboard, voice dictation should work automatically.

**Checkpoint**: Voice dictation works on the Dashboard AI card.

---

## Phase 6: User Story 4 — Arabic Language Support (Priority: P3)

**Goal**: Arabic input is correctly parsed and displayed in the draft.

**Independent Test**: Select AR, type Arabic, tap Generate, verify Arabic content in draft.

### Implementation for User Story 4

- [x] T011 [US4] Verify Arabic support works end-to-end.

**Checkpoint**: Arabic input produces Arabic draft output.

---

## Phase 7: User Story 5 — Shared Widget Parity (Priority: P1)

**Goal**: The NlInputCard behaves identically on both Dashboard and AddWorkOrderScreen.

### Implementation for User Story 5

- [x] T012 [US5] Verify shared widget parity between Dashboard and AddWorkOrderScreen.

**Checkpoint**: Both screens use the same widget with consistent behavior.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases and final refinements.

- [x] T013 Handle the case where `WorkOrderService().addWorkOrder()` requires fields that the AI draft might not provide.

- [x] T014 Handle the error case where the draft bottom sheet "Create" button is tapped but submission fails.

- [x] T015 Ensure the Dashboard refreshes properly after work order creation.

- [x] T016 Verify the NL input clears after both Create and Edit flows:

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — precondition check
- **Foundational (Phase 2)**: Depends on Phase 1 — creates shared widgets and refactors AddWO screen
- **User Stories (Phase 3-7)**: All depend on Phase 2
  - US1 (Phase 3): Can start after Phase 2 — **This is the MVP**
  - US2 (Phase 4): Depends on US1 (needs `_generateAiWorkOrder` and draft sheet)
  - US3 (Phase 5): Depends on Phase 2 (NlInputCard with mic button)
  - US4 (Phase 6): Depends on Phase 2 (NlInputCard with language chips)
  - US5 (Phase 7): Depends on T004 (refactored AddWO) and T006 (Dashboard integration)
- **Polish (Phase 8)**: Depends on all user stories

### User Story Dependencies

- **US1 (P1)**: Foundation only — **This is the MVP**
- **US2 (P2)**: Depends on US1 (draft bottom sheet must exist)
- **US3 (P2)**: Depends on Phase 2 only (NlInputCard includes mic button)
- **US4 (P3)**: Depends on Phase 2 only (NlInputCard includes language chips)
- **US5 (P1)**: Depends on Phase 2 T004 (refactored AddWO) — verification task

### Within Phase 2 (Foundational)

- T002 (NlInputCard) and T003 (AiDraftBottomSheet) can be done in parallel (different files)
- T004 (refactor AddWO) depends on T002 (needs NlInputCard to exist)
- T005 (prefill params) can be done in parallel with T002/T003 (different section of same file, but safer sequentially after T004)

### Parallel Opportunities

- T002 and T003 can run in parallel (new files, no dependencies)
- T010, T011, T012 (verification tasks) can run in parallel
- T013-T016 (polish tasks) can run in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002, T003, T004, T005)
3. Complete Phase 3: User Story 1 (T006, T007, T008)
4. **STOP and VALIDATE**: Type a sentence on Dashboard, tap Generate, see draft, tap Create, verify success
5. This alone delivers core value — quick-create from Dashboard

### Incremental Delivery

1. Setup + Foundational → Shared widgets extracted, AddWO refactored
2. Add US1 (Dashboard Create) → Test → **MVP ready**
3. Add US2 (Edit flow) → Test → Full create-or-edit experience
4. Add US3 (Voice on Dashboard) → Test → Hands-free Dashboard
5. Add US4 (Arabic) → Test → Bilingual support
6. Add US5 (Widget parity) → Test → Consistency verified
7. Polish → Edge cases → **Feature complete**

### Step-by-Step for LLM Implementer

Execute tasks in strict numerical order (T001 → T002 → ... → T016). After each task:
1. Save the file
2. Verify no compilation errors (`flutter analyze` or IDE error check)
3. Move to the next task

After completing each phase checkpoint, test the feature as described.

---

## Notes

- **No backend changes**: All 16 tasks are frontend-only. The existing `POST /ai/parse-work-order` endpoint (from 024) is reused.
- **Existing widget reuse**: `DictationButton` (022), `BottomSheetContainer`/`showAppBottomSheet` (existing), `AiAssistService.parseWorkOrder()` (024), `WorkOrderService.addWorkOrder()` (existing).
- **Field naming**: "Title" field uses `clientController` in AddWO screen. The `prefillTitle` param already exists.
- **Job number pattern**: `WO${YY}${MM}${DD}-${HH}${mm}${ss}` — same as `work_order_home.dart` line 758.
- **Dashboard state**: `_load()` is the existing method that refreshes all dashboard data.
- Commit after each phase completion.
- The reviewer will check: shared widget extraction correctness, draft bottom sheet UX, Create flow end-to-end, prefill param application, and stats refresh.
