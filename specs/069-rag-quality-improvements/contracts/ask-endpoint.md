# Contract: POST /api/manuals/ask — Validated QA Path

**Branch**: `069-rag-quality-improvements` | **Date**: 2026-04-16

## Endpoint

`POST /api/manuals/ask`

No changes to the request shape. Response shape is extended with additive fields.

## Request (unchanged)

```json
{
  "question": "string (required, max 2000 chars)",
  "manual_id": "string (optional UUID)",
  "user_email": "string (optional)",
  "model": "string (optional)",
  "history": "array (optional)",
  "session_summary": "string (optional)"
}
```

## Response — Validated QA Hit (threshold passed, LLM called)

```json
{
  "answer": "string — LLM-generated answer from validated QA context",
  "grounded": true,
  "sources": [
    {
      "id": "uuid",
      "question_text": "string",
      "score": 0.89
    }
  ],
  "confidence": "high",
  "score": 0.89,
  "is_verified": true,
  "verified_source": {
    "validated_qa_id": "uuid",
    "validated_by": "string",
    "validated_at": "iso8601",
    "similarity": 0.89
  },
  "retrieval_info": { "..." : "..." },
  "latency_breakdown": { "..." : "..." }
}
```

## Response — Below Threshold (no LLM call)

```json
{
  "answer": "I don't have reliable information on this topic in the knowledge base. You may want to submit this as a new question for admin review.",
  "sources": [],
  "confidence": "low",
  "score": 0.45,
  "grounded": false,
  "retrieval_info": { "..." : "..." }
}
```

## Response — Existing Paths (manual-chunks, greeting bypass, etc.)

Unchanged. The `confidence`, `score` fields are only added to the validated_qa path responses.

## Confidence Mapping

| Confidence | Score Range | LLM Called |
|------------|-------------|------------|
| high       | >= 0.85     | Yes        |
| medium     | >= 0.70     | Yes        |
| low        | < 0.70      | No         |

## Backward Compatibility

- `answer` field: unchanged position and format
- `sources` field: already exists (was `[]` for validated_qa hits); now populated with qa entries
- `confidence`, `score`: new additive fields — frontend ignores unknown fields
- Existing manual-chunks path: completely unchanged
