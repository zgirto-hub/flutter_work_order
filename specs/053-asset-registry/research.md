# Research: Asset Registry (053)

**Date**: 2026-04-14 | **Branch**: `053-asset-registry`

## R1: Dynamic Prompt Construction Pattern

**Decision**: Build the domain knowledge block as a formatted string at extraction time by querying `assets` + `asset_system_links` tables, then inject it into the prompt template via string replacement.

**Rationale**: The current `EXTRACTION_PROMPT` in `entity_extractor.py` (main branch) has a hardcoded `DOMAIN KNOWLEDGE` section listing 6 systems and their components. This works but requires code changes whenever infrastructure changes. A dynamic approach queries the registry, formats a text block like:
```
DOMAIN KNOWLEDGE — Known assets and systems (from registry):
- WS-01 (workstation, ACC Tower - Room 3): CADAS-ATS [client], CADAS-IMS [client]
- SRV-CADAS-01 (server, Server Room A): CADAS-ATS [primary]
...
```
This block replaces the `{{domain_knowledge}}` placeholder in the prompt template.

**Alternatives considered**:
- **Cache at startup**: Pre-load registry at service startup and rebuild on change. Rejected — adds complexity; registry changes are infrequent, and querying 200 assets is fast (~50ms).
- **Separate LLM call**: Ask the model to look up assets. Rejected — doubles inference cost and latency.
- **Embedding-based retrieval**: Embed asset descriptions and retrieve relevant ones per work order. Rejected — overkill for <200 assets; full list fits easily in prompt context.

## R2: Extraction Prompt Template Design

**Decision**: Split the prompt into a static template (instructions, field definitions, examples) with a `{{domain_knowledge}}` placeholder. The dynamic block is inserted at runtime. If the registry is empty, a minimal fallback block is used: "No assets registered. Extract equipment information from text context only."

**Rationale**: Keeps the prompt structure clean and testable. The fallback ensures extraction never fails due to empty registry.

**Alternatives considered**:
- **Full prompt regeneration**: Rebuild entire prompt from scratch each time. Rejected — harder to maintain; static parts (field definitions, examples) rarely change.

## R3: Server-Side Role Enforcement (Primary/Standby Uniqueness)

**Decision**: Enforce at the database level via a partial unique index: `CREATE UNIQUE INDEX ON asset_system_links(system, role) WHERE role IN ('primary', 'standby')`. The backend also checks before insert and returns a descriptive 409 error identifying the existing holder.

**Rationale**: Database constraint provides defense-in-depth. Backend check provides a user-friendly error message. Client role is not enforced (no need for constraint on "client" role since multiple workstations can be clients of the same system).

**Alternatives considered**:
- **Frontend-only validation**: Check before submit. Rejected — race condition possible with multiple admins.
- **Database-only constraint**: Rely on DB error. Rejected — error message would be cryptic without backend translation.

## R4: Pattern Alert Enrichment Approach

**Decision**: When the pattern engine creates an alert (in `_create_alert`), look up the `equipment_id` in the `assets` table by name match. If found, add `asset_context` to the alert record: `{"location": "...", "type": "...", "systems": [...]}`. The frontend `AlertCard` displays this context when present.

**Rationale**: Enrichment at alert creation time (not display time) means the context is captured once and persists even if the asset is later modified or deleted. This matches the existing alert data pattern where `message` is pre-formatted.

**Alternatives considered**:
- **Display-time enrichment**: Frontend queries registry when rendering alert. Rejected — adds API calls per alert render; stale if asset deleted.
- **Inline in message string**: Append asset context to the `message` field. Rejected — harder to style/filter in UI; mixes data with presentation.

## R5: Admin Screen UX Pattern

**Decision**: Two screens: `AssetRegistryScreen` (list with filter/search) and `AssetEditScreen` (add/edit form with inline system association management). System links are managed as a sub-list within the edit screen, not a separate screen.

**Rationale**: Follows the existing `RulesTab` → `RuleEditScreen` pattern from the manual assistant. System associations are tightly coupled to the asset and are few per asset (typically 1-5), so inline management is simpler than a separate screen.

**Alternatives considered**:
- **Single screen with bottom sheets**: Use modals for add/edit. Rejected — form has enough fields (name, type, location, notes + system links) that a full screen is warranted.
- **Three screens (list, detail, link manager)**: Separate system link management. Rejected — unnecessary navigation; YAGNI.

## R6: System Name Management

**Decision**: System names are stored as plain strings in `asset_system_links.system`. A set of known systems (CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV) is seeded in the migration and also hardcoded as suggestions in the frontend dropdown. Admins can type a custom system name if needed.

**Rationale**: No separate `systems` table needed (YAGNI). The 6 known systems cover current infrastructure. Free-text entry with suggestions provides extensibility without a management screen. A future refactor (noted in spec) may unify system names into a shared table with the System Status screen.

**Alternatives considered**:
- **Separate `systems` table**: Full CRUD for systems. Rejected — out of scope per clarification; adds a third entity and management UI for minimal benefit.
- **Enum/check constraint**: Restrict to known systems only. Rejected — too rigid; new systems would require a migration.
