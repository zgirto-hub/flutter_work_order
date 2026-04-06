# Data Model: Voice-to-Work-Order Dictation

**Branch**: `022-voice-work-order` | **Date**: 2026-04-06

## Overview

This feature introduces **no new data entities, database tables, or backend models**. Speech-to-text is a client-side UI input method — the transcribed text flows into existing `title` and `description` fields on the `work_orders` table via existing create/update API endpoints.

## Affected Existing Entities

### WorkOrder (unchanged)

The following existing fields receive dictated text input:

| Field         | Type   | Source          | Notes                                    |
|---------------|--------|-----------------|------------------------------------------|
| `title`       | String | `clientController` in `AddWorkOrderScreen` | Mic button appends dictated text |
| `description` | String | `descriptionController` in `AddWorkOrderScreen` | Mic button appends dictated text |

No schema changes. No migrations required.

## New Client-Side State (in-memory only)

### DictationService State

| Property           | Type     | Description                                      |
|--------------------|----------|--------------------------------------------------|
| `isAvailable`      | bool     | Whether speech recognition is supported on device |
| `isListening`      | bool     | Whether actively recording/transcribing           |
| `currentLocaleId`  | String   | Active locale (`en-US` or `ar-SA`)               |
| `lastError`        | String?  | Last error message from speech engine             |

### DictationButton State

| Property           | Type                   | Description                                      |
|--------------------|------------------------|--------------------------------------------------|
| `isRecording`      | bool                   | Visual state for the mic button                  |
| `targetController`  | TextEditingController  | The text field this button appends to            |
| `language`         | String                 | `en` or `ar` — determines locale for recognition |

All state is ephemeral (in-memory). Nothing is persisted beyond the text that ends up in the work order fields.

## State Transitions

```
DictationButton States:
  [Idle] --tap mic--> [Recording] --tap mic / silence timeout / error--> [Idle]
  [Idle] --speech unavailable--> [Hidden/Disabled]
```

No complex state machine. Two states: idle and recording.
