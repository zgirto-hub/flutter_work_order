#!/usr/bin/env bash
# Usage:
#   ./deploy_frontend.sh           → bumps patch and deploys
#   ./deploy_frontend.sh patch     → bumps patch and deploys
#   ./deploy_frontend.sh minor     → bumps minor and deploys
#   ./deploy_frontend.sh major     → bumps major and deploys
#   ./deploy_frontend.sh 2.1.0     → sets exact version and deploys
#   ./deploy_frontend.sh --build   → bumps only build number and deploys
#   ./deploy_frontend.sh --no-bump → deploys without changing version
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load deploy config from root .env
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a; source "$SCRIPT_DIR/../.env"; set +a
fi
SERVER="${DEPLOY_SERVER:-zorin@100.85.73.37}"

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
PUBSPEC_VERSION=$(grep '^version:' "$LOCAL_PROJECT/pubspec.yaml" | sed 's/version: //')
NEW_VERSION=$(echo "$PUBSPEC_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$PUBSPEC_VERSION" | cut -d'+' -f2)
BUILD_DATE=$(date +%Y-%m-%d_%H-%M-%S)
RELEASE_ID=$(date +%Y%m%d%H%M%S)

echo "Building Flutter Web (v$NEW_VERSION+$BUILD_NUMBER, release $RELEASE_ID)..."
cd "$LOCAL_PROJECT"
flutter build web --dart-define=BUILD_DATE=$BUILD_DATE --dart-define=RELEASE_ID=$RELEASE_ID

# Replace Flutter's generated cleanup worker with a non-looping unregister worker.
# This safely removes legacy registrations without forcing client.navigate().
cat > build/web/flutter_service_worker.js <<'SWEOF'
'use strict';

self.addEventListener('install', function() {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil((async function() {
    try {
      await self.registration.unregister();
    } catch (_) {}
  })());
});
SWEOF

cat > build/web/release.json <<EOF
{
  "version": "$NEW_VERSION",
  "build": "$BUILD_NUMBER",
  "release_id": "$RELEASE_ID",
  "build_date": "$BUILD_DATE"
}
EOF
echo "Wrote build/web/release.json (release_id=$RELEASE_ID)."

if [[ ! -f build/web/release.json ]]; then
  echo "ERROR: release.json was not generated. Aborting deploy."
  exit 1
fi

# ── Deploy ────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%F_%H-%M)
NEW_RELEASE="$RELEASE_DIR/release_$TIMESTAMP"

echo "Creating new release..."
ssh $SERVER "mkdir -p $NEW_RELEASE"

echo "Uploading build..."
scp -r build/web/* $SERVER:$NEW_RELEASE/

# Keep server git working tree clean: do not scp tracked repo files
# (for example backend/version.json) into /home/zorin/Development/flutter_work_order.

echo "Switching to new release..."
ssh $SERVER "ln -sfn $NEW_RELEASE $CURRENT_LINK"

echo "Verifying deployed release metadata..."
ssh $SERVER "test -f $CURRENT_LINK/release.json"

echo "Cleaning old releases (keep last 10)..."
ssh $SERVER "ls -dt $RELEASE_DIR/release_* 2>/dev/null | tail -n +11 | xargs -r rm -rf"

echo ""
echo "Deployment complete → v$NEW_VERSION"
