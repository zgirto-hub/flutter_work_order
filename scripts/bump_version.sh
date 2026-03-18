#!/usr/bin/env bash
# Usage:
#   ./bump_version.sh          → bumps patch  (1.7.1 → 1.7.2)
#   ./bump_version.sh patch    → bumps patch  (1.7.1 → 1.7.2)
#   ./bump_version.sh minor    → bumps minor  (1.7.1 → 1.8.0)
#   ./bump_version.sh major    → bumps major  (1.7.1 → 2.0.0)
#   ./bump_version.sh 2.0.0    → sets exact version

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PUBSPEC="$ROOT/frontend/pubspec.yaml"
VERSION_JSON="$ROOT/backend/version.json"

# ── Read current version from pubspec.yaml ──────────────────────────────────
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | cut -d'+' -f1)
BUILD=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | cut -d'+' -f2)
BUILD=$((BUILD + 1))

MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

# ── Compute new version ──────────────────────────────────────────────────────
BUMP="${1:-patch}"

case "$BUMP" in
  major)
    MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor)
    MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch)
    PATCH=$((PATCH + 1)) ;;
  [0-9]*.[0-9]*.[0-9]*)
    MAJOR=$(echo "$BUMP" | cut -d. -f1)
    MINOR=$(echo "$BUMP" | cut -d. -f2)
    PATCH=$(echo "$BUMP" | cut -d. -f3) ;;
  *)
    echo "Usage: $0 [patch|minor|major|x.y.z]"
    exit 1 ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
BUILD_DATE=$(date '+%-d %b %Y' 2>/dev/null || date '+%d %b %Y')
RELEASE_ID=$(date +%Y%m%d%H%M%S)

# ── Update pubspec.yaml ──────────────────────────────────────────────────────
sed -i "s/^version: .*/version: $NEW_VERSION+$BUILD/" "$PUBSPEC"

# ── Update version.json ──────────────────────────────────────────────────────
cat > "$VERSION_JSON" <<EOF
{
  "version": "$NEW_VERSION",
  "build_date": "$BUILD_DATE",
  "release_id": "$RELEASE_ID"
}
EOF

echo "✓ $CURRENT+$((BUILD-1))  →  $NEW_VERSION+$BUILD  ($BUILD_DATE)"
echo "  Updated: pubspec.yaml + backend/version.json"
