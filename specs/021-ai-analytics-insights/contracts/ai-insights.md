# API Contract: AI Insights

**Feature**: 021-ai-analytics-insights  
**Date**: 2026-04-05

## POST /api/ai/insights

Generate an AI-powered operational insight from aggregated data.

### Authentication

Query parameters (following existing pattern from `work_orders.py`):
- `email` (string, required) — user's email address
- `user_role` (string, required) — must be "admin" or "supervisor"

### Request Body

```json
{
  "insight_type": "overview",
  "date_range_days": 30,
  "language": "en"
}
```

| Field | Type | Required | Default | Constraints |
|-------|------|----------|---------|-------------|
| insight_type | string | yes | — | "overview" \| "system_status" \| "trends" |
| date_range_days | integer | no | 30 | 1–365 |
| language | string | no | "en" | "en" \| "ar" |

### Response — 200 OK

```json
{
  "insight": "• Work order volume increased 15% this week with 47 new orders...\n• Technical department leads with 23 open orders...\n• AIDA-NG system reported 3 outages...",
  "generated_at": "2026-04-05T14:32:00Z",
  "data_summary": {
    "total_work_orders": 142,
    "pending": 23,
    "in_progress": 18,
    "closed": 101,
    "systems_down": 2,
    "date_range_days": 30
  }
}
```

### Response — Arabic Example (language: "ar")

```json
{
  "insight": "• ارتفع حجم أوامر العمل بنسبة 15% هذا الأسبوع مع 47 أمر عمل جديد...\n• يتصدر القسم الفني بـ 23 أمر عمل مفتوح...",
  "generated_at": "2026-04-05T14:32:00Z",
  "data_summary": {
    "total_work_orders": 142,
    "pending": 23,
    "in_progress": 18,
    "closed": 101,
    "systems_down": 2,
    "date_range_days": 30
  }
}
```

### Error Responses

| Status | Condition | Body |
|--------|-----------|------|
| 403 | User role is not admin or supervisor | `{"detail": "Admin or supervisor access required"}` |
| 422 | Invalid insight_type or date_range_days | `{"detail": "Invalid insight_type. Must be overview, system_status, or trends"}` |
| 422 | Insufficient data (< 5 work orders in range) | `{"detail": "Not enough data for meaningful analysis. Try a wider date range."}` |
| 502 | AI model returned empty or invalid response | `{"detail": "AI could not generate insights. Please try again."}` |
| 503 | Ollama service unreachable or timed out | `{"detail": "AI service is currently unavailable. Please try again later."}` |

### Timeout Behavior

- Backend Ollama call timeout: 60 seconds
- Frontend HTTP timeout: 65 seconds (5-second buffer)
- If Ollama times out, backend returns 503

### Preamble Stripping

The backend strips conversational preambles from the AI response before returning it. Stripped phrases include:

**English**: "Here", "Sure", "Of course", "Certainly", "Below", "I'd", "I would"  
**Arabic**: "بالتأكيد" (certainly), "إليك" (here is), "بالطبع" (of course), "حسناً" (okay)

### Example curl

```bash
curl -X POST "http://localhost:8000/api/ai/insights?email=admin@example.com&user_role=admin" \
  -H "Content-Type: application/json" \
  -d '{"insight_type": "overview", "date_range_days": 30, "language": "en"}'
```
