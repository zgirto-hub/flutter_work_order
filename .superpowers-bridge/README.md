# Superpowers Bridge System

Hybrid workflow: Claude Code (planning) + OpenCode (implementation)

## Quick Start

1. Start planning:
```bash
   ./.superpowers-bridge/scripts/start-planning-session.sh "feature-name" "description"
```

2. Plan in Claude Code

3. Hand off to OpenCode:
```bash
   ./.superpowers-bridge/scripts/handoff-to-opencode.sh .superpowers-bridge/handoffs/[dir]
```

4. Implement in OpenCode

See WORKFLOW.md for complete guide.
