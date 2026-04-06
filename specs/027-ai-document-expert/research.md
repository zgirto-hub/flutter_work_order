# Research: 027-ai-document-expert

**Date**: 2026-04-06

## Decision 1: Backend Endpoint Pattern

**Decision**: Follow the existing ai_assist.py pattern — add a new `POST /ai/document-expert` endpoint in the same router file with a new Pydantic request model.

**Rationale**: The project already has two AI endpoints (`/ai/suggest`, `/ai/parse-work-order`) in `backend/routers/ai_assist.py` using identical Ollama calling patterns (httpx, `stream: false`, same error handling). Adding to the same file maintains consistency and reuses the existing `OLLAMA_URL`, `OLLAMA_MODEL`, and `OLLAMA_TIMEOUT` constants.

**Alternatives considered**:
- Separate router file (`ai_document.py`): Rejected — adds routing complexity for a single endpoint that shares all infrastructure with existing AI endpoints.
- Generic `/ai/generate` endpoint with action parameter: Rejected — conflates different prompt strategies; dedicated endpoint is clearer.

## Decision 2: Request/Response Model

**Decision**: New `DocumentExpertRequest` with fields: `action` (enum: improve/correct/generate/translate), `html_content` (string, the editor body), `target_language` (enum: ar/en), `instructions` (optional string). Response: `{"html_content": "<generated HTML>"}`.

**Rationale**: Mirrors the existing `AiSuggestRequest`/`AiParseWorkOrderRequest` pattern. The `action` field drives prompt selection server-side. HTML in/out matches the clarified requirement (FR-016).

**Alternatives considered**:
- Separate endpoints per action: Rejected — four endpoints for the same Ollama call with different prompts is excessive.
- Plain text in/out with frontend HTML conversion: Rejected — loses formatting; clarification confirmed HTML output.

## Decision 3: Ollama Health Check

**Decision**: Add a lightweight `GET /ai/health` endpoint that pings Ollama's `/api/tags` endpoint (fast, no model loading). Frontend calls this once on panel expand and caches the result.

**Rationale**: No health check currently exists (errors only surface after a failed request). The spec requires pre-flight availability detection (FR-017). Ollama's `/api/tags` is a fast metadata endpoint that confirms the service is running without triggering inference.

**Alternatives considered**:
- Frontend directly pings Ollama: Rejected — CORS issues, exposes internal infrastructure.
- Check on every button press: Rejected — adds latency to every action; clarification chose panel-expand check.

## Decision 4: postMessage Integration

**Decision**: Reuse the existing `GET_HTML` / `SET_HTML` postMessage protocol from `letter_form_tab_v2.dart`. The AI widget calls `GET_HTML` to extract current content, sends it to the backend, and uses a new `SET_HTML:<html>` message to apply the result.

**Rationale**: The iframe editor already supports `GET_HTML` (returns `EDITOR_HTML:<content>`) and sets content via `SET_HTML`. No changes to the editor iframe HTML needed.

**Alternatives considered**:
- New postMessage commands: Rejected — existing protocol covers all needs.
- Direct DOM manipulation: Rejected — breaks iframe isolation.

## Decision 5: Prompt Strategy

**Decision**: Four prompt variants mapped to the `action` enum, all sharing a base system prompt establishing the "Kuwaiti government civil aviation correspondence expert" persona. Each action adds specific instructions. All prompts enforce: return only the document HTML, no preamble, no explanation.

**Rationale**: Matches the spec's action taxonomy. The shared base prompt ensures consistent voice across all actions. The "HTML only" constraint prevents Ollama from wrapping output in markdown code blocks or explanatory text.

**Alternatives considered**:
- Single generic prompt with action as parameter: Rejected — prompt quality degrades when instructions are too broad; specialized prompts produce better results.
