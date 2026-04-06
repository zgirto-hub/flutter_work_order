# Tasks: AI-Powered Analytics & Insights

**Input**: Design documents from `/specs/021-ai-analytics-insights/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ai-insights.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create new files and register the router

- [ ] T001 Create backend router file with request model, Ollama config, and preamble stripping (English + Arabic) in `backend/routers/ai_insights.py`. Follow the pattern from `backend/routers/ai_assist.py`. Include: `AiInsightRequest` Pydantic model with `insight_type` (str, required), `date_range_days` (int, default 30), `language` (str, default "en"). Add Ollama constants: `OLLAMA_MODEL = "gemma4:e2b"`, `OLLAMA_URL = "http://localhost:11434/api/generate"`, `OLLAMA_TIMEOUT = 60`. Implement `_strip_preamble()` with both English phrases ("Here", "Sure", "Of course", "Certainly", "Below", "I'd", "I would") and Arabic phrases ("بالتأكيد", "إليك", "بالطبع", "حسناً"). Add role validation helper that checks `user_role in ("admin", "supervisor")` and raises HTTP 403 if not.
- [ ] T002 Register ai_insights router in `backend/main.py`. Add `from routers import ai_insights` to the import block (around line 25) and `app.include_router(ai_insights.router, prefix="/api")` in the registration section (around line 81).
- [ ] T003 [P] Create frontend service file `frontend/lib/services/ai_insights_service.dart`. Follow the pattern from `frontend/lib/services/ai_assist_service.dart`. Include: `AiInsightsService` class with method `Future<Map<String, dynamic>> getInsight({required String insightType, required String email, required String userRole, int dateRangeDays = 30, String language = "en"})`. POST to `${AppConfig.baseUrl}/ai/insights?email=$email&user_role=$userRole`. Request body: `{"insight_type": insightType, "date_range_days": dateRangeDays, "language": language}`. Frontend timeout: 65 seconds. Error mapping: 403 → "Access denied", 503 → "AI service is currently unavailable. Please try again later.", 502 → "AI could not generate insights. Please try again.", 422 → extract detail message, TimeoutException → "Request timed out. Please try again.", other → "Failed to get AI insights."

**Checkpoint**: Backend has empty router registered, frontend has service ready to call endpoint.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Data aggregation functions that ALL insight types depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Implement `_aggregate_work_order_stats(days: int) -> dict` in `backend/routers/ai_insights.py`. Query `work_orders` table with `from db import supabase`. Use `.select("status, type, department_id, location, created_at, closed_at")` with `.gte("created_at", cutoff_date.isoformat())`. Compute: `total` count, `by_status` dict (Pending/In Progress/Resolved/Closed counts), `by_type` dict (Technical/Inspection/Other counts), `by_department` list (join with `departments` table via separate `.select("id, name")` query to resolve names), `avg_resolution_hours` (mean of `closed_at - created_at` for closed orders, in hours), `weekly_volumes` list (group by ISO week number), `top_locations` list (top 5 locations by frequency, exclude empty). Return as dict matching `WorkOrderStats` from data-model.md.
- [ ] T005 [P] Implement `_aggregate_system_status_stats(days: int) -> dict` in `backend/routers/ai_insights.py`. Query `system_status_reports` table with `.select("system_name, report_date, notes, resolved_at, resolved_notes")` and `.gte("report_date", cutoff_date.isoformat())`. Also query unresolved issues separately: `.is_("resolved_at", "null")`. Compute: `currently_unresolved` list (system_name, report_date, notes for null resolved_at), `issues_per_system` list (count per system_name, sorted desc), `avg_resolution_hours_per_system` list (mean resolved_at - report_date per system), `clean_systems` list (from the 33 allowed systems, those with zero issues in range), `worst_systems` list (top 5 by issue count). Return as dict matching `SystemStatusStats` from data-model.md.

**Checkpoint**: Both aggregation functions return correct dicts from Supabase data.

---

## Phase 3: User Story 1 — View Operational Overview (Priority: P1) 🎯 MVP

**Goal**: Admin/supervisor can generate an AI-powered executive summary of operational health from the dashboard.

**Independent Test**: Log in as admin, navigate to dashboard, tap "Overview" insight type, see 3-5 bullet points summarizing work order counts, busiest departments, system health, and avg resolution time. Verify role guard returns 403 for non-admin.

### Implementation for User Story 1

- [ ] T006 [US1] Implement `_build_overview_prompt(wo_stats: dict, sys_stats: dict, language: str) -> str` in `backend/routers/ai_insights.py`. Prompt template: Start with "You are an operations analyst for a civil aviation technical department." Then feed a compact data section: "WORK ORDER STATS: Total: {total}, Pending: {pending}, In Progress: {in_progress}, Closed: {closed}. By type: Technical={tech}, Inspection={insp}, Other={other}. Avg resolution time: {avg_hours} hours. Busiest department: {dept_name} ({dept_count} orders). Top locations: {locations}." Then "SYSTEM STATUS: Currently down: {down_count} systems ({down_names}). Issues this period: {issue_count}. Most affected: {worst_system} ({worst_count} issues)." End with "Provide 3-5 concise bullet points summarizing operational health. No preamble, greeting, or commentary." If `language == "ar"`, append "Respond entirely in Arabic."
- [ ] T007 [US1] Implement the main `POST /api/ai/insights` endpoint in `backend/routers/ai_insights.py`. Use `@router.post("/ai/insights")`. Accept `request: AiInsightRequest`, `email: str = Query(...)`, `user_role: str = Query(...)`. Validate role (403 if not admin/supervisor). Validate `insight_type` is one of "overview", "system_status", "trends" (422 if not). Call `_aggregate_work_order_stats(request.date_range_days)`. Check if `total < 5` → return 422 with "Not enough data for meaningful analysis. Try a wider date range." Call `_aggregate_system_status_stats(request.date_range_days)`. For `insight_type == "overview"`: call `_build_overview_prompt()`. Send prompt to Ollama via `httpx.AsyncClient` POST to `OLLAMA_URL` with body `{"model": OLLAMA_MODEL, "prompt": prompt, "stream": False}`, timeout `OLLAMA_TIMEOUT`. Extract `response` field. Strip preamble. Log activity via `log_activity(email, "ai", "generated_insight", target_label=request.insight_type)`. Return `{"insight": stripped_text, "generated_at": datetime.utcnow().isoformat() + "Z", "data_summary": {"total_work_orders": total, "pending": ..., "in_progress": ..., "closed": ..., "systems_down": len(unresolved), "date_range_days": request.date_range_days}}`. Handle errors: `httpx.ConnectError`/`httpx.ConnectTimeout` → 503, `httpx.ReadTimeout` → 503, empty response → 502.
- [ ] T008 [US1] Create the `AiInsightsCard` widget in `frontend/lib/features/analytics/ai_insights_card.dart`. StatefulWidget that accepts `email` (String), `userRole` (String). State: `_insightText` (String?), `_loading` (bool), `_generatedAt` (DateTime?), `_selectedType` (String, default "overview"), `_selectedLanguage` (String, default "en"). Build method: Container with `AppColors.bgSurface` background, 14px border radius, 0.5px border (`AppColors.border`), 14px padding. Header row: sparkle icon (`Icons.auto_awesome`) in 32x32 accent-colored box with 9px radius, "AI Insights" label in `AppColors.textPrimary` 15px bold, spacer, refresh IconButton (disabled when loading). Second row: insight type selector — three `ChoiceChip` or `SegmentedButton` for "Overview", "Systems", "Trends" mapped to "overview"/"system_status"/"trends". Third row: language toggle — two small chips "EN" / "AR". Body: if loading, show `CircularProgressIndicator`; if `_insightText != null`, render text in `AppColors.textPrimary` with `textDirection` set to `TextDirection.rtl` when `_selectedLanguage == "ar"`, else `TextDirection.ltr`. Footer: "Generated X min ago" in `AppColors.textTertiary` 11px. Method `_generateInsight()`: set loading true, call `AiInsightsService().getInsight(...)`, set result text and timestamp, handle errors with `ScaffoldMessenger.of(context).showSnackBar()`, set loading false in `finally`. Auto-trigger on type/language change.
- [ ] T009 [US1] Integrate `AiInsightsCard` into `frontend/lib/screens/dashboard_screen.dart`. Import `ai_insights_card.dart`. In the build method, after the stats row section (around line 451) and before Quick Actions, add a conditional block: `if (widget.userRole == 'admin' || widget.userRole == 'supervisor') ... AiInsightsCard(email: widget.email, userRole: widget.userRole)`. Wrap in `Padding` with `EdgeInsets.symmetric(horizontal: 16, vertical: 8)`.

**Checkpoint**: Admin can generate an "Overview" insight from the dashboard. Non-admin users don't see the card. Endpoint returns 403 for unauthorized users. Insufficient data returns 422 with helpful message.

---

## Phase 4: User Story 2 — Analyze System Status Health (Priority: P2)

**Goal**: Admin/supervisor can generate a focused AI analysis of system reliability, identifying problematic and healthy systems.

**Independent Test**: Select "Systems" insight type on the dashboard card, verify the response identifies specific systems by name with issue counts.

### Implementation for User Story 2

- [ ] T010 [US2] Implement `_build_system_status_prompt(sys_stats: dict, language: str) -> str` in `backend/routers/ai_insights.py`. Prompt template: Start with "You are a systems reliability analyst for civil aviation infrastructure." Then "SYSTEMS WITH ISSUES:" followed by per-system table (system_name: count issues, avg resolution hours). Then "CURRENTLY UNRESOLVED:" followed by list of unresolved system names with report dates and notes. Then "SYSTEMS WITH ZERO ISSUES: {clean_systems joined by comma}." End with "Write 3-5 concise bullet points identifying which systems need attention, any patterns in failures, and which systems are performing well. Be specific with system names and numbers. No preamble." If `language == "ar"`, append "Respond entirely in Arabic."
- [ ] T011 [US2] Add `insight_type == "system_status"` branch to the main endpoint in `backend/routers/ai_insights.py`. In the existing endpoint handler, add an `elif request.insight_type == "system_status":` branch that calls `_build_system_status_prompt(sys_stats, request.language)` and follows the same Ollama call → strip preamble → return response pattern as the overview branch. The `data_summary` should include `systems_with_issues` count and `currently_unresolved` count instead of work order status breakdown.

**Checkpoint**: "Systems" insight type returns system-specific analysis with names and counts.

---

## Phase 5: User Story 3 — Detect Operational Trends (Priority: P2)

**Goal**: Admin/supervisor can generate AI-detected patterns and trends from work order and system data.

**Independent Test**: Select "Trends" insight type, verify the response identifies week-over-week changes, recurring issues, and department hotspots.

### Implementation for User Story 3

- [ ] T012 [US3] Implement `_build_trends_prompt(wo_stats: dict, sys_stats: dict, language: str) -> str` in `backend/routers/ai_insights.py`. Prompt template: Start with "You are an operations trend analyst for a civil aviation maintenance department." Then "WEEKLY WORK ORDER VOLUME:" followed by weekly_volumes data (week: count). Then "RECURRING SYSTEM ISSUES (2+ in period):" followed by systems with count >= 2 from issues_per_system. Then "DEPARTMENT WORKLOAD:" followed by by_department data. Then "RESOLUTION TIMES BY TYPE: Technical: {tech_avg}h, Inspection: {insp_avg}h, Other: {other_avg}h." End with "Write 3-5 concise bullet points about trends, patterns, or concerns. Flag anything getting worse. No preamble." If `language == "ar"`, append "Respond entirely in Arabic."
- [ ] T013 [US3] Add `insight_type == "trends"` branch to the main endpoint in `backend/routers/ai_insights.py`. Add `elif request.insight_type == "trends":` branch that calls `_build_trends_prompt(wo_stats, sys_stats, request.language)`. For `data_summary`, include `weekly_trend` (percentage change between last two weeks) and `recurring_systems` count. Compute per-type average resolution hours by filtering closed work orders by type.

**Checkpoint**: "Trends" insight type returns trend analysis with week-over-week comparisons and pattern detection.

---

## Phase 6: User Story 4 — Refresh and Customize Date Range (Priority: P3)

**Goal**: Admin/supervisor can refresh insights and change the analysis date range.

**Independent Test**: Change date range from 30 to 7 days, tap refresh, verify the insight updates with data from the shorter period.

### Implementation for User Story 4

- [ ] T014 [US4] Add date range selector to `AiInsightsCard` in `frontend/lib/features/analytics/ai_insights_card.dart`. Add state variable `_dateRangeDays` (int, default 30). Add a `DropdownButton<int>` or row of `ChoiceChip` widgets with options: 7, 14, 30, 90 days. Pass `_dateRangeDays` to the service call in `_generateInsight()`. When date range changes, auto-trigger regeneration (same pattern as type/language change). Style the selector to match existing chips using `AppColors.bgSurface2` for unselected and `AppColors.accent` for selected.

**Checkpoint**: User can select 7/14/30/90 day ranges and the insight regenerates accordingly.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T015 Verify all three insight types generate coherent bullet points by testing with curl against each insight_type (overview, system_status, trends) with both `language: "en"` and `language: "ar"` — 6 total requests
- [ ] T016 [P] Verify role guard by testing endpoint with `user_role=reporter` and `user_role=technician` — both should return 403
- [ ] T017 [P] Verify insufficient data guard by testing with `date_range_days=1` when no recent work orders exist — should return 422 with helpful message
- [ ] T018 Run quickstart.md validation — execute all 5 test scenarios from `specs/021-ai-analytics-insights/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on T001 (router file exists) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 (aggregation functions exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (endpoint structure exists, just adding a branch)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (endpoint structure exists, just adding a branch)
- **User Story 4 (Phase 6)**: Depends on Phase 3 (frontend card exists)
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) — creates the endpoint and frontend card
- **User Story 2 (P2)**: Depends on US1 (adds branch to existing endpoint) — can start after T007 is complete
- **User Story 3 (P2)**: Depends on US1 (adds branch to existing endpoint) — can start after T007 is complete. Can run in parallel with US2.
- **User Story 4 (P3)**: Depends on US1 (adds control to existing card) — can start after T008 is complete

### Within Each User Story

- Prompt function before endpoint branch
- Backend before frontend integration
- Core implementation before polish

### Parallel Opportunities

- T003 (frontend service) can run in parallel with T001/T002 (backend setup)
- T004 and T005 (aggregation functions) can run in parallel
- US2 (T010-T011) and US3 (T012-T013) can run in parallel after US1 endpoint is complete
- T015, T016, T017 (verification tasks) can run in parallel

---

## Parallel Example: User Story 1

```bash
# After Phase 2 is complete, launch prompt + frontend in parallel:
Task: T006 "Implement _build_overview_prompt in backend/routers/ai_insights.py"
Task: T008 "Create AiInsightsCard widget in frontend/lib/features/analytics/ai_insights_card.dart"

# Then sequentially:
Task: T007 "Implement POST /api/ai/insights endpoint" (depends on T006)
Task: T009 "Integrate AiInsightsCard into dashboard_screen.dart" (depends on T008)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T005)
3. Complete Phase 3: User Story 1 (T006-T009)
4. **STOP and VALIDATE**: Test "Overview" insight end-to-end
5. Deploy/demo if ready — admins can already get AI operational summaries

### Incremental Delivery

1. Setup + Foundational → Backend router and aggregation ready
2. Add User Story 1 → Overview insight works end-to-end (MVP!)
3. Add User Story 2 → System status analysis available
4. Add User Story 3 → Trend detection available
5. Add User Story 4 → Date range customization
6. Each story adds a new insight type without breaking previous ones

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No new database tables — all tasks read from existing Supabase tables
- Reference files (ai_assist.py, system_status.py, ai_assist_service.dart) should be read but not modified
- Activity logging (constitution VI) is included in T007 via `log_activity()`
- Arabic RTL rendering uses TextDirection.rtl in the frontend card (T008)
- Commit after each task or logical group
