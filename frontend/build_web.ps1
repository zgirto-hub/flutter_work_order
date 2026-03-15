$BUILD_DATE = Get-Date -Format "yyyy-MM-dd_HH-mm"

Write-Host "Building Flutter Web..."
Write-Host "Build date: $BUILD_DATE"

flutter build web --dart-define=BUILD_DATE=$BUILD_DATE

# -----------------------------------------------------------------------
# Patch 1: Cache-bust main.dart.js
# flutter_bootstrap.js references "main.dart.js" with no version, so browsers
# cache it for 6 months and never pick up new builds.
# Adding ?v=BUILD_DATE makes every build a unique URL -> always fetched fresh.
# flutter_bootstrap.js itself is served no-cache, so it's always up to date.
# -----------------------------------------------------------------------
$bootstrapPath = "build/web/flutter_bootstrap.js"
$bootstrapContent = Get-Content $bootstrapPath -Raw
$bootstrapContent = $bootstrapContent -replace '"main\.dart\.js"', "`"main.dart.js?v=$BUILD_DATE`""
Set-Content -Path $bootstrapPath -Value $bootstrapContent -NoNewline
Write-Host "main.dart.js cache-busted with ?v=$BUILD_DATE"

# -----------------------------------------------------------------------
# Patch 2: Replace Flutter's generated service worker with a no-op.
# Flutter's generated SW calls client.navigate() on every activate, which
# causes an infinite reload loop in PWA standalone mode.
# -----------------------------------------------------------------------
$swPath = "build/web/flutter_service_worker.js"
$noopSW = @"
'use strict';
// No-op service worker — caching handled by Nginx + cache-busted URLs.
// No clients.claim() — avoids firing controllerchange on running PWA clients,
// which causes a white screen in standalone PWA mode on some browsers.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  // Clean up any leftover caches from a previous caching service worker.
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.map(k => caches.delete(k)))));
});
"@
Set-Content -Path $swPath -Value $noopSW
Write-Host "Service worker replaced with no-op."

Write-Host "Build complete."
