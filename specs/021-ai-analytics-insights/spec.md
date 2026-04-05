# Feature Specification: AI-Powered Analytics & Insights

**Feature Branch**: `021-ai-analytics-insights`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "AI-powered analytics and insights feature for the work order app. Using the existing Ollama + Gemma4:e2b AI infrastructure, add a new endpoint and dashboard widget that generates natural language summaries and trend analysis. The backend aggregates work order statistics and system status data, then feeds compact prompts to the local LLM. Three insight types: overview, system_status, and trends. The AI insights card appears on the admin/supervisor dashboard with a type selector, loading state, and refresh button. Role-gated to admin/supervisor only."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Operational Overview (Priority: P1)

As an admin or supervisor, I want to see a concise AI-generated summary of the current operational health so I can quickly understand the state of work orders and system status without manually reviewing multiple screens.

**Why this priority**: This is the core value proposition — turning raw data into actionable intelligence. An executive summary is the most broadly useful insight type and provides immediate value to decision-makers.

**Independent Test**: Can be fully tested by logging in as an admin, navigating to the dashboard, and requesting an "Overview" insight. Delivers a natural language summary covering work order distribution, system health snapshot, and average resolution times.

**Acceptance Scenarios**:

1. **Given** an admin is on the dashboard and there are work orders and system status data in the system, **When** they request an "Overview" insight, **Then** the system displays a natural language summary of operational health including work order counts by status, busiest departments, and current system health.
2. **Given** an admin requests an overview insight, **When** the AI service is processing, **Then** a loading indicator is shown and the user cannot trigger duplicate requests.
3. **Given** there are fewer than 5 work orders in the selected time range, **When** an insight is requested, **Then** the system displays a helpful message indicating insufficient data rather than generating a low-quality summary.

---

### User Story 2 - Analyze System Status Health (Priority: P2)

As an admin or supervisor, I want to see an AI-generated analysis of system reliability so I can identify which systems need attention and which are performing well.

**Why this priority**: System uptime is critical for civil aviation operations. A focused analysis of system health patterns helps prioritize maintenance efforts and resource allocation.

**Independent Test**: Can be fully tested by requesting a "System Status" insight. Delivers analysis identifying problematic systems, unresolved issues, and systems with clean track records.

**Acceptance Scenarios**:

1. **Given** an admin requests a "System Status" insight, **When** system status data exists for the selected period, **Then** the system displays an analysis identifying which systems have the most issues, currently unresolved problems, and systems with zero issues.
2. **Given** multiple systems have recurring issues in the selected period, **When** the insight is generated, **Then** the analysis highlights these repeat-offender systems by name with issue counts.

---

### User Story 3 - Detect Operational Trends (Priority: P2)

As an admin or supervisor, I want to see AI-detected patterns and trends in work order and system data so I can proactively address worsening situations before they become critical.

**Why this priority**: Trend detection enables proactive management rather than reactive firefighting. Equal priority to system status as both serve different aspects of operational intelligence.

**Independent Test**: Can be fully tested by requesting a "Trends" insight. Delivers pattern analysis covering week-over-week volume changes, recurring issues, and department workload distribution.

**Acceptance Scenarios**:

1. **Given** an admin requests a "Trends" insight with a 30-day range, **When** sufficient data exists, **Then** the system displays identified patterns such as volume trends, recurring issues, and department hotspots.
2. **Given** work order volume has increased week-over-week, **When** the trends insight is generated, **Then** the analysis flags the increasing trend and identifies contributing factors.

---

### User Story 4 - Refresh and Customize Date Range (Priority: P3)

As an admin or supervisor, I want to refresh insights on demand and adjust the analysis time range so I can get up-to-date information and compare different periods.

**Why this priority**: Provides flexibility in how insights are consumed. Lower priority because the default 30-day range covers most use cases.

**Independent Test**: Can be tested by changing the date range selector and clicking refresh, verifying the insight updates with data from the new period.

**Acceptance Scenarios**:

1. **Given** an admin is viewing an existing insight, **When** they tap the refresh button, **Then** a new insight is generated with the latest data, replacing the previous one.
2. **Given** an admin changes the date range from 30 days to 7 days, **When** the insight regenerates, **Then** the analysis reflects only the selected time period.

---

### Edge Cases

- What happens when the AI service is unavailable? The system displays a clear error message indicating the AI service is temporarily unavailable and suggests trying again later.
- What happens when there is no data at all (fresh deployment)? The system shows a friendly empty-state message instead of calling the AI.
- What happens if the AI response is incoherent or empty after processing? An error message is shown asking the user to try again.
- What happens when a non-admin user tries to access insights? The insights card is not visible to non-admin/non-supervisor users, and the backend rejects unauthorized requests with a 403 status.
- What happens if the request times out? The system shows a timeout message and allows the user to retry.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST aggregate work order statistics (counts by status, type, and department; average resolution time; weekly volumes; top locations) for a configurable date range.
- **FR-002**: System MUST aggregate system status data (current unresolved issues, per-system issue counts, average resolution time, most and least problematic systems) for a configurable date range.
- **FR-003**: System MUST generate natural language insights as 3-5 concise bullet points using the existing local AI model for three insight types: "overview", "system_status", and "trends".
- **FR-004**: System MUST restrict insight generation to users with admin or supervisor roles only.
- **FR-005**: System MUST display the AI insights as a card widget on the dashboard, visible only to admin and supervisor users.
- **FR-006**: System MUST provide a selector for choosing insight type (Overview, System Status, Trends).
- **FR-007**: System MUST show a loading indicator while insights are being generated and prevent duplicate simultaneous requests.
- **FR-008**: System MUST provide a refresh button to regenerate insights on demand.
- **FR-009**: System MUST handle insufficient data gracefully by showing a helpful message when fewer than 5 work orders exist in the selected range.
- **FR-010**: System MUST handle AI service unavailability with clear user-facing error messages.
- **FR-011**: System MUST display a timestamp showing when the insight was last generated.
- **FR-012**: System MUST support a configurable date range for analysis (default: 30 days).
- **FR-013**: System MUST provide a language toggle (English / Arabic) on the insights card, and generate insights in the selected language.
- **FR-014**: When Arabic is selected, the insight text MUST render with right-to-left (RTL) text direction.

### Key Entities

- **Insight Request**: Represents a request for AI analysis — includes insight type (overview/system_status/trends), date range, and preferred language (English or Arabic).
- **Insight Response**: Contains the generated insight as 3-5 bullet points, generation timestamp, and a summary of the aggregated data used.
- **Work Order Statistics**: Aggregated counts and metrics derived from work order data over a date range.
- **System Status Statistics**: Aggregated reliability metrics derived from system status reports over a date range.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admin and supervisor users can generate an operational insight in under 90 seconds from button press to displayed result.
- **SC-002**: Generated insights accurately reference actual system names, department names, and numeric counts from the underlying data.
- **SC-003**: The insights card loads without blocking the initial dashboard rendering — the dashboard remains interactive while insights are generated.
- **SC-004**: 100% of unauthorized access attempts (non-admin/non-supervisor users) are rejected before any data aggregation occurs.
- **SC-005**: Users can successfully switch between all three insight types and receive distinct, relevant analysis for each.
- **SC-007**: Users can toggle between English and Arabic, and the generated insights are rendered in the selected language with correct text direction.
- **SC-006**: Error states (AI unavailable, timeout, insufficient data) display clear, actionable messages — no raw error codes or stack traces are shown to the user.

## Clarifications

### Session 2026-04-05

- Q: What format should generated insights use? → A: Bullet points (3-5 concise bullets per insight).
- Q: What language should insights be generated in? → A: User-selectable (English or Arabic toggle on the insights card).

## Assumptions

- The existing Ollama + Gemma4:e2b AI model infrastructure is already deployed and operational (same setup as the AI work order description feature).
- The local AI model can produce coherent analytical summaries from structured statistical data provided in the prompt.
- Work order and system status data already exist in the database in sufficient volume for meaningful analysis (the feature degrades gracefully for sparse data).
- The existing dashboard screen is the primary landing page for admin/supervisor users and is the appropriate location for the insights widget.
- The default 30-day analysis window is sufficient for most operational insights; customization is a secondary concern.
- No data caching is needed for V1 — each insight request generates fresh analysis from current data.
- The preamble-stripping approach already used in the AI description feature is sufficient for cleaning insight responses.
