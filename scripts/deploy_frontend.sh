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
flutter build web

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
