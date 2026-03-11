#!/bin/bash
set -e

SERVER="zorin@100.85.73.37"
RELEASE_DIR="/var/www/releases"
CURRENT_LINK="/var/www/flutter_app"

echo "Available releases:"
ssh $SERVER "ls -dt $RELEASE_DIR/release_* | nl"

echo ""
read -p "Enter release number: " NUM

VERSION=$(ssh $SERVER "ls -dt $RELEASE_DIR/release_* | sed -n ${NUM}p")

ssh $SERVER "ln -sfn $VERSION $CURRENT_LINK"

echo "Rollback complete."
