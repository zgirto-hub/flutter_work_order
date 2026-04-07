---
name: server
description: Check server health and restart the FastAPI backend
entrypoint: server.sh
requiresConfirmation:
  - restart_backend
triggers:
  - "server status"
  - "disk usage"
  - "last errors"
  - "restart backend"
  - "restart fastapi"
---

# Server Management Skill

This skill provides server health monitoring and backend management capabilities.

## Actions

### status

Returns the current status of nginx, fastapi, and disk usage.

**Arguments**: None

**Example invocations**:
- "server status"
- "check server status"
- "is nginx running"

**Response**: Markdown with nginx/fastapi status and disk usage:
```
*Server status*
- nginx: active ✅
- fastapi: active ✅
- disk (/): 42% used (210G free)
```

---

### disk

Returns disk usage information.

**Arguments**: None

**Example invocations**:
- "disk usage"
- "show disk space"
- "how much disk space"

**Response**: Code block with `df -h` output, truncated to root and uploads partition.

---

### errors

Returns recent error logs from the fastapi service.

**Arguments**:
- `lines` (integer, optional): Number of lines to fetch (default 20, max 100)

**Example invocations**:
- "last errors"
- "show error logs"
- "recent fastapi errors"

**Response**: Code block with journalctl output, or "No recent errors." if empty.

---

### restart_backend

Restarts the FastAPI backend service.

**Arguments**: None

**Example invocations**:
- "restart backend"
- "restart fastapi"
- "restart the API server"

**Confirmation**: Required. First call returns needs_confirmation with prompt: "⚠️ Restart the FastAPI backend? This will briefly interrupt the app. Reply 'yes' within 60s."

**Response on success**: "✅ FastAPI restarted. New status: active."