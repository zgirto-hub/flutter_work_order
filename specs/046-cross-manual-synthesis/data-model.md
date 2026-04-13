# Data Model: Cross-Manual Synthesis (Layer 4)

**Date**: 2026-04-13 | **Branch**: `046-cross-manual-synthesis`

## Overview

No database schema changes. All new entities are transient (in-memory only during request processing). The feature adds new optional fields to the existing API response format.

## Transient Entities

### SubAnswer

Intermediate result from generating an answer scoped to one manual's chunks.

| Field | Type | Description |
|-------|------|-------------|
| manual_id | string (UUID) | ID of the source manual |
| manual_title | string | Display title of the source manual |
| answer | string | Generated answer text from this manual's content |
| chunks | list[dict] | Qualifying chunks used to generate this answer |
| grounded | bool | Whether the answer is grounded (not "not found" sentinel) |

**Lifecycle**: Created during sub-answer generation, consumed by synthesis, discarded after response is sent.

### SynthesisResult

Final merged answer combining all sub-answers.

| Field | Type | Description |
|-------|------|-------------|
| answer | string | Synthesized answer text with attribution and conflict markers |
| synthesized | bool | True if multiple sub-answers were combined; false if single pass-through |
| manuals_consulted | list[dict] | List of {id, title} for each contributing manual |
| has_conflicts | bool | True if "⚠ CONFLICT:" marker detected in answer |

**Lifecycle**: Created during synthesis, fields mapped into API response, then discarded.

## API Response Changes (Additive)

### Existing fields (unchanged)

| Field | Type | Present in |
|-------|------|-----------|
| answer | string | All responses |
| grounded | bool | All responses |
| sources | list[SourceObj] | All responses |
| model | string | All responses |
| duration_seconds | float | All responses |
| session_summary | string? | All responses |

### New fields (cross-manual only)

| Field | Type | Present in | Default |
|-------|------|-----------|---------|
| manuals_consulted | list[{id, title}] | Cross-manual responses only | absent |
| has_conflicts | bool | Cross-manual responses only | absent |

**Backward compatibility**: New fields are absent from single-manual responses. Frontend must handle their absence gracefully (null/empty defaults).

## Flutter Model Changes

### ManualQaAnswer (updated)

| Field | Dart Type | JSON Key | Default |
|-------|-----------|----------|---------|
| manualsConsulted | List\<ManualConsulted\> | manuals_consulted | [] |
| hasConflicts | bool | has_conflicts | false |

### ManualConsulted (new inline class)

| Field | Dart Type | JSON Key |
|-------|-----------|----------|
| id | String | id |
| title | String | title |
