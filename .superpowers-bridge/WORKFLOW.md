# Hybrid Superpowers Workflow

## Quick Reference

| Phase | Tool | Purpose |
|-------|------|---------|
| Planning | Claude Code | Design, spec, plan |
| Implementation | OpenCode | Execute tasks |
| Review | Claude Code | Debug, refactor |

## Phase 1: Planning in Claude Code

1. **Start session**:
```bash
   ./.superpowers-bridge/scripts/start-planning-session.sh "feature-name" "description"
```

2. **Open Claude Code** and use brainstorming skill

3. **Create plan** with writing-plans skill (DO NOT use subagent-driven-development)

4. **Break into tasks** - each 5-15 minutes

## Phase 2: Implementation in OpenCode

1. **Hand off**:
```bash
   ./.superpowers-bridge/scripts/handoff-to-opencode.sh .superpowers-bridge/handoffs/[dir]
```

2. **Open OpenCode** and paste the prompt

3. **Execute tasks** one by one, waiting for approval between each

## Phase 3: Review (if needed)

Switch back to Claude Code for:
- Complex bugs (use systematic-debugging skill)
- Code review (use requesting-code-review skill)
- Refactoring (use test-driven-development skill)

## Best Practices

- Claude Code: Planning, decisions, debugging
- OpenCode: Implementation, following instructions
- Switch freely when appropriate
