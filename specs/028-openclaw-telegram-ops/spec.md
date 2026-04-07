# Feature Specification: OpenClaw Telegram Ops Assistant

**Feature Branch**: `028-openclaw-telegram-ops`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "Install and configure OpenClaw on the existing Zorin OS Linux server to act as an AI-powered ops assistant for the Work Order Management System, accessible via Telegram bot, backed by local Ollama/Gemma, wrapping existing FastAPI endpoints via skills."

## Clarifications

### Session 2026-04-07

- Q: How is an "overdue" work order defined? → A: Any work order in Open or Pending state for more than 48 hours without a status change (same threshold as the daily digest stale highlight).
- Q: Which timezone governs scheduled jobs (daily 7 AM, weekly Sunday 6 PM)? → A: Server local timezone of the Linux host.
- Q: How long does a pending destructive-action confirmation remain valid? → A: 60 seconds; after that, the assistant must require the destructive command to be reissued.
- Q: How are admin commands audited? → A: Append-only local log file on the server recording every admin command, timestamp, and outcome.
- Q: How often does the push-failure fallback check run? → A: Every hour, checking the previous hour's failed deliveries.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Query Work Orders from Telegram (Priority: P1)

The admin opens Telegram on their phone and asks the ops bot natural-language questions about work orders (e.g., "show open work orders", "how many pending?", "what did we close this week?"). The bot replies with accurate, current data drawn from the live Work Order Management System, without the admin needing to open the web/PWA app.

**Why this priority**: This is the primary value proposition — giving the admin instant situational awareness from anywhere via a channel they already use. It is also the smallest self-contained slice that proves the entire stack (Telegram → bot → AI → skill → backend API → response) works end-to-end.

**Independent Test**: Admin sends "show open work orders" from Telegram and receives a formatted list matching what the dashboard shows in the PWA. Deliverable on its own as an MVP even if no other skills exist.

**Acceptance Scenarios**:

1. **Given** the bot is running and the admin is authorized, **When** the admin sends "show open work orders", **Then** the bot returns a list of currently open work orders with their job numbers and titles within a few seconds.
2. **Given** there are pending work orders, **When** the admin asks "how many pending work orders?", **Then** the bot replies with an accurate count.
3. **Given** a specific work order exists, **When** the admin sends "close work order #1234", **Then** the work order's status is updated to Closed and the bot confirms the change.
4. **Given** a user who is NOT the admin messages the bot, **When** they send any command, **Then** the bot ignores or rejects the request and does not expose data.

---

### User Story 2 - Automated Daily Digest (Priority: P2)

Each morning at 7:00 AM local time, the admin automatically receives a Telegram message summarizing the operational state of the Work Order system: counts of open, pending, and overdue work orders, plus a highlighted alert for any work order that has been open for more than 48 hours without a status change. A weekly summary arrives Sunday at 6:00 PM.

**Why this priority**: Proactive visibility without requiring the admin to ask. Builds a habit loop and surfaces issues that would otherwise be missed. Depends on Story 1's plumbing but adds no new user interface.

**Independent Test**: Wait until 7:00 AM (or manually trigger the scheduled job) and verify a summary message arrives on Telegram with counts that match the live system.

**Acceptance Scenarios**:

1. **Given** the scheduler is running, **When** the clock reaches 7:00 AM, **Then** the admin receives a Telegram message with current open/pending/overdue counts.
2. **Given** a work order has been in "Open" state for more than 48 hours, **When** the daily digest runs, **Then** it is highlighted in the digest as stale.
3. **Given** the clock reaches Sunday 6:00 PM, **When** the weekly job runs, **Then** the admin receives a richer summary broken down by status.

---

### User Story 3 - Server Health Checks from Telegram (Priority: P2)

The admin can ask the bot about the server's operational health — "server status", "disk usage", "last errors" — and receive accurate answers without SSH'ing into the box. For destructive actions like restarting the backend service, the bot requires an explicit confirmation reply before executing.

**Why this priority**: Gives the admin a recovery channel when something is wrong and they're away from a workstation. Independent of the work-order skill and valuable on its own.

**Independent Test**: Admin sends "server status" and receives current reverse-proxy and backend service health plus disk usage. Sending "restart backend" triggers a confirmation prompt and only restarts after the admin confirms.

**Acceptance Scenarios**:

1. **Given** both the reverse proxy and backend service are running, **When** the admin asks for server status, **Then** the bot reports both as healthy with current disk usage.
2. **Given** the admin requests a backend restart, **When** the bot receives the request, **Then** it replies with a confirmation prompt and only proceeds after the admin explicitly confirms.
3. **Given** the admin asks for recent errors, **When** the bot runs, **Then** it returns the most recent error log entries from the backend.

---

### User Story 4 - Email Work Order PDFs via Chat (Priority: P3)

The admin can tell the bot to email a work order PDF to a specific recipient (e.g., "Send work order #42 PDF to director@example.com") or to send a weekly summary report via email, and the bot uses the existing email infrastructure to deliver it.

**Why this priority**: A convenience add-on. Not required for core ops visibility but saves steps when dispatching documents from the field.

**Independent Test**: Admin sends a command to email a specific work order PDF to an address, and the recipient receives a correctly rendered PDF.

**Acceptance Scenarios**:

1. **Given** work order #42 exists, **When** the admin says "Send work order #42 PDF to director@example.com", **Then** the recipient receives an email containing the correct work order PDF and the bot confirms delivery.
2. **Given** the admin requests a weekly summary by email, **When** the command runs, **Then** a summary report is emailed to the admin.

---

### User Story 5 - Delivery Failure Fallback (Priority: P3)

When push notifications to the mobile app fail to deliver, the admin is alerted via Telegram instead, so critical notifications are never lost.

**Why this priority**: Safety net — valuable only when the primary notification channel degrades. Layered on top of earlier stories.

**Independent Test**: Simulate a failed push delivery and verify a Telegram fallback message arrives for the admin within the heartbeat window.

**Acceptance Scenarios**:

1. **Given** a push notification failed in the last hour, **When** the heartbeat check runs, **Then** the admin receives a Telegram message summarizing the failure.

---

### Edge Cases

- What happens when the local AI model is unreachable? The bot must reply with a clear error instead of hanging.
- What happens when the backend API is down? The bot must report the failure rather than returning stale or empty results.
- What happens when a non-admin user messages the bot? The bot must ignore or reject the request and must not leak data or command surface area.
- What happens when a referenced work order does not exist? The bot responds with a clear "not found" message.
- What happens when the server reboots? The assistant must restart automatically without manual intervention.
- What happens when the bot receives an ambiguous command (e.g., "close it")? It should ask for clarification rather than act.
- What happens when destructive commands (e.g., restart backend) are issued? They must require explicit confirmation before execution.
- What happens when a scheduled digest misses its window (server offline at 7 AM)? The missed run is skipped and the next scheduled run proceeds normally.

## Requirements *(mandatory)*

### Functional Requirements

**Access & Security**

- **FR-001**: The assistant MUST only respond to messages from the pre-authorized admin identity; all other senders MUST be ignored.
- **FR-002**: The assistant MUST NOT be reachable from the public internet; it MUST only be accessible over the existing private network.
- **FR-003**: All interactions with Work Order data MUST go through the existing backend API — direct database access is prohibited.
- **FR-004**: Destructive operations (e.g., restarting services, closing work orders) MUST require an explicit confirmation reply before execution. A pending confirmation MUST expire after 60 seconds, after which the destructive command must be reissued from scratch.

**Core Assistant**

- **FR-005**: The assistant MUST run as a managed background service that starts automatically on server boot and restarts automatically on failure.
- **FR-006**: The assistant MUST use the locally hosted AI model as its language backend — no cloud AI calls.
- **FR-007**: The assistant MUST expose a chat interface through the messaging platform (Telegram) for the admin.
- **FR-008**: The assistant MUST respond to each admin message with either a useful answer, a clarification question, or a clear error.

**Work Orders Skill**

- **FR-009**: The assistant MUST allow the admin to list work orders filtered by status (open, pending, closed, overdue), where "overdue" means a work order that has remained in Open or Pending state for more than 48 hours without a status change.
- **FR-010**: The assistant MUST allow the admin to look up a specific work order by its job number.
- **FR-011**: The assistant MUST allow the admin to change a work order's status (including closing it) via chat.
- **FR-012**: The assistant MUST allow the admin to request summary counts (e.g., how many pending, how many closed this week).
- **FR-013**: The assistant MUST answer natural-language questions about recent completed work over a user-specified time window.

**Server Management Skill**

- **FR-014**: The assistant MUST report the health of the reverse proxy and the backend service on demand.
- **FR-015**: The assistant MUST report current disk usage on demand.
- **FR-016**: The assistant MUST return the most recent error log entries on demand.
- **FR-017**: The assistant MUST support restarting the backend service, gated by explicit confirmation.

**Email Skill**

- **FR-018**: The assistant MUST allow the admin to request that a specific work order's PDF be emailed to a named recipient, using the existing email delivery capability.
- **FR-019**: The assistant MUST allow the admin to request a weekly summary report by email.

**Scheduled Automations**

- **FR-020**: The assistant MUST send a daily digest to the admin at 7:00 AM in the server's local timezone containing counts of open, pending, and overdue work orders.
- **FR-021**: The daily digest MUST highlight any work order that has been in an open state for more than 48 hours without a status change.
- **FR-022**: The assistant MUST send a weekly summary to the admin on Sunday at 6:00 PM in the server's local timezone broken down by work order status.

**Notification Fallback (optional slice)**

- **FR-023**: The assistant SHOULD run a push-failure check once per hour that inspects push notifications from the previous hour and, when any failed delivery is detected, send the admin a chat message summarizing the failure(s).

**Non-Modification Constraint**

- **FR-024**: The integration MUST NOT modify existing backend routes or existing frontend code; it MUST be purely additive.

**Audit**

- **FR-025**: The assistant MUST write every received admin command, the resolved action, and its outcome (success/failure/confirmation-required/expired) to an append-only local audit log file on the server, with a timestamp for each entry.

### Key Entities

- **Admin Identity**: The single authorized operator. Identified by a messaging-platform user ID and an admin email used as the caller identity when invoking backend operations.
- **Skill**: A named, self-contained capability the assistant can invoke (e.g., work orders, server, email, heartbeat). Each skill has a description of when to use it and an executable that performs the action.
- **Scheduled Job**: A recurring automation (daily digest, weekly summary, delivery-failure watchdog) with a time/frequency and a target output channel.
- **Conversation Session**: The stream of messages between the admin and the assistant, used to hold short-term context such as pending confirmations for destructive actions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a cold server reboot, the assistant is available to answer admin messages within 2 minutes without any manual action.
- **SC-002**: 95% of natural-language work-order queries asked by the admin return an answer that matches the live system state, verified against the primary UI.
- **SC-003**: The admin can get a full operational snapshot (open / pending / overdue counts + server health) in under 30 seconds from their phone, without opening the primary app.
- **SC-004**: The 7:00 AM daily digest arrives on at least 95% of days without any manual intervention over a 30-day observation window.
- **SC-005**: Zero unauthorized users are ever able to retrieve work-order data or trigger actions via the assistant (verified by sending test messages from a non-admin account).
- **SC-006**: Destructive actions are never executed without an explicit confirmation reply from the admin (verified by audit of command history).
- **SC-007**: The assistant runs entirely on-premises; no work order content is sent to any third-party AI service.
- **SC-008**: Adding a new skill requires no changes to existing backend code.

## Assumptions

- The admin's messaging-platform user ID and email address are known at configuration time and can be hardcoded into the assistant configuration.
- The locally hosted AI model is already running and reachable on the server and will remain the sole language backend for this feature.
- The existing backend exposes all data and actions the assistant needs; no new backend endpoints will be introduced in this feature.
- The existing email delivery capability (used by the email skill) is already in place or being delivered by a parallel, already-specced feature, and this feature only consumes it.
- Only a single admin user will interact with the assistant in this iteration; per-technician chat access is explicitly out of scope and deferred to a future feature.
- The server's private network access (via the existing overlay network) is the sole channel through which the assistant will be reached — no public exposure of any kind.
- Local server time is correct and authoritative for scheduled jobs (7 AM daily, Sunday 6 PM weekly).
- Missed scheduled runs (e.g., server offline at 7 AM) are skipped rather than replayed on recovery.
- The assistant's configuration, skills, and service definition live in standard per-user locations on the server and do not need to be version-controlled inside the main application repository unless later requested.
