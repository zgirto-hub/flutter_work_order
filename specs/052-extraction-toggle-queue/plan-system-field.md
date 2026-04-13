# Add `system` Field to Entity Extraction Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `system` column to entity extraction so pattern rules can group issues by parent system (CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV) across all their components (workstations, servers, switches, cameras, etc.)

**Architecture:** The `system` field flows through: extraction prompt (Gemma fills it) -> `work_order_entities.system` column (stored) -> pattern engine (groupable) -> alert card (displayed). The extraction prompt is enhanced with Kuwait DGCA domain knowledge so Gemma understands the relationship between systems and their components.

**Tech Stack:** Python 3.10 / FastAPI (backend), Dart 3.x / Flutter 3.x (frontend), Supabase PostgreSQL

---

## Domain Knowledge

These are the known systems and components at Kuwait DGCA:

| System | Components |
|---|---|
| **CADAS-ATS** | Workstations, Servers, Switches |
| **CADAS-IMS** | Workstations, Servers, Switches |
| **AIDA-NG** | Workstations, Servers, Switches, International Circuits |
| **INDRA CCTV** | Workstations, Bosch Cameras (x10), Media Converters (fiber-to-LAN), Power Adapters, Switches |
| **MUX** | Multiplexer / AFTN messaging hardware |
| **AFTN** | Aeronautical Fixed Telecommunication Network |

A single work order may reference a system by name ("CADAS-ATS mailbox") or by component ("Camera 5 offline"). The extraction prompt must map both to the correct `system` value.

---

## File Structure

```text
# Modified files:
backend/services/entity_extractor.py         # Updated prompt + payload with system field
backend/services/pattern_engine.py            # Add system to alert creation, enable system grouping
backend/routers/patterns.py                   # Pass system through alert endpoints
frontend/lib/models/pattern_alert.dart        # Add system field to model
frontend/lib/screens/manual_assistant/widgets/alert_card.dart  # Display system chip

# Database:
supabase/migrations/20260413100000_create_entity_extraction.sql  # Reference only (already applied)
# Migration applied via Supabase SQL: ALTER TABLE work_order_entities ADD COLUMN system TEXT
# (already done — column exists)
```

No new files are created. This is a field addition threading through the existing pipeline.

---

### Task 1: Update Extraction Prompt with Domain Knowledge

**Files:**
- Modify: `backend/services/entity_extractor.py:17-38` (the `EXTRACTION_PROMPT` constant)

- [ ] **Step 1: Replace the EXTRACTION_PROMPT constant**

Replace the entire `EXTRACTION_PROMPT` string (lines 17-38) with this updated version that adds domain knowledge and the `system` field:

```python
EXTRACTION_PROMPT = """You are an expert at extracting structured information from work order descriptions at Kuwait DGCA (Civil Aviation).

The input text may be in Arabic, English, or mixed. You MUST output all field values in English regardless of input language.

DOMAIN KNOWLEDGE — Known systems and their components:
- CADAS-ATS: Air Traffic Services system. Components: workstations, servers, switches.
- CADAS-IMS: Information Management System. Components: workstations, servers, switches.
- AIDA-NG: Aeronautical Information system. Components: workstations, servers, switches, international circuits.
- INDRA CCTV: Surveillance system. Components: workstations, Bosch cameras, media converters (fiber to LAN), power adapters, switches.
- MUX: Multiplexer / AFTN messaging system.
- AFTN: Aeronautical Fixed Telecommunication Network.

When a work order mentions any of these systems or their components, use the system name for the "system" field and identify the specific component as "equipment_id". For example, "CADAS-ATS mailbox" -> system="CADAS-ATS", equipment_id="CADAS-ATS mailbox server". "Camera 3 media converter" -> system="INDRA CCTV", equipment_id="Camera 3 media converter".

Extract the following fields from the work order text below. Return a JSON object with these exact field names:
- system (optional string — the parent system name: "CADAS-ATS", "CADAS-IMS", "AIDA-NG", "INDRA CCTV", "MUX", "AFTN", or other system if identifiable)
- equipment_id (required, non-empty string — the specific equipment, component, asset tag, or device name)
- equipment_type (optional string — type of component: "workstation", "server", "switch", "camera", "media converter", "power adapter", "generator", "pump", etc.)
- fault_type (optional string — the category of fault: "mechanical", "electrical", "network", "software", "performance", "malfunction", "plumbing", "structural", etc.)
- fault_code (optional string — any fault/error code mentioned in the text)
- action_taken (optional string — what was done to address the issue)
- procedure_followed (optional string — any standard procedure or reference followed)
- parts_replaced (optional JSON array of strings — list of parts that were replaced)
- outcome (optional string — result of the work: "resolved", "pending parts", "escalated", "monitoring", etc.)
- technician_id (optional string — ID or name of the technician who performed the work)
- date (optional string — date of the work or service)

Example 1:
Input: "صيانة مولد كهربائي رقم G-102. تم تغيير بلف الضغط. الفني: أحمد. النتيجة: تم الإصلاح."
Output: {{"system": "", "equipment_id": "G-102", "equipment_type": "generator", "fault_type": "mechanical", "fault_code": "", "action_taken": "replaced pressure valve", "procedure_followed": "", "parts_replaced": ["pressure valve"], "outcome": "resolved", "technician_id": "Ahmed", "date": ""}}

Example 2:
Input: "CADAS-ATS workstation in room S-65 not responding. Restarted the workstation and verified connectivity."
Output: {{"system": "CADAS-ATS", "equipment_id": "CADAS-ATS workstation S-65", "equipment_type": "workstation", "fault_type": "software", "fault_code": "", "action_taken": "restarted workstation and verified connectivity", "procedure_followed": "", "parts_replaced": [], "outcome": "resolved", "technician_id": "", "date": ""}}

Example 3:
Input: "Camera 5 offline. Replaced media converter and power adapter. Camera back online."
Output: {{"system": "INDRA CCTV", "equipment_id": "Camera 5", "equipment_type": "camera", "fault_type": "network", "fault_code": "", "action_taken": "replaced media converter and power adapter", "procedure_followed": "", "parts_replaced": ["media converter", "power adapter"], "outcome": "resolved", "technician_id": "", "date": ""}}

Example 4:
Input: "Daily routine for clearing CADAS-ATS mailboxes at KCMC."
Output: {{"system": "CADAS-ATS", "equipment_id": "CADAS-ATS mailbox server", "equipment_type": "server", "fault_type": "", "fault_code": "", "action_taken": "cleared mailboxes", "procedure_followed": "daily routine", "parts_replaced": [], "outcome": "resolved", "technician_id": "", "date": ""}}

Input: {{work_order_text}}
Output ONLY the JSON object. No other text."""
```

- [ ] **Step 2: Update the payload in `extract_entities()` to include `system`**

In the same file, find the `payload` dict (around line 162) and add the `system` field after `work_order_id`:

```python
        payload = {
            "work_order_id": work_order_id,
            "system": parsed_data.get("system") or None,   # <-- ADD THIS LINE
            "equipment_id": parsed_data.get("equipment_id", ""),
            # ... rest unchanged
        }
```

- [ ] **Step 3: Commit**

```bash
git add backend/services/entity_extractor.py
git commit -m "feat(extraction): add system field and DGCA domain knowledge to prompt"
```

---

### Task 2: Update Pattern Engine to Use `system` Field

**Files:**
- Modify: `backend/services/pattern_engine.py:129-139` (alert creation in `evaluate_patterns`)
- Modify: `backend/services/pattern_engine.py:199-209` (alert creation in `full_scan`)
- Modify: `backend/services/pattern_engine.py:444-468` (`_create_alert` function)

The pattern engine creates alerts and passes `equipment_id` and `fault_type`. We need to also pass `system` so alerts carry the system context. We also add `system` as a valid `target_field` for grouping in `_check_recurring_fault`.

- [ ] **Step 1: Add `system` parameter to `_create_alert`**

Find the `_create_alert` function (line 444). Add `system: Optional[str]` parameter and include it in the insert payload:

```python
async def _create_alert(
    rule_id: str,
    work_order_ids: list[str],
    system: Optional[str],          # <-- ADD
    equipment_id: Optional[str],
    fault_type: Optional[str],
    technician_id: Optional[str],
    severity: str,
    message: str,
    dedup_key: Optional[str],
) -> None:
    """Create a new pattern alert."""
    try:
        supabase.table("pattern_alerts").insert(
            {
                "rule_id": rule_id,
                "work_order_ids": work_order_ids,
                "system": system,               # <-- ADD
                "equipment_id": equipment_id,
                "fault_type": fault_type,
                "technician_id": technician_id,
                "severity": severity,
                "status": "new",
                "message": message,
                "dedup_key": dedup_key,
            }
        ).execute()
    except Exception as e:
        logger.warning(f"[pattern_engine] Failed to create alert: {e}")
```

- [ ] **Step 2: Update both call sites to pass `system`**

In `evaluate_patterns()` (around line 130), add `system=entity.get("system")`:

```python
            if match["matched"]:
                await _create_alert(
                    rule_id=rule["id"],
                    work_order_ids=[work_order_id],
                    system=entity.get("system"),       # <-- ADD
                    equipment_id=entity.get("equipment_id"),
                    fault_type=entity.get("fault_type"),
                    technician_id=entity.get("technician_id"),
                    severity=rule["severity"],
                    message=match["message"],
                    dedup_key=None,
                )
```

In `full_scan()` (around line 199), same change:

```python
                await _create_alert(
                    rule_id=rule_id,
                    work_order_ids=[entity["work_order_id"]],
                    system=entity.get("system"),       # <-- ADD
                    equipment_id=entity.get("equipment_id"),
                    fault_type=entity.get("fault_type"),
                    technician_id=entity.get("technician_id"),
                    severity=rule["severity"],
                    message=match["message"],
                    dedup_key=dedup_key,
                )
```

- [ ] **Step 3: Add `system` column to `pattern_alerts` table**

Run this SQL on Supabase (the `work_order_entities.system` column was already added):

```sql
ALTER TABLE pattern_alerts ADD COLUMN IF NOT EXISTS system TEXT;
```

- [ ] **Step 4: Commit**

```bash
git add backend/services/pattern_engine.py
git commit -m "feat(patterns): thread system field through alert creation"
```

---

### Task 3: Expose `system` in Alert API Response

**Files:**
- Modify: `backend/routers/patterns.py:286-326` (list_alerts endpoint)
- Modify: `backend/routers/patterns.py:329-407` (update_alert_status endpoint)

No code changes needed here — both endpoints already return `SELECT *` from `pattern_alerts`, so the new `system` column is automatically included in the response JSON. Verify by checking that the endpoints use `supabase.table("pattern_alerts").select("*")`.

- [ ] **Step 1: Verify list_alerts returns system (no code change needed)**

Confirm line 297 uses `.select("*", count="exact")` — this already returns all columns including the new `system` column.

- [ ] **Step 2: Verify update_alert_status returns system (no code change needed)**

Confirm line 384-388 uses `.update(...)` which returns the updated row with all columns.

- [ ] **Step 3: Move on — no commit needed for this task**

---

### Task 4: Add `system` to Flutter Alert Model

**Files:**
- Modify: `frontend/lib/models/pattern_alert.dart`

- [ ] **Step 1: Add `system` field to PatternAlert class**

Add `final String? system;` to the field list (after `technicianId`, line 8):

```dart
class PatternAlert {
  final String id;
  final String ruleId;
  final String? ruleName;
  final List<String> workOrderIds;
  final String? equipmentId;
  final String? faultType;
  final String? technicianId;
  final String? system;           // <-- ADD
  final String severity;
  // ... rest unchanged
```

Add it to the constructor:

```dart
  PatternAlert({
    required this.id,
    required this.ruleId,
    this.ruleName,
    required this.workOrderIds,
    this.equipmentId,
    this.faultType,
    this.technicianId,
    this.system,                  // <-- ADD
    required this.severity,
    // ... rest unchanged
```

Add it to `fromJson`:

```dart
      technicianId: json['technician_id'] as String?,
      system: json['system'] as String?,           // <-- ADD
      severity: json['severity'] as String,
```

Add it to `toJson`:

```dart
      'technician_id': technicianId,
      'system': system,                            // <-- ADD
      'severity': severity,
```

Add it to `copyWith` (parameter and body):

```dart
    String? system,           // <-- ADD parameter
```

```dart
      system: system ?? this.system,               // <-- ADD in body
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/pattern_alert.dart
git commit -m "feat(alerts): add system field to PatternAlert model"
```

---

### Task 5: Display `system` Chip on Alert Card

**Files:**
- Modify: `frontend/lib/screens/manual_assistant/widgets/alert_card.dart:135-161`

- [ ] **Step 1: Add system chip to the Wrap widget**

Find the `Wrap` widget that shows `equipmentId` and `faultType` chips (line 135). Update the condition and add the system chip:

```dart
            if (alert.equipmentId != null ||
                alert.faultType != null ||
                alert.system != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (alert.system != null)
                    Chip(
                      avatar: const Icon(Icons.dns, size: 14),
                      label: Text(
                        alert.system!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (alert.equipmentId != null)
                    Chip(
                      label: Text(
                        alert.equipmentId!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (alert.faultType != null)
                    Chip(
                      label: Text(
                        alert.faultType!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/screens/manual_assistant/widgets/alert_card.dart
git commit -m "feat(alerts): display system chip on alert cards"
```

---

### Task 6: Update Migration File for Completeness

**Files:**
- Modify: `supabase/migrations/20260413100000_create_entity_extraction.sql`

The `system` column was already added via live SQL. Update the migration file so future fresh deployments include it.

- [ ] **Step 1: Add `system` column to the CREATE TABLE statement**

Find line 4 in the migration file and add `system text,` after `equipment_id text NOT NULL,`:

```sql
CREATE TABLE work_order_entities (
  work_order_id uuid PRIMARY KEY REFERENCES work_orders(id) ON DELETE CASCADE,
  equipment_id text NOT NULL,
  system text,                    -- parent system: CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV, etc.
  equipment_type text,
  -- ... rest unchanged
```

Also add `system text,` to the `pattern_alerts` table in `supabase/migrations/20260413200000_create_pattern_engine.sql`, after `equipment_id text,`:

```sql
    equipment_id text,
    system text,                  -- parent system name
    fault_type text,
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260413100000_create_entity_extraction.sql supabase/migrations/20260413200000_create_pattern_engine.sql
git commit -m "chore(migrations): add system column to entity and alert tables"
```

---

### Task 7: Deploy and Validate End-to-End

- [ ] **Step 1: Push to main and update server**

```bash
git push
ssh zorin@100.85.73.37 "cd ~/Development/flutter_work_order && git pull && sudo systemctl restart document_server.service"
```

- [ ] **Step 2: Deploy frontend (no version bump)**

```bash
bash scripts/deploy_frontend.sh --no-bump
```

- [ ] **Step 3: Test extraction with a real work order**

Create a WO with description: "CADAS-ATS workstation in room S-65 not responding. Restarted and verified."

Check the `work_order_entities` table — expect:
- `system` = "CADAS-ATS"
- `equipment_id` = "CADAS-ATS workstation S-65"
- `equipment_type` = "workstation"

- [ ] **Step 4: Test pattern scan**

Trigger a scan via: `POST /api/patterns/scan?user_email=salah@admin.com`

Check the Alerts tab — new alerts should show the system chip (e.g., "CADAS-ATS") alongside equipment and fault chips.

- [ ] **Step 5: Test with INDRA CCTV work order**

Create a WO: "Camera 5 offline at KCMC. Replaced media converter. Camera back online."

Expected extraction:
- `system` = "INDRA CCTV"
- `equipment_id` = "Camera 5"
- `equipment_type` = "camera"
- `parts_replaced` = ["media converter"]

---

## Execution Order

```
Task 1 (prompt + payload)
  |
Task 2 (pattern engine) -- can run in parallel with Task 1 since different files
  |
Task 3 (verify API -- no changes needed)
  |
Task 4 (Flutter model) -- can run in parallel with Tasks 1-3 since different layer
  |
Task 5 (alert card UI) -- depends on Task 4
  |
Task 6 (migration files) -- independent, can run anytime
  |
Task 7 (deploy + validate) -- depends on all above
```
