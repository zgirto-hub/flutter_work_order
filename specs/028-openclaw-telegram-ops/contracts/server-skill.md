# Contract: Server Management Skill

**Skill name**: `server`
**Entrypoint**: `server.sh`
**Requires confirmation**: `["restart_backend"]`

## Actions

### `status`
- **args**: `{}`
- **runs**: `systemctl is-active nginx`, `systemctl is-active fastapi`, `df -h /` (root filesystem only).
- **reply**:
  ```
  *Server status*
  - nginx: active ✅
  - fastapi: active ✅
  - disk (/): 42% used (210G free)
  ```

### `disk`
- **args**: `{}`
- **runs**: `df -h`
- **reply**: code block with the table truncated to root + uploads partition.

### `errors`
- **args**: `{ "lines": <int, default 20, max 100> }`
- **runs**: `journalctl -u fastapi -p err -n <lines> --no-pager`
- **reply**: code block with the captured lines, or `No recent errors.` if empty.

### `restart_backend`
- **args**: `{}`
- **runs**: `sudo systemctl restart fastapi` (requires sudoers entry — see quickstart)
- **confirmation**: required. First call returns `needs_confirmation` with prompt: `⚠️ Restart the FastAPI backend? This will briefly interrupt the app. Reply "yes" within 60s.`
- **reply on success**: `✅ FastAPI restarted. New status: active.` (re-checks `is-active` after restart).

## Safety boundary

The script MUST whitelist actions by name. No `eval`, no command interpolation from arguments. Any action name not in the above list returns `status=error` with reply `Unknown server action.`.
