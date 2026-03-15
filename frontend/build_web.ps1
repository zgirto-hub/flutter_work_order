$BUILD_DATE = Get-Date -Format "yyyy-MM-dd_HH-mm"

Write-Host "Building Flutter Web..."
Write-Host "Build date: $BUILD_DATE"

flutter build web --dart-define=BUILD_DATE=$BUILD_DATE

# Replace Flutter's generated service worker with a no-op.
# Flutter's generated SW calls client.navigate() on every activate, which
# causes an infinite reload loop in PWA standalone mode.
# Caching is handled by Nginx no-cache headers instead.
$swPath = "build/web/flutter_service_worker.js"
$noopSW = @"
'use strict';
// No-op service worker — caching handled by Nginx, not the SW.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
"@
Set-Content -Path $swPath -Value $noopSW
Write-Host "Service worker replaced with no-op."

Write-Host "Build complete."
