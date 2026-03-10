#!/bin/bash
set -e


SERVER="zorin@100.85.73.37"
APP="/var/www/flutter_app"
BACKUP="/var/www/backups"

echo "Building Flutter Web..."
cd /c/Development/flutter_work_order/frontend
flutter build web

echo "Creating backup on server..."
ssh $SERVER "mkdir -p $BACKUP && cp -r $APP $BACKUP/flutter_app_\$(date +%F_%H-%M)"

echo "Deploying new build..."
scp -r build/web/* $SERVER:$APP/

echo "Deployment complete."
