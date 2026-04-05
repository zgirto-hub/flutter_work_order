# Quickstart: Version-File Based PWA Update Detection

**Feature**: 017-pwa-version-update | **Date**: 2026-04-05

## What This Feature Does

Replaces the unreliable service-worker-event-based PWA update detection with a simple version-file comparison. On each deployment, a `version.json` file with a unique `releaseId` timestamp is generated. The app seeds this value on load and periodically re-fetches it to detect new deployments.

## Files to Modify

| File | Change |
|------|--------|
| `scripts/deploy_frontend.sh` | Ensure version.json uses `releaseId` field; add explicit SW cache-bypass for version.json |
| `frontend/web/index.html` | Replace SW event detection IIFE with version-file seeding + checkForAppUpdate + registerUpdateCallback; keep applyPWAUpdate with single-fire guard |
| `nginx_flutter_app.conf` | Add `location = /version.json` exact-match block before regex block |
| `server/nginx/flutter_app.conf` | Same nginx change (server copy) |
| `frontend/lib/services/pwa_update_web.dart` | Replace five functions with three: checkForUpdate (returns Future<UpdateStatus>), registerUpdateCallback, applyUpdate |
| `frontend/lib/services/pwa_update_stub.dart` | Update stub signatures to match new API |
| `frontend/lib/screens/dashboard_screen.dart` | Update calls to use new function names |
| `frontend/lib/screens/settings_page.dart` | Update calls to use new function names |

## Implementation Order

1. **Deploy script** — Ensure version.json has `releaseId` field and SW bypasses cache for it
2. **Nginx config** — Add exact-match location block for version.json
3. **index.html** — Replace SW event detection with version-file approach
4. **Dart interop** — Update pwa_update_web.dart and pwa_update_stub.dart
5. **Screens** — Update dashboard and settings to use new API

## Testing Checklist

- [ ] Deploy a new version → verify version.json has `releaseId` field
- [ ] Open app → verify seeded releaseId matches version.json on server
- [ ] Deploy again while app is open → verify callback fires
- [ ] Call checkForUpdate when no new version → verify returns upToDate
- [ ] Disconnect network → call checkForUpdate → verify returns error
- [ ] Tap apply update → verify overlay shows and page reloads once
- [ ] Tap apply update twice rapidly → verify only one reload
- [ ] Test on iOS Safari → verify detection works (the main motivation)
