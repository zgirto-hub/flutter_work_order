#!/usr/bin/env bash
set -e

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

TIMESTAMP=$(date +%F_%H-%M)
NEW_RELEASE="$RELEASE_DIR/release_$TIMESTAMP"

echo "Building Flutter Web..."
cd "$LOCAL_PROJECT"
flutter build web

echo "Creating new release..."
ssh $SERVER "mkdir -p $NEW_RELEASE"

echo "Uploading build..."
scp -r build/web/* $SERVER:$NEW_RELEASE/

echo "Switching to new release..."
ssh $SERVER "ln -sfn $NEW_RELEASE $CURRENT_LINK"

echo "Cleaning old releases (keep last 5)..."
ssh $SERVER "ls -dt $RELEASE_DIR/release_* 2>/dev/null | tail -n +6 | xargs -r rm -rf"

echo "Deployment complete."