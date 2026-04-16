# API Contracts: 076 — Default Q&A Generation to Gemini Flash

**Date**: 2026-04-16

## No New Endpoints

This feature modifies no API contracts. All existing endpoints continue with identical request/response shapes.

## Behavioral Changes (non-breaking)

### POST /manuals/ask
- **Before**: Default generation provider is local Ollama
- **After**: Default generation provider is Gemini Flash
- **Response shape**: Unchanged. The `latency_breakdown` dict already includes `provider` field showing which provider was used.
- **Fallback**: If Gemini fails, falls back to Ollama transparently. Response includes `fallback_info` only in server-side audit logging — never exposed to client.

### POST /ai/provider
- **Before**: Default value when no row exists was `"local"`
- **After**: Default value when no row exists is `"gemini"`
- **No breaking change**: Endpoint behavior, request/response shapes unchanged.

### GET /ai/provider
- **Before**: Returns `"local"` when no DB row exists
- **After**: Returns `"gemini"` when no DB row exists
- **No breaking change**: Clients already handle any string provider key.
