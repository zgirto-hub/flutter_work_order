# Data Model: 027-ai-document-expert

**Date**: 2026-04-06

## Entities

No new database entities. This feature is entirely ephemeral — AI requests and responses exist only in memory during the editing session.

## Request/Response Structures

### DocumentExpertRequest (Backend)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| action | enum(improve, correct, generate, translate, concise, elaborate) | Yes | Which AI action to perform |
| html_content | string | No (required for improve/correct/translate) | The HTML content from the editor |
| target_language | enum(ar, en) | Yes | Desired output language |
| instructions | string | No | Optional free-text user instructions |

### DocumentExpertResponse (Backend)

| Field | Type | Description |
|-------|------|-------------|
| html_content | string | The AI-generated HTML content |

### HealthCheckResponse (Backend)

| Field | Type | Description |
|-------|------|-------------|
| available | boolean | Whether Ollama is reachable and responsive |

## State Transitions

### AI Panel State

```
Collapsed → Expanded (user clicks toggle)
  → Checking (health check fires)
    → Ready (Ollama available)
    → Unavailable (Ollama 503/timeout)

Ready → Processing (user triggers action)
  → Result (AI returns HTML)
    → Applied (user clicks Apply → editor updated)
    → Discarded (user dismisses or triggers new action)
  → Error (AI request failed)
    → Ready (user can retry)

Processing → Cancelled (user triggers new action while pending)
```

## Validation Rules

- `action=improve|correct|translate|concise|elaborate` requires non-empty `html_content`
- `action=generate` allows empty `html_content` (uses `instructions` as primary input)
- `target_language` defaults to `ar` if not specified
- `instructions` max length: 1000 characters
