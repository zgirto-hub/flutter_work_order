# Feature Specification: iOS PWA Native Share for Letters & Work Order PDFs

**Feature Branch**: `038-ios-pwa-share`
**Created**: 2026-04-11
**Status**: Draft
**Input**: User description: "Add Web Share API support for iOS/PWA PDF sharing to Letters V2 and Work Order exports. Currently 'Open in new tab' button breaks iOS PWA session by kicking to Safari. Need to detect iOS standalone PWA mode and show native Share button instead, using navigator.share() with PDF files for AirDrop/Mail/Print. Apply to LetterHtmlViewerScreen and Work Order PDF export flow. Keep existing desktop 'Open in new tab' behavior."

## Clarifications

### Session 2026-04-11

- Q: On desktop Chrome/Edge that *do* support sharing files via the Web Share API, should the user see the native share sheet or the existing "Open in new tab" control? → A: Keep "Open in new tab" on all desktops regardless of browser capability — the control selector is gated on form factor (mobile/touch), not on raw `canShare({files})` support.
- Q: When native file sharing is unavailable on a mobile platform (e.g., old iOS, `canShare({files})` returns false), which fallback should the user see? → A: Auto-download the PDF to the device's Files/Downloads location and show a brief "Saved to Files" confirmation — no share sheet, no navigation, no fallback to "Open in new tab".
- Q: Where should the iOS share control live for the work order PDF export, and how should it coexist with the `printing` package's built-in `PdfPreview` toolbar? → A: Add the share control to the **AppBar** of `PdfPreviewScreen` on mobile only, and hide the `printing` package's built-in toolbar actions (download/print/share) on mobile so there is exactly one share affordance. The `PdfPreview` viewer body itself (scroll, zoom, paginate) stays unchanged. Desktop keeps the full `printing` toolbar as today.
- Q: Is Android PWA support a release-blocking requirement for this feature? → A: Smoke-tested but not release-blocking. Android PWA is expected to work (it naturally benefits from the same mobile form-factor gate), and a basic smoke test runs before release, but only iOS failures block shipping. Android issues become follow-up tickets.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Share a generated letter from iPhone PWA without losing the session (Priority: P1)

An admin or clerk using the installed Home Screen PWA on iPhone/iPad opens a generated letter in the HTML viewer. They tap a share control and the native iOS share sheet appears, offering AirDrop, Mail, Messages, Save to Files, and Print — all without leaving the installed app. After the share sheet is dismissed (or an action completes), they are still inside the same PWA session with their navigation stack, auth, and any in-progress state intact.

**Why this priority**: This is the blocking issue today. The existing "Open in new tab" control force-kicks iOS PWA users into Safari, dropping their session, reloading the app from scratch, and (for some users) losing in-progress form state. Without a native share path, iOS PWA users effectively cannot print or distribute letters without disrupting their workflow. Every other story depends on this path existing.

**Independent Test**: Install the web app to the Home Screen on an iOS device, generate any letter, open the HTML viewer, tap the new share control, and confirm the native iOS share sheet appears, a PDF of the letter is offered as the shared item, and after dismissing the sheet the user remains on the letter viewer screen inside the installed PWA.

**Acceptance Scenarios**:

1. **Given** a user on an iOS device running the app as a Home Screen PWA, **When** they open a letter in the HTML viewer and tap the share control, **Then** the native iOS share sheet appears with a PDF rendition of the letter as the shared file.
2. **Given** the iOS share sheet is open with a letter PDF, **When** the user selects AirDrop, Mail, Messages, Save to Files, or Print, **Then** the chosen system action receives the PDF file (not a URL or HTML blob) and the user remains inside the PWA after the action completes or is cancelled.
3. **Given** an iOS PWA user has cancelled the share sheet, **When** they look at the screen, **Then** they are still on the letter viewer with the same navigation stack, scroll position, and auth state as before sharing.

---

### User Story 2 - Share a closed Work Order PDF report from iPhone PWA (Priority: P1)

A supervisor or admin opens a closed work order from the Work Orders list on their iPhone PWA and triggers the PDF export. The PDF preview loads, and they can share the generated PDF through the native iOS share sheet — sending to Mail, AirDrop, or the system Print dialog — without leaving the installed app.

**Why this priority**: Work Order PDF export is the second primary document-distribution flow in the product and currently relies on the same PDF preview chrome that, on iOS PWA, forces the user into Safari when they try to print or save. Fixing Letters without fixing Work Orders would leave half the document workflow broken on mobile.

**Independent Test**: On an installed iOS PWA, open a closed work order, trigger "Export PDF", wait for the PDF preview to render, tap the share control, and confirm the iOS share sheet offers the WO PDF and that AirDrop/Mail/Print all receive the file.

**Acceptance Scenarios**:

1. **Given** an iOS PWA user viewing the exported PDF of a closed work order, **When** they tap the share control, **Then** the native iOS share sheet appears with the work order PDF (filename including the WO job number) as the shared file.
2. **Given** the exported PDF is still being built (server fetch in flight), **When** the user taps the share control, **Then** they see a loading indicator and the share sheet only opens once the PDF bytes are ready, without double-triggering the share.
3. **Given** an iOS PWA user on a work order that is not in "closed" status, **When** they look at the work order actions, **Then** the share control is not offered (matching the existing rule that export is gated on closed status).

---

### User Story 3 - Desktop users keep the existing "Open in new tab" behaviour (Priority: P2)

A desktop user on Chrome, Edge, Firefox, or Safari on macOS continues to see the current "Open in new tab" control on the letter HTML viewer and the current PDF preview chrome on the work order export, because opening in a tab is the most useful behaviour there — it routes through the browser's own print/save-as-PDF dialog and keeps the tab available for reference. The share-sheet UX is only surfaced where it is actually useful (iOS / mobile PWA contexts).

**Why this priority**: We must not regress an already-working flow for the majority of users just to fix iOS. This story ensures the change is strictly additive.

**Independent Test**: Open the letter HTML viewer and a closed work order PDF export on a desktop browser and confirm the existing "Open in new tab" control is still present, still labelled the same, and still opens the letter/PDF in a new browser tab exactly as it does today.

**Acceptance Scenarios**:

1. **Given** a user on a desktop browser (any OS), **When** they open the letter HTML viewer, **Then** they see the existing "Open in new tab" control and tapping it opens the letter HTML in a new browser tab.
2. **Given** a user on a desktop browser viewing an exported work order PDF, **When** they use the toolbar controls, **Then** they still get the existing in-app PDF preview with its normal toolbar behaviour and no native share sheet is invoked.
3. **Given** an Android Chrome user on the installed PWA, **When** they view a letter or a work order PDF, **Then** they see a share control that invokes the Android system share sheet with the PDF file attached, matching the iOS behaviour. *(This is a natural consequence of the mobile form-factor gate. Android is smoke-tested before release but is not release-blocking — only iOS failures block shipping.)*

---

### Edge Cases

- **Web Share API unavailable / share-with-files unsupported**: An iOS device on an older iOS version where `navigator.share` either does not exist or cannot accept files. The system MUST fall back to **auto-downloading the PDF to the device's Files/Downloads location** with a brief "Saved to Files" confirmation. It MUST NOT silently fail, MUST NOT show message-only dead-ends, and MUST NOT fall back to the session-breaking "Open in new tab" path on iOS.
- **User cancels the share sheet**: The app treats cancellation as a no-op — no error toast, no navigation, no duplicate share prompts.
- **PDF generation fails** (server error, network loss, auth expired): The share control surfaces a clear error state to the user and does not open an empty share sheet. The existing error handling used by the PDF export and letter generation flows is reused.
- **Large PDF payloads**: A multi-page work order with many embedded signatures/logos produces a PDF several MB in size. The share flow must handle this without blocking the UI indefinitely and without exceeding any platform size limit imposed by the share sheet. *(Assumption: mobile share sheets handle typical office-document sizes; platform limits are accepted rather than imposing a lower app-side cap.)*
- **Letter has not yet been saved as PDF**: The letter viewer currently works on HTML. The share flow must produce an actual PDF file for the share sheet (not raw HTML), so that receiving apps like Mail, Print, and Save to Files treat the payload correctly.
- **Rapid re-taps**: User double-taps the share button while the PDF is still being built. Only one share sheet opens; subsequent taps are ignored until the first completes.
- **Non-PWA Safari on iOS** (user visits the site in regular Safari, not the installed Home Screen app): The iOS share control is still useful here because the Web Share API works in mobile Safari too. The detection logic should surface the share control for any iOS Safari / standalone context where file sharing is supported, not exclusively when the app is in `display-mode: standalone`. *(Assumption: we want the best iOS UX in both contexts and the cost is near zero since the same API path works.)*
- **Share sheet appears but user selects "Print"**: The PDF is sent to the iOS Print dialog, producing a faithful print output, unlike the current flow where printing from a new tab kicks the user out of the PWA.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Letters V2 HTML viewer MUST offer a share control that, when tapped on a platform supporting native file sharing, opens the native system share sheet with a PDF rendition of the letter as the shared file.
- **FR-002**: The Work Order PDF export preview MUST offer a share control in the **AppBar** of the PDF preview screen on mobile platforms that, when tapped, opens the native system share sheet with the generated work order PDF as the shared file, named with the work order job number. On mobile platforms, the built-in toolbar actions (download/print/share) of the underlying PDF preview widget MUST be hidden so that there is exactly one share affordance visible to the user. The PDF preview body itself (scroll, zoom, paginate) MUST remain unchanged on all platforms.
- **FR-003**: The system MUST choose between the native share control and the existing "Open in new tab" / desktop PDF preview toolbar using a **form-factor gate**, not a raw capability check: the native share control is offered only on mobile/touch platforms (iOS Safari, iOS installed PWA, Android Chrome/PWA), and all desktop platforms retain the existing control regardless of whether the desktop browser supports `navigator.share` with files. Users never see both controls for the same purpose at the same time.
- **FR-004**: On iOS (both installed PWA and mobile Safari), the system MUST prefer the native share control over "Open in new tab" for both letters and work order PDFs, because opening in a new tab breaks the PWA session on iOS.
- **FR-005**: On all desktop browsers (Chrome, Edge, Firefox, Safari on macOS, etc.), the system MUST retain the existing "Open in new tab" control for the letter HTML viewer and the existing PDF preview chrome for the work order export — even on desktop browsers that technically support file sharing via the Web Share API. No regression of current desktop behaviour.
- **FR-006**: Tapping the share control MUST NOT navigate the user away from the current screen, MUST NOT reload the app, and MUST NOT drop the user's auth session, regardless of whether the share sheet is confirmed or cancelled.
- **FR-007**: The share action MUST produce a real PDF file (binary attachment) for both flows, not an HTML blob or a URL, so that receiving apps (Mail, AirDrop, Messages, Print, Save to Files) treat the payload as a printable/archivable document.
- **FR-008**: The letter share flow MUST convert the currently-viewed letter HTML to PDF before invoking the share sheet, using the same rendering pipeline the application already uses to produce final letter PDFs, so that the shared file matches what users would get today via the existing "Generate PDF" action.
- **FR-009**: The work order share flow MUST use the same server-side PDF bytes produced by the existing work order export pipeline, with no second round-trip or re-rendering — the bytes the preview displays are the bytes the share sheet receives.
- **FR-010**: If the native share sheet rejects the share (e.g., user cancellation, platform file-size limit, permissions error), the system MUST distinguish cancellation (silent no-op) from actual failure (user-visible error message), and MUST leave the user on the same screen in both cases.
- **FR-011**: The share control MUST be visually consistent with the existing app toolbar controls (same icon sizing, colour, spacing) so it does not feel bolted on.
- **FR-012**: The share control MUST show a loading/disabled state while the PDF is being prepared and MUST prevent concurrent share invocations from the same button until the first one resolves.
- **FR-013**: When native file sharing is unavailable on a mobile platform where the user would otherwise expect it (e.g., old iOS version, `canShare({files})` returns false, share call throws), the system MUST fall back to **automatically downloading the PDF to the device's Files/Downloads location** and showing a brief confirmation (e.g., "Saved to Files"). The system MUST NOT show only an error message, MUST NOT open the share sheet with no content, and MUST NOT fall back to the session-breaking "Open in new tab" behaviour on iOS.
- **FR-014**: The share control MUST be offered under the same authorization and status gating as the existing export controls — e.g., the work order share control MUST only appear when the work order is in a status that currently allows PDF export (closed), and only to users who can already trigger the export today.
- **FR-015**: The shared PDF filename MUST be meaningful to the receiving app — letters MUST use a filename derived from the letter title/reference, work orders MUST use a filename derived from the work order job number — so that users can identify the file in Mail attachments, AirDrop previews, and saved Files.

### Key Entities *(include if feature involves data)*

- **Shareable Document**: A user-facing concept representing a single document the user wants to distribute (a letter or a work order report). Its attributes from the share perspective are: a human-readable title used in the share sheet, a filename used by receiving apps, and the PDF byte payload itself. It is a transient, in-memory artefact — nothing is persisted by this feature.
- **Share Capability Context**: The runtime determination of whether the current browser/device can accept a native file share, which controls whether the user sees the share control or the legacy "Open in new tab" control. This is computed at screen build time and is not persisted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An iOS PWA user can share a letter or a closed work order PDF and, after completing or cancelling the share, is still inside the installed PWA on the same screen they started from — measured by zero reports/regressions of "I got kicked to Safari when I tried to print" from iOS users after rollout.
- **SC-002**: At least the five most common share targets on iOS (AirDrop, Mail, Messages, Save to Files, Print) accept the shared PDF and produce a correct output, verified during manual device testing before release. Android PWA is smoke-tested (open share sheet → confirm a PDF is offered → share to one target) but is not release-blocking; only iOS failures block shipping.
- **SC-003**: Desktop users on Chrome, Edge, Firefox, and macOS Safari see no change in the letter HTML viewer or work order PDF export flow — confirmed by manual regression checks that "Open in new tab" still exists, is still labelled the same, and still opens the document in a new browser tab.
- **SC-004**: Sharing a letter or a work order PDF completes within 3 seconds of tapping the share control on a typical iOS device over a normal office Wi-Fi connection, for documents up to 10 pages.
- **SC-005**: When native file sharing is unavailable, users see the PDF land in their device's Files/Downloads 100% of the time, with a "Saved to Files" confirmation — never a broken share, never a silent failure, never a message-only dead-end, and never a forced Safari hand-off on iOS.
- **SC-006**: 95% of share attempts on supported platforms succeed in opening the native share sheet on first tap (no double-tap needed, no spinner that never resolves), measured across the manual device test matrix.

## Assumptions

- The target platforms for the native share UX are modern iOS Safari / installed Home Screen PWA (iOS 15+) and Android Chrome on the installed PWA, all of which support sharing files via the Web Share API. Older iOS versions are rare in the user base (office staff on managed devices) and get the fallback path.
- Desktop browsers, including macOS Safari, either do not support file-sharing via Web Share or support it inconsistently, and desktop users already have a working flow via "Open in new tab" → browser print dialog. Therefore desktop is deliberately left on the existing path.
- The existing letter HTML→PDF rendering pipeline (already used by the current "Generate PDF" action in the letter viewer) is the canonical way to produce a letter PDF, and this feature will reuse it rather than invent a second renderer.
- The existing server-side work order PDF export endpoint already returns final printable bytes — no new backend work is needed to produce a shareable artefact. This feature is purely a frontend sharing layer.
- The specific iOS breakage is triggered by the existing "Open in new tab" control in the letter HTML viewer and by the built-in toolbar actions of the underlying PDF preview widget (print/share/download) in the work order export. Both are in-scope to be replaced on mobile: the letter viewer gains an AppBar share button in place of "Open in new tab", and the work order PDF preview screen gains an AppBar share button while its internal toolbar actions are hidden on mobile. The PDF preview widget body (scroll, zoom, paginate) remains unchanged on all platforms.
- The existing authorization and status gating for exporting a work order PDF (closed status, user role check) continues to govern who can share — sharing does not introduce a new permission surface.
- No new persistent data is introduced: PDF bytes are generated, passed to the share sheet, and released; nothing is stored server-side or in local storage as a result of a share.
- No analytics/telemetry for share events is required as part of this feature; if the team later wants to measure adoption, that is a follow-up.
- No backend changes are required. This is a frontend-only change to two screens (letter HTML viewer, work order PDF preview) plus a small shared share-capability helper.
