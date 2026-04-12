# Contracts: HyDE Retrieval

No contract changes. The `POST /manuals/ask` endpoint request and response schemas remain identical. HyDE is an internal pipeline optimization invisible to API consumers.

## Existing Contract (unchanged)

**Request**: `AskRequest` — `question`, `manual_id`, `user_email`, `model`, `history`
**Response**: `{ answer, grounded, sources, model, duration_seconds }`

The only observable difference is potentially improved retrieval quality for vague questions and a slight increase in `duration_seconds` due to the HyDE generation step.
