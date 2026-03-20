#!/usr/bin/env bash
# IMPORTANT: Always use this script to deploy. Never manually copy files to /var/www/flutter_app
#   - The deploy script uses symlinks to /var/www/releases/release_* directories
#   - Direct file copies will break the release system and cause version mismatches
#
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

echo "Switching to new release..."
ssh $SERVER "
  # Ensure /var/www/flutter_app is always a symlink, never files
  if [ -L '$CURRENT_LINK' ]; then
    rm '$CURRENT_LINK'
  elif [ -d '$CURRENT_LINK' ]; then
    echo 'WARNING: /var/www/flutter_app was a directory (not symlink). Replacing with symlink.'
    rm -rf '$CURRENT_LINK'
  fi
  ln -sfn '$NEW_RELEASE' '$CURRENT_LINK'
"

echo "Verifying deployed release metadata..."
ssh $SERVER "test -f $CURRENT_LINK/release.json && echo 'Release metadata verified.'"

# Verify version matches
DEPLOYED_VERSION=$(ssh $SERVER "cat $CURRENT_LINK/version.json | grep -oP '\"version\":\s*\"\K[^\"]+'")
if [ "$DEPLOYED_VERSION" != "$NEW_VERSION" ]; then
  echo "ERROR: Version mismatch! Expected $NEW_VERSION, got $DEPLOYED_VERSION"
  exit 1
fi
echo "Version check passed: v$DEPLOYED_VERSION"

echo "Cleaning old releases (keep last 10)..."
ssh $SERVER "ls -dt $RELEASE_DIR/release_* 2>/dev/null | tail -n +11 | xargs -r rm -rf"

echo ""
echo "Deployment complete → v$NEW_VERSION"
