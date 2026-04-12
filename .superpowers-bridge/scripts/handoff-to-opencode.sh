#!/bin/bash
set -e

FEATURE_DIR="$1"

if [ -z "$FEATURE_DIR" ]; then
    echo "Usage: $0 <feature-directory>"
    exit 1
fi

if [ ! -d "$FEATURE_DIR" ]; then
    echo "❌ Error: Feature directory not found: $FEATURE_DIR"
    exit 1
fi

FEATURE_NAME=$(basename "$FEATURE_DIR" | sed 's/^[0-9-]*-//')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ HANDOFF TO OPENCODE READY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Feature: $FEATURE_NAME"
echo ""
echo "Copy this prompt to OpenCode:"
echo ""
cat << PROMPT

I have a complete implementation plan from Claude Code + Superpowers.

Context files:
- Spec: $FEATURE_DIR/01-SPEC.md
- Plan: $FEATURE_DIR/02-PLAN.md
- Tasks: $FEATURE_DIR/03-TASKS.md

Read all three files, then I'll feed you tasks one at a time.

Implementation rules:
1. Execute tasks in order
2. Implement exactly as described
3. Run tests after each task
4. STOP immediately if tests fail
5. Wait for my approval before next task

Ready to start?

PROMPT
