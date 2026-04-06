# Quickstart: Natural Language Search for Work Orders

**Feature**: 023-nl-search-work-orders  
**Date**: 2026-04-06

## Prerequisites

- Ollama running on `localhost:11434` with `gemma4:e2b` model loaded
- Backend FastAPI server running
- Flutter web app running
- Supabase database with existing work_orders, departments, users tables populated

## Implementation Order

### Step 1: Backend — NL Search Endpoint

**File**: `backend/routers/ai_search.py` (NEW)

Create a new router following the pattern in `ai_assist.py`:
1. Define `NLSearchRequest` Pydantic model (query, email, user_role, limit, offset)
2. Build an Ollama prompt that includes valid statuses, types, and department names
3. Call Ollama with 5-second timeout via httpx
4. Parse JSON response into extracted filters
5. Validate filters against known enums/departments
6. Query work_orders table with validated filters
7. Apply role-based filtering (same logic as GET /api/work-orders)
8. On any AI failure: fall back to keyword search (ILIKE on job_no, title, description)
9. Log activity via `log_activity()`
10. Return results with filters and fallback flag

**Register router** in `backend/main.py`:
```python
from routers.ai_search import router as ai_search_router
app.include_router(ai_search_router, prefix="/api")
```

### Step 2: Frontend — Search Service

**File**: `frontend/lib/services/ai_search_service.dart` (NEW)

Create service following `ai_assist_service.dart` pattern:
1. `searchWorkOrders(query, email, userRole, {limit, offset})` method
2. POST to `${AppConfig.baseUrl}/search/nl`
3. Parse response into model with work_orders, total, filters, fallback flag
4. Handle timeout (65s client-side to account for 5s backend + network)

### Step 3: Frontend — Search Result Model

**File**: `frontend/lib/models/nl_search_result.dart` (NEW)

Define:
- `NLSearchResult` with fields: workOrders, total, filters, fallback
- `ExtractedFilters` with fields: status, type, department, location, dateFrom, dateTo, minResolutionDays

### Step 4: Frontend — Integrate NL Search into Work Order Home

**File**: `frontend/lib/screens/Work_Orders/work_order_home.dart` (MODIFY)

1. Change search bar submit behavior: on Enter/button, call `AiSearchService.searchWorkOrders()`
2. While loading: show progress indicator in search bar area
3. On success (fallback=false): populate list with results, show filter chips, hide manual filters
4. On fallback: populate list with results, show fallback notice, keep manual filters visible
5. On clear: restore manual filters and original work order list

### Step 5: Frontend — Filter Chips for Extracted Filters

**File**: `frontend/lib/screens/Work_Orders/work_order_home.dart` (MODIFY)

1. When NL search returns filters, render removable chips (e.g., "Status: Closed", "Dept: Plumbing")
2. On chip removal: re-query backend with remaining filters (reuse the search endpoint with explicit filters)
3. On "Clear all": exit NL search mode, restore manual filters

## Testing Checklist

- [ ] Type "closed technical orders this week" → verify only Closed + Technical + this week results
- [ ] Type "plumbing issues from last month" → verify department and date filtering
- [ ] Stop Ollama → type any query → verify keyword fallback with notice
- [ ] Type query → verify filter chips appear → remove one chip → verify results update
- [ ] Log in as technician → type "all pending orders" → verify only department-scoped results
- [ ] Log in as reporter → type "my orders" → verify only own orders shown
- [ ] Type query in Arabic → verify filters extracted correctly
- [ ] Clear NL search → verify manual filters restored
