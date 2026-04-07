# Implementation Review — Feature 028 OpenClaw Telegram Ops

**Reviewed**: 2026-04-07
**Scope**: All artifacts under `specs/028-openclaw-telegram-ops/server/`
**Verdict**: Scaffold correct; **several runtime-breaking bugs** must be fixed before deploying.

---

## 🔴 Critical bugs (block runtime)

### C1. `api_put` is broken — assigns string to `get_method`
**File**: [server/skills/_lib/wo_api.py:89](server/skills/_lib/wo_api.py#L89)

```python
req.get_method = "PUT"
```

`Request.get_method` must be a **callable**, not a string. urllib crashes with `TypeError: 'str' object is not callable` the moment `api_put` is called — which is the `update_status` path.

**Fix**:
```python
req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="PUT")
req.add_header("Content-Type", "application/json")
```
Drop the `req.get_method = ...` line entirely.

---

### C2. `server.sh` emits invalid JSON — multiline reply strings never escaped
**File**: [server/skills/server/server.sh:19](server/skills/server/server.sh#L19)

```bash
local json='{"status":"'"$status"'","reply":"'"$reply"'",...}'
```

`$reply` contains literal `\n`, quotes, and backticks (`action_status`, `action_disk`, `action_errors` all build multiline Markdown). Concatenating into JSON produces **invalid JSON** — OpenClaw will fail to parse every server-skill response.

**Fix**: Use `jq -nc --arg` as the T011 prompt required:
```bash
jq -nc \
  --arg status "$status" \
  --arg reply "$reply" \
  --arg action "$ACTION" \
  --argjson args "$ARGS" \
  --arg outcome "$outcome" \
  --argjson duration "$duration_ms" \
  '{status:$status, reply:$reply, audit:{action:$action, args:$args, outcome:$outcome, duration_ms:$duration}}'
```

---

### C3. `server.sh` — `errors` action ignores the `lines` arg
**File**: [server/skills/server/server.sh:80](server/skills/server/server.sh#L80)

```bash
local lines="${ARGS:-20}"
```

`$ARGS` is the *entire args JSON object* (e.g. `{"lines":50}`), not the numeric `lines` value. The `-gt`/`-lt` comparison on the next line fails silently and the default 20 is always used.

**Fix**: In `main()`, extract lines from the JSON:
```bash
LINES=$(echo "$input" | jq -r '.args.lines // 20')
```
Then use `$LINES` in `action_errors`.

---

### C4. `handle_update_status` returns 3-tuple on invalid status
**File**: [server/skills/workorders/workorders.py:207-211](server/skills/workorders/workorders.py#L207-L211)

```python
if new_status not in valid_statuses:
    return (
        f"Invalid status. Must be one of: {', '.join(valid_statuses)}",
        "failure",
        None,
    )
```

All other return paths are 4-tuples `(status, reply, outcome, error)`. The caller unpacks 4 values → `ValueError: not enough values to unpack`. The top-level `try/except` in `main()` catches it, so the user sees a generic error instead of the intended validation message.

**Fix**: prepend `"error"`:
```python
return ("error", f"Invalid status. Must be one of: {', '.join(valid_statuses)}", "failure", None)
```

---

## 🟠 Spec/contract drift

### D1. `iso_now()` uses UTC, clarification says server-local
**Files**:
- [server/skills/_lib/wo_api.py:101-102](server/skills/_lib/wo_api.py#L101-L102)
- [server/skills/heartbeat/daily_digest.py:54](server/skills/heartbeat/daily_digest.py#L54)

```python
def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()
```

Spec Clarification Q2 says scheduled jobs run in **server local timezone**. The T005 prompt explicitly said `datetime.now().astimezone()`.

**Impact**:
- Audit-log timestamps in UTC contradict operator expectations.
- `daily_digest.py`'s "today" header uses UTC date → Riyadh 7 AM digest shows yesterday's date.
- Overdue math still works (both sides TZ-aware), so the count is right.

**Fix**:
```python
def iso_now() -> str:
    return datetime.now().astimezone().isoformat()
```
And in `daily_digest.py` line 54: `today = datetime.now().astimezone().strftime("%Y-%m-%d")`.

---

### D2. FR-025 audit log is never actually written by the skills
**Files**: all skills + `install_openclaw.sh`

The install script creates `~/.openclaw/audit.log` and the config points to it, but **no skill writes to it**. Skills emit an `audit` block in their stdout envelope and trust OpenClaw to persist it. This is the intended design per research R7 — but it hinges on OpenClaw actually reading the envelope's `audit` object and appending it to `audit.logPath`.

**Risk**: If OpenClaw doesn't do this automatically, FR-025 is silently unsatisfied and SC-006 can't be audit-verified.

**Action**: On first deploy, tail `audit.log` during a test and confirm lines are appended. If not, add a fallback: each skill's `write_reply` also opens `$OPENCLAW_AUDIT_LOG` (new env var in `openclaw.json`) and appends its own NDJSON line.

---

### D3. Email endpoint path is inconsistent
**File**: [server/skills/email/email.py](server/skills/email/email.py)

- Line 63: `POST /work-orders/{id}/email` (in `handle_send_work_order_pdf`)
- Line 141: `POST /email/send` (in `handle_send_weekly_summary`)

Two different endpoints. The parallel Exchange-SMTP feature likely exposes only one. The mismatched path will 404 and the graceful-degrade branch will fire.

**Action**: Confirm the actual endpoint path from the SMTP feature spec and use one consistently.

---

### D4. `server.sh` `disk` action regex is brittle
**File**: [server/skills/server/server.sh:68](server/skills/server/server.sh#L68)

```bash
df -h 2>/dev/null | grep -E '^/dev/(sda|vda|nvme)' | head -5
```

Misses LVM/mapper mounts (`/dev/mapper/...`) common on Zorin VMs. Falls through to the `df -h | tail -n +2 | head -10` default, so acceptable.

**Optional fix**: Broaden the regex or drop the filter and just show the top 10 real filesystems.

---

## 🟡 Minor issues

### M1. `wo_api.py` — dead `try/except ... raise` blocks
Every HTTP method has:
```python
except urllib.error.HTTPError as e:
    raise
except urllib.error.URLError as e:
    raise
```
No-op. Delete for clarity.

### M2. `install_openclaw.sh` — indirect expansion with `set -u`
**File**: [server/install_openclaw.sh:9](server/install_openclaw.sh#L9)

```bash
local var_value="${!var_name}"
```
With `set -u`, accessing an unset var via indirect expansion errors before the friendly message prints.

**Fix**: `local var_value="${!var_name:-}"`.

### M3. `install_openclaw.sh` copies `_lib/.gitkeep` to server
`cp -r skills/* ~/.openclaw/skills/` includes the `_lib/.gitkeep` tracking file. Harmless; optional cleanup: `find ~/.openclaw/skills -name .gitkeep -delete`.

### M4. `server.sh` — inactive service reported as "unknown"
**File**: [server/skills/server/server.sh:38,46](server/skills/server/server.sh#L38)

When `systemctl is-active` exits non-zero (inactive), the script sets `"unknown"` instead of `"inactive ❌"`. Operator-facing clarity issue.

### M5. `handle_close` / `handle_update_status` trust `envelope["confirmed"]` blindly
Confirmation expiry is enforced by OpenClaw, not the skill. Stateless-by-design per research R6, so this is intended — but worth noting in the deploy verification plan: if OpenClaw's confirmation TTL is misconfigured, stale confirmations could slip through.

### M6. `email.py` duplicates weekly-summary building logic
**File**: [server/skills/email/email.py:122-137](server/skills/email/email.py#L122-L137)

Duplicates `heartbeat/weekly_summary.py`'s `build_weekly`. The T016 prompt explicitly forbade importing from other skills to keep them independent, so this is acceptable DRY-violation.

### M7. Workorders SKILL.md uses YAML list form for `requiresConfirmation`
Frontmatter uses:
```yaml
requiresConfirmation:
  - close
  - update_status
```
Both block and flow list forms are valid YAML. Should parse identically in OpenClaw. No action unless OpenClaw turns out to be picky.

---

## ✅ What's correct

- Directory tree, `.gitkeep` scaffolding, SKILL.md frontmatter
- `openclaw.json.template` — matches data-model E1 exactly
- `openclaw.service` — correct systemd ordering, restart policy, user isolation
- `envelope.py` — status/outcome validation, single-line JSON output, duration timing
- `authz.py` — minimal and correct
- `workorders.py` happy paths (`list_open/pending/overdue`, `count`, `get`, `summary_closed_in_range`)
- `close` confirmation flow — correctly returns `needs_confirmation` first, executes when confirmed
- `daily_digest.py` / `weekly_summary.py` — correct API calls, counts, Markdown shape
- `push_failure_check.py` — correct graceful degradation on 404/501
- `email.py` — correct email regex, 404/501 graceful handling
- `install_openclaw.sh` — idempotency, env gating, systemd install, journal tail

---

## Recommended fix order before deploying

| # | Severity | Fix | Effort |
|---|---|---|---|
| 1 | 🔴 C1 | `api_put` — use `method="PUT"` kwarg | 1 line |
| 2 | 🔴 C2 | `server.sh` emit_reply → `jq -nc --arg` | ~10 lines |
| 3 | 🔴 C3 | Parse `lines` from JSON, not `$ARGS` | 2 lines |
| 4 | 🔴 C4 | Add `"error"` to 3-tuple return | 1 line |
| 5 | 🟠 D1 | `iso_now()` → `.astimezone()`; digest "today" local | 2 lines |
| 6 | 🟠 D2 | Verify OpenClaw writes audit.log; add fallback if not | Verify; maybe ~20 lines |
| 7 | 🟠 D3 | Confirm and unify email endpoint path | 1 line after confirmation |
| 8 | 🟡 M1–M7 | Polish | optional |

**Do not run quickstart tests until C1–C4 are fixed.** C1 crashes `update_status`; C2 breaks every `server` skill response; C3 breaks the `errors` action's `lines` argument; C4 swallows the validation message. D1 is trivially cheap and worth doing in the same pass.
