# Fixing Plan — Feature 028 Review Findings

**Created**: 2026-04-07
**Based on**: [review-findings.md](review-findings.md)
**Goal**: Take the 028 implementation from "scaffold complete, runtime broken" to "deploy-ready" with the minimum set of surgical edits.

---

## Execution order

Fixes are ordered so that each step is independently verifiable and the dependency chain runs forward-only. Do them in this order; do not batch 1–4 into a single commit — each is a distinct logical change.

---

## Step 1 — F1: Fix `api_put` callable bug (C1)

**File**: `specs/028-openclaw-telegram-ops/server/skills/_lib/wo_api.py`
**Lines**: 79–98

**Change**:

```python
def api_put(path: str, body: dict) -> dict:
    api_base = get_api_base()

    if not path.startswith("/"):
        path = "/" + path

    url = api_base + path

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        method="PUT",
    )
    req.add_header("Content-Type", "application/json")

    with urllib.request.urlopen(req, timeout=10) as response:
        data = response.read().decode("utf-8")
        return json.loads(data)
```

- Pass `method="PUT"` to `Request()` constructor (Python 3.3+ kwarg).
- Delete the `req.get_method = "PUT"` line.
- Delete the dead `try/except ... raise` blocks while you're there (also applies to `api_get` and `api_post`, see F8).

**Verification**:
```bash
python3 -c "
import sys; sys.path.insert(0, 'specs/028-openclaw-telegram-ops/server/skills/_lib')
import os; os.environ['API_BASE_URL']='http://localhost:8000/api'; os.environ['ADMIN_EMAIL']='x@y.z'
from wo_api import api_put
# Will raise URLError (connection refused), NOT TypeError
try: api_put('/work-orders/1', {'status':'Open'})
except TypeError as e: print('STILL BROKEN:', e); exit(1)
except Exception: print('OK')
"
```

---

## Step 2 — F2: Fix `server.sh` JSON escaping (C2)

**File**: `specs/028-openclaw-telegram-ops/server/skills/server/server.sh`
**Lines**: 4–28 (rewrite `emit_reply`)

**Change** — replace the entire `emit_reply` function with a jq-based version:

```bash
emit_reply() {
  local status="$1"
  local reply="$2"
  local outcome="$3"
  local error="${4:-}"

  local end_ts duration_ms=0
  end_ts=$(date +%s%3N)
  duration_ms=$((end_ts - START_TS))

  if [[ -n "$error" ]]; then
    jq -nc \
      --arg status "$status" \
      --arg reply "$reply" \
      --arg action "$ACTION" \
      --argjson args "$ARGS" \
      --arg outcome "$outcome" \
      --argjson duration "$duration_ms" \
      --arg error "$error" \
      '{status:$status, reply:$reply, audit:{action:$action, args:$args, outcome:$outcome, duration_ms:$duration, error:$error}}'
  else
    jq -nc \
      --arg status "$status" \
      --arg reply "$reply" \
      --arg action "$ACTION" \
      --argjson args "$ARGS" \
      --arg outcome "$outcome" \
      --argjson duration "$duration_ms" \
      '{status:$status, reply:$reply, audit:{action:$action, args:$args, outcome:$outcome, duration_ms:$duration}}'
  fi
}
```

**Why `jq -nc`**: `-n` = no input, `-c` = single-line compact output. `--arg` auto-escapes strings; `--argjson` passes through parsed JSON for `args` and `duration`.

**Verification**:
```bash
echo '{"action":"status","args":{},"confirmed":false}' | bash specs/028-openclaw-telegram-ops/server/skills/server/server.sh | jq .
# MUST print valid JSON without errors. Previously: jq would fail on unescaped newlines.
```

---

## Step 3 — F3: Fix `server.sh` `errors` action lines arg (C3)

**File**: `specs/028-openclaw-telegram-ops/server/skills/server/server.sh`

**Change 1** — in `main()`, after parsing `ACTION`/`ARGS`/`CONFIRMED`, add:
```bash
LINES=$(echo "$input" | jq -r '.args.lines // 20' 2>/dev/null || echo "20")
```

**Change 2** — in `action_errors()`, replace:
```bash
local lines="${ARGS:-20}"
```
with:
```bash
local lines="${LINES:-20}"
```

The clamp logic (`-gt 100` / `-lt 1`) stays the same.

**Verification**:
```bash
echo '{"action":"errors","args":{"lines":5},"confirmed":false}' | bash server.sh | jq .
# Reply should contain output truncated to 5 lines (or "No recent errors.").
```

---

## Step 4 — F4: Fix `handle_update_status` tuple return (C4)

**File**: `specs/028-openclaw-telegram-ops/server/skills/workorders/workorders.py`
**Lines**: 207–211

**Change**:

```python
    if new_status not in valid_statuses:
        return (
            "error",
            f"Invalid status. Must be one of: {', '.join(valid_statuses)}",
            "failure",
            None,
        )
```

Prepend `"error"` to restore the 4-tuple contract.

**Verification**:
```bash
cd specs/028-openclaw-telegram-ops/server/skills/workorders
echo '{"action":"update_status","args":{"job_no":"1","new_status":"Bogus"},"confirmed":true,"caller_id":"X"}' | \
  OPENCLAW_CALLER_ID=X ADMIN_EMAIL=a@b.c API_BASE_URL=http://localhost:8000/api python3 workorders.py | jq .reply
# Expected: "Invalid status. Must be one of: Open, Pending, In Progress"
# Previously: a generic "An error occurred: not enough values to unpack..."
```

---

## Step 5 — F5: Switch `iso_now()` + digest date to local timezone (D1)

**File 1**: `specs/028-openclaw-telegram-ops/server/skills/_lib/wo_api.py`
**Lines**: 101–102

```python
def iso_now() -> str:
    return datetime.now().astimezone().isoformat()
```

Remove the `timezone` import if no longer used elsewhere in the file (keep it — `parse_iso` tolerates `Z`).

**File 2**: `specs/028-openclaw-telegram-ops/server/skills/heartbeat/daily_digest.py`
**Line**: 54

```python
today = datetime.now().astimezone().strftime("%Y-%m-%d")
```

**File 3**: `specs/028-openclaw-telegram-ops/server/skills/heartbeat/weekly_summary.py`
**Lines**: 48–50

```python
today = datetime.now().astimezone()
end_date = today.strftime("%Y-%m-%d")
start_date = (today - timedelta(days=7)).strftime("%Y-%m-%d")
```

**File 4**: `specs/028-openclaw-telegram-ops/server/skills/email/email.py`
**Lines**: 88–90

Same pattern as weekly_summary.

**File 5**: `specs/028-openclaw-telegram-ops/server/skills/heartbeat/push_failure_check.py`
**Line**: 34

```python
one_hour_ago = datetime.now().astimezone() - timedelta(hours=1)
```

**Verification**:
```bash
python3 -c "
from datetime import datetime
print(datetime.now().astimezone().isoformat())
# Should print with local offset like '2026-04-07T08:36:00+03:00', NOT '+00:00'
"
```

---

## Step 6 — F6: Verify OpenClaw audit log writing (D2)

**No code change in this step — verification only.**

After deploying, do the following smoke test on the server:

```bash
# 1. Tail the audit log in one terminal
tail -f ~/.openclaw/audit.log

# 2. Send one test message via Telegram: "show open work orders"

# 3. Expect ONE new NDJSON line to appear within ~5 seconds:
#    {"ts":"...","caller":"...","input":"show open work orders","skill":"workorders","action":"list_open","outcome":"success",...}
```

### Contingency if OpenClaw does NOT auto-write the audit log

Add an explicit fallback in `envelope.py`:

**File**: `specs/028-openclaw-telegram-ops/server/skills/_lib/envelope.py`

Add a new helper:

```python
def append_audit(
    action: str,
    args: Dict,
    outcome: str,
    caller: str,
    input_text: str,
    duration_ms: int,
    error: Optional[str] = None,
) -> None:
    """Fallback audit log writer. Only invoked if OPENCLAW_AUDIT_FALLBACK=1."""
    import os
    if os.environ.get("OPENCLAW_AUDIT_FALLBACK") != "1":
        return
    log_path = os.environ.get("OPENCLAW_AUDIT_LOG", "")
    if not log_path:
        return
    log_path = os.path.expanduser(log_path)
    record = {
        "ts": _local_iso(),
        "caller": caller,
        "input": input_text[:500],
        "skill": os.environ.get("OPENCLAW_SKILL_NAME", ""),
        "action": action,
        "args": args,
        "outcome": outcome,
        "duration_ms": duration_ms,
    }
    if error:
        record["error"] = error
    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError:
        pass  # never block on audit failure
```

Then in `write_reply`, after `print(...)`, call `append_audit(...)` with the same fields. Add `OPENCLAW_AUDIT_FALLBACK=1`, `OPENCLAW_AUDIT_LOG=~/.openclaw/audit.log`, and `OPENCLAW_SKILL_NAME=<name>` to `openclaw.json` → `env` block.

**Decision gate**: Only implement the fallback after the verification step shows OpenClaw is NOT writing automatically. Do not pre-implement.

---

## Step 7 — F7: Confirm and unify email endpoint path (D3)

**No code change until confirmed.**

### Action

1. Open the parallel Exchange-SMTP feature spec (likely `specs/02x-exchange-smtp/`) and find the actual email endpoint path.
2. It will be one of:
   - `POST /api/work-orders/{id}/email` (attachment-oriented)
   - `POST /api/email/send` (generic)
   - Something else

### Then fix

**File**: `specs/028-openclaw-telegram-ops/server/skills/email/email.py`

- **Line 63** (`handle_send_work_order_pdf`): replace `/work-orders/{wo_id}/email` with the confirmed path. If generic `/email/send`, switch to:
  ```python
  api_post("/email/send", {
      "to": [to],
      "cc": cc,
      "from_email": admin_email,
      "subject": subject or f"Work Order #{job_no}",
      "work_order_id": wo_id,  # or attachment ref per spec
  })
  ```
- **Line 141** (`handle_send_weekly_summary`): ensure it uses the same path as above.

### If the SMTP feature is not yet specced

Leave `handle_send_work_order_pdf` on `/work-orders/{id}/email` and `handle_send_weekly_summary` on `/email/send`. Both will hit the graceful-degrade branch (`Email backend not available yet.`) until the feature ships. Add a TODO comment:

```python
# TODO(028): Unify endpoint with parallel SMTP feature once the path is finalized.
```

---

## Step 8 — F8: Polish (M1–M7, optional but cheap)

Do these in a single "polish" commit after F1–F5 are verified working.

### M1. Delete dead re-raise blocks in `wo_api.py`

Each of `api_get`, `api_post`, `api_put`: remove:
```python
except urllib.error.HTTPError as e:
    raise
except urllib.error.URLError as e:
    raise
```
Just let exceptions propagate naturally.

### M2. `install_openclaw.sh` indirect expansion safety

**Line 9**:
```bash
local var_value="${!var_name:-}"
```

### M3. Clean up `.gitkeep` files post-install

In `install_openclaw.sh`, after the `cp -r` line, add:
```bash
find "$OPENCLAW_DIR/skills" -name .gitkeep -delete
```

### M4. Server skill "inactive" branding

In `server.sh` `action_status()`, replace:
```bash
else
  nginx_status="unknown"
fi
```
with:
```bash
else
  nginx_status="inactive ❌"
fi
```
Same for fastapi.

### M5. SKILL.md `requiresConfirmation` list form

Only action needed **if OpenClaw fails to parse the block list form**. First check on deploy:
```bash
openclaw skills list
```
If `workorders` or `server` is missing its `requiresConfirmation` entries, convert to flow form:
```yaml
requiresConfirmation: [close, update_status]
```

---

## Verification checklist (post-fix)

Run these in order. If any fail, stop and fix before proceeding.

- [ ] **F1**: `api_put` no longer raises `TypeError` (see Step 1 snippet)
- [ ] **F2**: `server.sh` output pipes cleanly to `jq .`
- [ ] **F3**: `errors` action respects `args.lines`
- [ ] **F4**: Invalid-status update returns the validation message via `.reply`
- [ ] **F5**: `iso_now()` prints a non-UTC offset on a server in a non-UTC timezone
- [ ] **Smoke test 1**: `workorders.py` with action `count` against a running backend returns `status=ok`
- [ ] **Smoke test 2**: `workorders.py` with action `close` and `confirmed=false` returns `status=needs_confirmation`
- [ ] **Smoke test 3**: `server.sh` with action `status` returns valid JSON with nginx/fastapi status
- [ ] **Smoke test 4**: `daily_digest.py` run directly prints a valid envelope with a `*Daily Work Order Digest*` reply
- [ ] **F6 verify**: After first Telegram interaction, `audit.log` has at least one NDJSON line
- [ ] **F7**: Email endpoint path is confirmed with the SMTP feature OR explicitly marked as TODO

Only after ALL of the above pass, proceed to the full quickstart test suite (T019).

---

## Estimated line-count of changes

| Fix | File(s) | Added | Modified | Removed |
|---|---|---|---|---|
| F1 | `wo_api.py` | 0 | 3 | 4 |
| F2 | `server.sh` | 15 | 25 | 25 |
| F3 | `server.sh` | 1 | 1 | 0 |
| F4 | `workorders.py` | 1 | 0 | 0 |
| F5 | 5 files | 0 | 5 | 0 |
| F6 | `envelope.py` (conditional) | ~30 | ~3 | 0 |
| F7 | `email.py` | 0 | 2 | 0 |
| F8 | various | ~5 | ~10 | ~15 |

**Total for critical fixes (F1–F5)**: ~30 lines touched across 6 files. A single focused session.

---

## Commit strategy

Propose three commits, in order:

1. **`fix(028): critical runtime bugs in workorders and server skills`** — F1, F2, F3, F4 together (all hard blockers)
2. **`fix(028): use server-local timezone in skills per spec clarification Q2`** — F5
3. **`chore(028): polish — dead code, install script hardening, inactive branding`** — F8 (optional, can ship separately)

F6 becomes its own commit *only* if the verification step shows OpenClaw isn't auto-writing the audit log. F7 becomes its own commit once the SMTP endpoint is confirmed.

---

## What this plan deliberately does NOT do

- Does not rewrite any skill from scratch — all fixes are surgical.
- Does not touch `workorders.py` happy paths (they work).
- Does not change the architecture or the contracts in `contracts/`.
- Does not add test harness code — manual verification via the one-liners above is sufficient for this MVP.
- Does not address M5 (SKILL.md list form) preemptively — only if OpenClaw parser complains on deploy.
- Does not modify `install_openclaw.sh` systemd wiring (already correct).

---

## When you can run quickstart tests

After F1–F5 are committed and all 8 verification checklist items pass. F6 and F7 can run in parallel with the quickstart pass (they only affect edge cases and can be retrofitted mid-deployment).
