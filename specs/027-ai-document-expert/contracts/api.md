# API Contract: 027-ai-document-expert

## POST /api/ai/document-expert

Process document content through the AI expert.

**Request**:
```json
{
  "action": "improve" | "correct" | "generate" | "translate" | "concise" | "elaborate",
  "html_content": "<p>محتوى الرسالة</p>",
  "target_language": "ar" | "en",
  "instructions": "اجعل النص أكثر رسمية"
}
```

**Response 200**:
```json
{
  "html_content": "<p>محتوى الرسالة المحسّن</p>"
}
```

**Response 503** (Ollama unavailable):
```json
{
  "detail": "AI service is currently unavailable"
}
```

**Response 502** (Ollama error):
```json
{
  "detail": "AI model error"
}
```

**Response 422** (validation):
```json
{
  "detail": "html_content is required for improve/correct/translate actions"
}
```

---

## GET /api/ai/health

Check Ollama service availability.

**Response 200**:
```json
{
  "available": true
}
```

**Response 200** (Ollama down):
```json
{
  "available": false
}
```
