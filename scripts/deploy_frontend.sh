#!/usr/bin/env bash
# Usage:
#   ./deploy_frontend.sh           → bumps patch and deploys
#   ./deploy_frontend.sh patch     → bumps patch and deploys
#   ./deploy_frontend.sh minor     → bumps minor and deploys
#   ./deploy_frontend.sh major     → bumps major and deploys
#   ./deploy_frontend.sh 2.1.0     → sets exact version and deploys
#   ./deploy_frontend.sh --no-bump → deploys without changing version
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="zorin@100.85.73.37"

# Detect OS and set project path
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  LOCAL_PROJECT="$HOME/Development/flutter_work_order/frontend"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
  LOCAL_PROJECT="/c/Development/flutter_work_order/frontend"
else
  echo "Unsupported OS"
  exit 1
fi

RELEASE_DIR="/var/www/releases"
CURRENT_LINK="/var/www/flutter_app"

# ── Bump version ─────────────────────────────────────────────────────────────
BUMP="${1:-patch}"
if [[ "$BUMP" != "--no-bump" ]]; then
  echo "Bumping version ($BUMP)..."
  "$SCRIPT_DIR/bump_version.sh" "$BUMP"
  echo ""
fi

# ── Build ─────────────────────────────────────────────────────────────────────
NEW_VERSION=$(grep '^version:' "$LOCAL_PROJECT/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f1)
echo "Building Flutter Web (v$NEW_VERSION)..."
cd "$LOCAL_PROJECT"
BUILD_DATE=$(date +%Y-%m-%d_%H-%M)
flutter build web --dart-define=BUILD_DATE=$BUILD_DATE

# Patch 1: Cache-bust main.dart.js
# flutter_bootstrap.js uses a fixed "main.dart.js" URL, which browsers cache
# for 6 months. Adding ?v=BUILD_DATE makes every build a unique URL.
sed -i "s|\"main\.dart\.js\"|\"main.dart.js?v=$BUILD_DATE\"|g" build/web/flutter_bootstrap.js
echo "main.dart.js cache-busted with ?v=$BUILD_DATE"

# Patch 2: Replace Flutter's generated SW with a no-op.
# Flutter's generated SW calls client.navigate() on every activate, causing
# an infinite reload loop in PWA standalone mode.
cat > build/web/flutter_service_worker.js << 'SWEOF'
'use strict';
// No-op service worker — caching handled by Nginx + cache-busted URLs.
// No clients.claim() to avoid firing controllerchange on running PWA clients.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.map(k => caches.delete(k)))));
});
SWEOF
echo "Service worker replaced with no-op."

# ── Deploy ────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%F_%H-%M)
NEW_RELEASE="$RELEASE_DIR/release_$TIMESTAMP"

echo "Creating new release..."
ssh $SERVER "mkdir -p $NEW_RELEASE"

echo "Uploading build..."
scp -r build/web/* $SERVER:$NEW_RELEASE/

echo "Uploading version.json..."
scp "$SCRIPT_DIR/../backend/version.json" $SERVER:/home/zorin/Development/flutter_work_order/backend/version.json

echo "Switching to new release..."
ssh $SERVER "ln -sfn $NEW_RELEASE $CURRENT_LINK"

echo "Cleaning old releases (keep last 10)..."
ssh $SERVER "ls -dt $RELEASE_DIR/release_* 2>/dev/null | tail -n +11 | xargs -r rm -rf"

echo ""
echo "Deployment complete → v$NEW_VERSION"
