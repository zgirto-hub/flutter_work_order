# Quickstart — Manual Validation Checklist for iOS PWA Native Share

**Feature**: 038-ios-pwa-share
**Purpose**: Stand-in for automated tests. Every check below MUST pass on the listed device/browser combos before this feature ships. iOS rows are **release-blocking** (Q4 clarification). Android rows are **smoke-tested, not release-blocking**. Desktop rows are **regression checks** (must not regress).

---

## Build & deploy

1. From repo root: `bash scripts/deploy_frontend.sh` (or whatever the current dev-deploy path is — check `scripts/` for the up-to-date name).
2. Bump patch version if required: `bash scripts/bump_version.sh`.
3. Confirm the Flutter web build completes without errors.
4. Confirm the backend server is running and the new `POST /activity-log/shared` endpoint responds with 200 for a valid body and 400 for an invalid `document_type`:
   ```bash
   # 200 path
   curl -X POST https://<host>/activity-log/shared \
        -H 'Content-Type: application/json' \
        -d '{"user_email":"test@example.com","document_type":"letter","document_id":"test-id"}'
   # → {"status":"logged"}
   # 400 path
   curl -X POST https://<host>/activity-log/shared \
        -H 'Content-Type: application/json' \
        -d '{"user_email":"test@example.com","document_type":"wrong","document_id":"test-id"}'
   # → 400 Bad Request
   ```

## Device matrix

| # | Device | Browser | Context | Gate |
|---|--------|---------|---------|------|
| 1 | iPhone | Safari (Home Screen PWA) | Installed PWA | 🚫 Release-blocking |
| 2 | iPhone | Safari (regular tab) | Not installed | 🚫 Release-blocking |
| 3 | iPad | Safari (Home Screen PWA) | Installed PWA | 🚫 Release-blocking |
| 4 | Android phone | Chrome (installed PWA) | Installed PWA | 🟡 Smoke only |
| 5 | Desktop Windows | Chrome | Regular tab | 🟢 Regression |
| 6 | Desktop Windows | Edge | Regular tab | 🟢 Regression |
| 7 | Desktop Mac | Safari | Regular tab | 🟢 Regression |
| 8 | Desktop Linux | Firefox | Regular tab | 🟢 Regression |

---

## Letters V2 — share from the HTML viewer

Run these steps on every device in rows 1–4, and the **desktop regression** steps on rows 5–8.

### Mobile path (rows 1–4)

1. Log in. Navigate to **Letters V2 → History** tab.
2. Tap a saved letter to preview it → the `LetterHtmlViewerScreen` opens.
3. **Observation**: the AppBar shows a **share icon** (iOS/Android share glyph), NOT an "open in new tab" icon.
4. Tap the share icon.
5. **Expected**: within ~3 seconds (SC-004), the **native system share sheet** appears with a PDF file attached, the file label matching the pattern `letter_<first-8-of-id>.pdf`, and the source title showing the letter subject (Arabic or English, rendered correctly).
6. Select **AirDrop** (iOS) → send to a nearby device → confirm the nearby device receives the PDF and can open it.
7. Repeat the share: this time select **Mail** → confirm the Mail composer opens with the PDF as an attachment named correctly.
8. Repeat: select **Save to Files** → confirm the PDF is saved and openable.
9. Repeat: select **Print** → confirm the iOS Print dialog appears and renders a preview.
10. Repeat: tap the share icon, then **cancel** the share sheet → confirm the user is returned to the letter viewer on the same screen with NO error message, NO snackbar, NO navigation (FR-010, US1 AC#3).
11. **Critical check**: after ALL of the above, confirm the user is STILL inside the installed PWA (rows 1 and 3) — not kicked to Safari. Check by looking at the status bar / app chrome.
12. Navigate to **Letters V2 → Create**. Fill out a new letter form. Tap **Preview** to open the HTML viewer. Tap the share icon in the viewer → confirm the share sheet appears with a freshly-generated PDF (filename `letter_<millis>.pdf`).

### Desktop regression (rows 5–8)

1. Log in. Navigate to **Letters V2 → History**. Tap a letter.
2. **Observation**: the AppBar shows the existing **"Open in new tab"** icon (the `open_in_new_rounded` glyph with tooltip "Open in new tab (for printing)"), NOT a share icon.
3. Tap it → confirm a new browser tab opens showing the letter HTML (current behaviour).
4. Confirm no share sheet or share UI is triggered anywhere.

---

## Work Order PDF export — share from the preview

Run on every device in rows 1–4, and the desktop regression on rows 5–8.

### Mobile path (rows 1–4)

1. Navigate to **Work Orders**. Open a **closed** work order.
2. Tap **Export PDF** → `PdfPreviewScreen` opens and begins loading.
3. **Observation while loading**: the `PdfPreview` body shows a progress indicator. The AppBar shows a **share icon**. The built-in toolbar actions of the `printing` package (print, share, download buttons in the package's toolbar) are **hidden**.
4. Wait for the PDF to finish loading → confirm the preview renders.
5. Tap the AppBar share icon. **Expected**: the native share sheet opens with a PDF attached, filename `WO-<jobNo>.pdf`, source title indicating it's a work order report.
6. Select **AirDrop** → confirm delivery.
7. Select **Mail** → confirm composer has the PDF as an attachment.
8. Select **Save to Files** → confirm the PDF saves.
9. Select **Print** → confirm the Print dialog renders.
10. Cancel path: tap share, cancel the sheet → no error, no snackbar, user stays on `PdfPreviewScreen` (FR-010).
11. Double-tap path: tap the share icon twice rapidly → only one share sheet opens (FR-012). The second tap is ignored while the first is in flight.
12. **Critical**: after all share operations, user is still inside the installed PWA (rows 1 and 3) — NOT kicked to Safari.
13. Navigate to an **open** (not closed) work order → confirm Export PDF is not offered at all (FR-014 / existing gating).

### Desktop regression (rows 5–8)

1. Open a closed work order → Export PDF → `PdfPreviewScreen` loads.
2. **Observation**: the AppBar does NOT show a mobile share icon. The `printing` package's built-in toolbar is visible as today with its print, share (browser-native), and download buttons.
3. Use the package's built-in print button → confirm it opens the browser print dialog (current behaviour).
4. Use the package's built-in download button → confirm the PDF downloads to the browser's Downloads folder.

---

## Fallback path — unsupported platform (FR-013)

The mobile devices in rows 1–4 are expected to support `canShare({files})`. To exercise the fallback path you need to force it. Two options:

**Option A — temporarily monkey-patch `navigator.canShare` in DevTools** (iOS Safari 17+, Android Chrome):
1. Open Safari Web Inspector / Chrome DevTools connected to the PWA.
2. In the Console: `Object.defineProperty(navigator, 'canShare', { value: () => false });`
3. Refresh the page (the patch persists for the session).
4. Repeat the **Letters V2 mobile path** and the **Work Order mobile path** above.
5. **Expected**: when the share button is tapped, NO share sheet opens. Instead, the PDF is auto-downloaded to the device's Files / Downloads location. A brief **"Saved to Files"** confirmation snackbar appears.
6. Confirm the user is still on the same screen inside the PWA (FR-006).
7. Confirm the PDF can be opened from Files / Downloads.

**Option B — use an older iOS device** (iOS 14 or earlier) if available.

Fallback rows are **expected behaviour**, not bugs. They satisfy SC-005.

---

## Audit log check

After completing the Letters and Work Orders share flows on **one** device, query the backend:

```bash
curl "https://<host>/activity-log?category=file&limit=10"
curl "https://<host>/activity-log?category=work_order&limit=10"
```

Expected: one row per share button tap, with `action = "shared"`, `target_type` set correctly, `target_id` matching the document you shared. Cancelled shares should still have a row (intent is logged, not completion — per research decision 7).

---

## Sign-off checklist

Before merging:

- [ ] Rows 1 and 2 (iPhone Safari PWA + iPhone Safari tab) pass all Letters and Work Orders mobile steps
- [ ] Row 3 (iPad Safari PWA) passes all Letters and Work Orders mobile steps
- [ ] Rows 5, 6, 7, 8 (all desktops) pass the **regression** checks with NO visual or behavioural change from current production
- [ ] Row 4 (Android PWA) smoke-tested: share sheet opens once on letters and once on work orders with the correct PDF
- [ ] Fallback path (Option A) verified on at least one iOS device and one Android device
- [ ] Audit log verified — at least one `shared` row visible per document type
- [ ] No regression to the existing "Generate PDF" download flow (mobile or desktop)
- [ ] Version bumped via `scripts/bump_version.sh`
- [ ] `backend/version.json` NOT committed (constitution technology constraint)

If any iOS row fails, the feature is NOT ready to ship. If an Android row fails, file a follow-up ticket but do not block the release.
