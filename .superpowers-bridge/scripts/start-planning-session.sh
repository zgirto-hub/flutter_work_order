#!/bin/bash
set -e

FEATURE_NAME="$1"
DESCRIPTION="$2"

if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature-name> <description>"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
FEATURE_DIR=".superpowers-bridge/handoffs/${TIMESTAMP}-${FEATURE_NAME}"
mkdir -p "$FEATURE_DIR"

cp .superpowers-bridge/templates/FEATURE_SPEC.md "$FEATURE_DIR/01-SPEC.md"
cp .superpowers-bridge/templates/IMPLEMENTATION_PLAN.md "$FEATURE_DIR/02-PLAN.md"
cp .superpowers-bridge/templates/TASKS.md "$FEATURE_DIR/03-TASKS.md"

SESSION_ID="claude-${TIMESTAMP}"
DATE=$(date +"%Y-%m-%d %H:%M:%S")

sed -i.bak "s/\[FEATURE_NAME\]/$FEATURE_NAME/g" "$FEATURE_DIR"/*.md && rm "$FEATURE_DIR"/*.md.bak
sed -i.bak "s/\[DATE\]/$DATE/g" "$FEATURE_DIR"/*.md && rm "$FEATURE_DIR"/*.md.bak
sed -i.bak "s/\[SESSION_ID\]/$SESSION_ID/g" "$FEATURE_DIR"/*.md && rm "$FEATURE_DIR"/*.md.bak

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Feature planning directory created"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📂 Location: $FEATURE_DIR"
echo "🆔 Session:  $SESSION_ID"
echo "📝 Feature:  $FEATURE_NAME"
echo ""
echo "NEXT: Open Claude Code and paste:"
echo ""
echo "I want to build: $DESCRIPTION"
echo ""
echo "Use the brainstorming skill to help me refine this."
