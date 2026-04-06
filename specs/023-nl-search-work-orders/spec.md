# Feature Specification: Natural Language Search for Work Orders

**Feature Branch**: `023-nl-search-work-orders`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Smart natural language search for work orders. Admins and supervisors can type queries like 'show me all plumbing issues from last month that took over 3 days' or 'closed technical orders in AFTN this week' into a search bar and get filtered results. The backend parses the natural language query using the existing Ollama AI infrastructure (same as features 020 and 021) to extract structured filters (status, type, department, location, date range, resolution time), then queries the work_orders table with those filters and returns matching results. The search bar appears on the work orders list screen. Falls back to normal keyword search if AI parsing fails."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Natural Language Query Returns Filtered Results (Priority: P1)

An admin or supervisor opens the work orders list screen and types a natural language query such as "show me all plumbing issues from last month" into the search bar. The system sends the query to the backend, which uses the AI service to extract structured filters (e.g., department = "Plumbing", date range = last 30 days). The backend then queries the work_orders table with those filters and returns matching results. The user sees a filtered list of work orders that match their intent.

**Why this priority**: This is the core value proposition of the feature. Without natural language query parsing and filtered result retrieval, the feature has no purpose.

**Independent Test**: Can be fully tested by typing a natural language query into the search bar and verifying that the returned work orders match the described filters. Delivers immediate value by replacing manual multi-step filtering with a single text input.

**Acceptance Scenarios**:

1. **Given** an admin is on the work orders list screen, **When** they type "closed technical orders this week" and submit, **Then** they see only work orders with status "Closed", type "Technical", and created within the current week.
2. **Given** a supervisor is on the work orders list screen, **When** they type "plumbing issues from last month that took over 3 days", **Then** they see only work orders related to the Plumbing department, created in the previous calendar month, with a resolution time exceeding 3 days.
3. **Given** an admin types "pending inspection orders in AFTN", **When** results are returned, **Then** only work orders with status "Pending", type "Inspection", and location containing "AFTN" are displayed.

---

### User Story 2 - Graceful Fallback to Keyword Search (Priority: P2)

When the AI service is unavailable (e.g., Ollama is offline) or fails to parse the query into structured filters, the system automatically falls back to the existing keyword-based search behavior. The user sees results matching their query text against job number, title, and description fields. A subtle indicator informs the user that AI-powered search was unavailable and keyword search was used instead.

**Why this priority**: Reliability is critical. Users must always get some results even when the AI service is down. Without fallback, the search bar becomes broken during AI outages.

**Independent Test**: Can be tested by disabling the AI service and typing a query, then verifying that keyword-based results are returned and a fallback notice is shown.

**Acceptance Scenarios**:

1. **Given** the AI service is unavailable, **When** a user types "plumbing issues" into the search bar, **Then** the system performs a keyword search against job number, title, and description, returns matching results, and shows a notice indicating keyword search was used.
2. **Given** the AI service returns an unparseable or empty response, **When** the user submits a query, **Then** the system falls back to keyword search seamlessly without displaying an error.
3. **Given** the AI successfully parses the query but returns zero structured filters, **When** the user submits a query, **Then** the system treats the input as a keyword search.

---

### User Story 3 - Visual Feedback for Active AI Filters (Priority: P3)

After a successful natural language query, the user sees visual indicators (filter chips or tags) showing which filters the AI extracted from their query (e.g., "Status: Closed", "Department: Plumbing", "Date: March 2026"). The user can remove individual filter chips to broaden results, or clear all filters to return to the full list.

**Why this priority**: Transparency builds trust in the AI. Users need to understand and verify what the AI interpreted from their query, and easily adjust if the interpretation was wrong.

**Independent Test**: Can be tested by submitting a natural language query and verifying that extracted filter chips appear, are accurate, and can be individually removed to update results.

**Acceptance Scenarios**:

1. **Given** the AI parses "closed orders from last week" into status=Closed and date range=last 7 days, **When** results are displayed, **Then** filter chips for "Status: Closed" and "Date: [last week range]" are visible above the results.
2. **Given** filter chips are displayed after an AI query, **When** the user removes the "Status: Closed" chip, **Then** the results update to show all orders from last week regardless of status.
3. **Given** filter chips are displayed, **When** the user taps "Clear all", **Then** all AI-extracted filters are removed and the full unfiltered list is restored.

---

### User Story 4 - Role-Based Result Scoping (Priority: P3)

Natural language search respects existing role-based access controls. A technician using natural language search only sees work orders within their assigned department. A reporter only sees work orders they created. Admins and supervisors see all matching work orders.

**Why this priority**: Security and data access rules must be preserved regardless of search method. This is non-negotiable but ranks lower because the existing role-based filtering infrastructure already handles this.

**Independent Test**: Can be tested by having users with different roles submit the same natural language query and verifying each user only sees work orders they are authorized to access.

**Acceptance Scenarios**:

1. **Given** a technician assigned to the Electrical department types "all pending orders", **When** results are returned, **Then** only pending work orders in the Electrical department are shown.
2. **Given** a reporter types "my orders from this month", **When** results are returned, **Then** only work orders created by that reporter in the current month are shown.
3. **Given** an admin types "all pending orders", **When** results are returned, **Then** pending work orders across all departments are shown.

---

### Edge Cases

- What happens when the user types a very short or ambiguous query (e.g., "orders")?  
  The system treats it as a keyword search since there are no meaningful filters to extract.

- What happens when the AI extracts a department name that doesn't match any existing department?  
  The filter for that field is ignored, and remaining valid filters are still applied. The result set may be broader than expected.

- What happens when the user types a query in Arabic?  
  The AI prompt supports Arabic input (consistent with feature 021's language support). The AI extracts filters from Arabic text the same way it does from English.

- What happens when no results match the extracted filters?  
  An empty state message is displayed, such as "No work orders match your search." The extracted filter chips remain visible so the user can adjust.

- What happens when the user rapidly submits multiple queries?  
  Only the most recent query's results are displayed. Previous in-flight requests are cancelled or their results are discarded.

- What happens when the query mentions a time period like "last month" or "this week"?  
  The backend resolves relative date expressions to absolute date ranges based on the current server date at the time of the request.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a search input on the work orders list screen where users can type natural language queries and submit via Enter key or a search button (no auto-search on typing pause).
- **FR-002**: System MUST send the natural language query to the backend for AI-powered parsing into structured filters.
- **FR-003**: System MUST extract the following filter types from natural language queries: status, work order type, department, location, date range, and resolution time.
- **FR-004**: System MUST query the work_orders table using the extracted structured filters and return matching results with existing pagination behavior (infinite scroll, 30 items per page).
- **FR-005**: System MUST fall back to keyword-based search (matching against job number, title, and description) when the AI service is unavailable, fails to parse the query, or does not respond within 5 seconds.
- **FR-006**: System MUST display a subtle indicator when keyword fallback search is used instead of AI-powered search.
- **FR-007**: System MUST display extracted filters as removable visual indicators (chips/tags) after a successful AI-parsed query.
- **FR-008**: System MUST allow users to remove individual extracted filters to broaden search results by re-querying the backend with remaining filters.
- **FR-015**: System MUST hide existing manual filter controls (status chips, date picker, employee filter) while an NL search is active, and restore them when the user clears the NL search.
- **FR-009**: System MUST enforce existing role-based access controls on all search results (technicians see only their department, reporters see only their created orders, admins/supervisors see all).
- **FR-010**: System MUST resolve relative date expressions (e.g., "last month", "this week") to absolute date ranges on the server side.
- **FR-011**: System MUST support natural language queries in both English and Arabic.
- **FR-012**: System MUST cancel or discard results from previous in-flight queries when a new query is submitted.
- **FR-013**: System MUST display an appropriate empty state message when no work orders match the extracted filters.
- **FR-014**: All user roles (including technicians and reporters) MUST be able to use the natural language search bar, with results scoped to their access level.

### Key Entities

- **Search Query**: The natural language text input from the user, submitted for AI parsing.
- **Extracted Filters**: Structured filter set derived from the natural language query, consisting of: status, type, department, location, date range (start/end), and resolution time threshold.
- **Search Result**: A list of work orders matching the extracted filters (or keyword match in fallback mode), scoped by the user's role-based access.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can find specific work orders using natural language in under 10 seconds, compared to the current multi-step manual filtering process.
- **SC-002**: The AI correctly extracts at least one meaningful filter from 90% of well-formed natural language queries.
- **SC-003**: When the AI service is unavailable, keyword fallback returns results within 2 seconds with no user-visible errors.
- **SC-004**: Search results respect role-based access controls with 100% accuracy — no user ever sees a work order they are not authorized to view.
- **SC-005**: Users can understand which filters were applied by viewing the displayed filter indicators, reducing repeated or confused searches.
- **SC-006**: The feature supports queries in both English and Arabic with equivalent accuracy.

## Clarifications

### Session 2026-04-06

- Q: How does the user trigger the natural language search? → A: User presses Enter or taps a search button to submit (no auto-search on typing pause).
- Q: How does NL search coexist with existing manual filters (status chips, date picker, employee filter)? → A: NL search replaces manual filters while active; clearing NL search restores manual filter controls.
- Q: How long should the system wait for AI parsing before falling back to keyword search? → A: 5 seconds. After 5 seconds without an AI response, the system falls back to keyword search.
- Q: Should NL search results use existing pagination (infinite scroll, 30/page) or return all at once? → A: Preserve existing infinite scroll pagination (30 items per page).
- Q: When a user removes an AI-extracted filter chip, should the system re-query the backend or filter client-side? → A: Re-query the backend with remaining filters (ensures accuracy and correct pagination).

## Assumptions

- The existing Ollama AI infrastructure (used by features 020 and 021) is available and will be reused for query parsing. No new AI service deployment is required.
- The current work_orders table schema already contains all fields needed for filtering (status, type, department_id, location, created_at, closed_at). No schema changes are required.
- Relative date expressions are resolved based on the server's current date/time, not the client's.
- "Resolution time" is calculated as the difference between created_at and closed_at timestamps.
- The existing role-based access control logic (admin sees all, technician sees department, reporter sees own orders) will be reused and applied to search results.
- Department matching from natural language uses fuzzy/partial matching against department names in the database (e.g., "plumbing" matches "Plumbing Department").
- The search bar replaces or enhances the existing search input on the work orders list screen rather than adding a second search bar.
- AI query parsing adds a network round-trip; users accept a brief loading state while the AI processes their query.
