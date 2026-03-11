#!/bin/bash
set -e

SERVER="zorin@100.85.73.37"
LOCAL_PROJECT="/c/Development/flutter_work_order/frontend"

RELEASE_DIR="/var/www/releases"
CURRENT_LINK="/var/www/flutter_app"

TIMESTAMP=$(date +%F_%H-%M)
NEW_RELEASE="$RELEASE_DIR/release_$TIMESTAMP"

echo "Building Flutter Web..."
cd $LOCAL_PROJECT
flutter build web

echo "Creating new release..."
ssh $SERVER "mkdir -p $NEW_RELEASE"

echo "Uploading build..."
scp -r build/web/* $SERVER:$NEW_RELEASE/

echo "Switching to new release..."
ssh $SERVER "ln -sfn $NEW_RELEASE $CURRENT_LINK"

echo "Deployment complete."