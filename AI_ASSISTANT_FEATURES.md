# AI Assistant — Full Feature Inventory

A reference document for sharing with Claude (or any LLM) so it has a complete
picture of what the AI assistant in this work-order app does, where each piece
lives, and how it is wired together.

Scope: the RAG-based Manual Assistant, the multi-provider AI layer, and every
satellite AI feature (WO description, NL search, entity extraction, pattern
rules, analytics, letter generation, dashboard cards, etc.).

Source of truth: code under `backend/services/` and `frontend/lib/`, plus the
numbered specs under `specs/` (020–086).

---

## 1. RAG Pipeline (Manual Assistant)

Core file: `backend/services/manual_rag_service.py` (~1,705 lines).

### 1.1 Retrieval stages
- **Dual-layer lookup** (specs 067, 069, 083): every query is checked against
  the curated `validated_qa` table *and* the document-chunk store.
- **Two validated-QA passes** (spec 069): one before query rewrite, one after,
  so rewrite cannot hide a direct hit.
- **Verbatim short-circuit** (spec 083): if top-1 validated-QA similarity
  ≥ 0.85 AND gap to #2 ≥ 0.05, the stored answer is returned verbatim — the
  LLM is never called. Logged in `user_activity_log`.
- **Synthesized verified answer**: when confidence is medium, top-3 matches are
  composed by the LLM using a dedicated `VALIDATED_QA_SYSTEM_PROMPT`.
- **HyDE** (spec 043, 077): hypothetical answer generated and embedded to
  improve vector recall. Skipped for direct lookups (IPs, hostnames, component
  IDs) via regex. Runs in parallel with rewrite via `asyncio.gather`.
- **Query rewrite** (spec 042, 045): history-aware rewrite using a compressed
  3–4 sentence session summary.
- **Diversity-aware retrieval** (spec 078):
  `backend/services/document_search_service.py`. Picks up to 8 documents with
  max 3 chunks each, balancing aggregate score against a diversity floor.
- **Cosine threshold** gate: `MAX_CHUNK_DISTANCE = 0.55`.
- **Contextual embeddings** (spec 075): chunks embedded with a document-aware
  prefix (`contextual_prefix.py`).

### 1.2 Generation stages
- **Streaming generator**: `ask_stream()` yields tokens via async generators
  (spec 079).
- **System prompts**:
  - `DOCUMENT_QA_SYSTEM_PROMPT` (~292 lines): safety rules, regulatory-ID
    preservation, Arabic support, conflict flagging.
  - `VALIDATED_QA_SYSTEM_PROMPT` (~209 lines): strict curated-QA path.
- **Stage latency breakdown** (spec 066): `LatencyBreakdown` dataclass tracks
  `embed_ms`, `hyde_ms`, `rewrite_ms`, `retrieval_ms`, `generator_ms`,
  `total_ms` per request.

### 1.3 Document preprocessing
- `backend/services/document_preprocessor.py` (~216 lines): smart page
  reconstruction on upload. Uses Gemini with Ollama fallback. Fixes terse
  extractions while preserving structure (spec 073).

---

## 2. Multi-Provider AI Layer

Directory: `backend/services/ai_providers/`.

- **Providers**: `OllamaProvider`, `GeminiProvider`, `MistralProvider`,
  `GroqProvider` (spec 063).
- **Resolver**: `ai_providers/resolver.py`. Reads the current provider from
  the `app_settings` table, 60-second cache, auto-migration of stale defaults
  (`gemini` → `local`, spec 076).
- **Fallback chain** (spec 065): primary provider failure triggers automatic
  fallback to Ollama with an audit entry in `user_activity_log`.
- **Health checks**: each provider implements `health_check()` on a common
  `BaseProvider`.
- **Timeouts**: 30 s generation, 20 s embeddings, 120 s preprocessing.
- **Custom exceptions**: `EmbedderTimeoutError`, `GeneratorTimeoutError`,
  `GeneratorModelError`.
- **Deliberate Ollama pinning**: HyDE and query-rewrite paths bypass the
  resolver and always use local Ollama (spec 076) for cost/latency reasons.

---

## 3. Validated / Verified Answers

File: `backend/services/validated_qa_service.py`.

- **Ratings ingest**: thumbs-up/down from users become training signal.
- **Auto-approve paraphrases** (spec 068): near-duplicate detection promotes
  paraphrases of validated answers without re-review. Shared `rating_id` by
  design (migration `20260415000000`).
- **Reflag threshold**: `REFLAG_THRESHOLD = 0.30` — answers below this ratio
  of positive ratings are re-queued for review.
- **Source attribution**: every synthesized answer lists `validated_qa_id`,
  validator email, and validation timestamp.
- **Confidence tiers**: high (≥ 0.85), medium (0.75–0.85), low (< 0.75).
- **Delete/undo** (spec 082): admins can delete validated entries with an
  undo window.
- **Verified-answer CRUD tab** in frontend Manual Assistant screen.

---

## 4. Work-Order AI Features

### 4.1 AI WO description (spec 020)
- Turns short free-text + selected department into a structured description
  via backend `/api/ai/wo-description`.

### 4.2 Voice input (spec 022)
- Frontend `speech_to_text` wrapper around Web Speech API. Dictation button
  shared across AI inputs.

### 4.3 Natural-language search (spec 023)
- Free-text → structured WO filter via backend.

### 4.4 Dashboard AI create card (spec 025)
- Dictate or type → draft WO → confirm before submit. No persistence until
  confirm.

### 4.5 Entity extraction (spec 049)
- `backend/services/entity_extractor.py` (~233 lines): equipment names, fault
  codes, asset references. Writes to `work_order_entities`, failures to
  `extraction_failures`.

### 4.6 Pattern rules engine (spec 051)
- `backend/services/pattern_engine.py` (~513 lines): rule matching over
  entities. Emits `pattern_alerts`. Admin UI tab under Manual Assistant.

### 4.7 Asset auto-suggest (spec 055)
- Surfaces likely assets in the WO form based on entities + history.

### 4.8 Extraction toggle & queue (spec 052)
- Global switch in `system_settings` to enable/disable extraction; a queue
  replays failed extractions.

### 4.9 Structured WO description (spec 054)
- Template-driven structured fields in the description.

---

## 5. Analytics & Insights

- **AI analytics insights** (spec 021): backend aggregates + LLM summary,
  surfaced in dashboard.
- **Cross-manual synthesis** (spec 046): multi-document retrieval for broad
  questions; single-pass generation (no sub-answer tree).
- **AI insights card** (`frontend/lib/widgets/ai_insights_card.dart`) and
  **NL input card** (`nl_input_card.dart`) — collapsible (spec 030).

---

## 6. Letter / Document Generation

- **Civil aviation letter gen** (spec 026): ReportLab + Arabic reshaping +
  bidi, stored in `generated_letters`.
- **AI document expert** (spec 027): assists with drafting letter bodies.
- **Cert ↔ letter linking** (spec 029): `payment_certificates.letter_id` FK
  with ordering via `letter_link_order`.
- **Barcode on letters** (spec 032): in-memory PNG via `python-barcode`.
- **Editor toolbar & image insert** (specs 033, 034): inline HTML editor with
  image upload to `backend/uploaded_files/letters/`.
- **Letters V2 UI refactor** (spec 035) and dead-code cleanup of V1
  (spec 036).
- **iOS PWA share** (spec 038): Web `navigator.share` + Blob download for
  generated PDFs.

---

## 7. Knowledge Management / Train-AI Tab

Screen: `frontend/lib/screens/manual_assistant_screen.dart` — 7 tabs:
1. Chat (spec 040, `chat_tab.dart`)
2. Review Queue
3. Rules (pattern rules admin)
4. Alerts
5. Verified Answers
6. Documents (upload / list / delete)
7. Train-AI (spec 080) — upload manuals, manage corpus, view ratings.

Frontend services:
- `frontend/lib/services/manual_assistant_service.dart` — main client.
- `frontend/lib/services/ai_*.dart` — provider, ratings, entity, rules.

---

## 8. Asset / System Registry (AI-adjacent)

- `assets`, `systems`, `asset_system_links` tables (specs 053, 056).
- `system_status_reports` with per-asset status (spec 086).
- Infrastructure screen (spec 061) consumes this data; AI features use it for
  disambiguation and suggestion.

---

## 9. Observability & Safety

- **Audit logging**: `utils.activity.log_activity()` writes verified-answer
  hits, provider fallbacks, ratings, entity extraction decisions, pattern
  alerts.
- **Stage latency** visible in every response for debugging (spec 066).
- **Graceful degradation**: no provider → Ollama → surfaced error with code.
- **Safety prompts** forbid invention of regulatory IDs, require conflict
  flagging, preserve Arabic as-is.

---

## 10. Testing

- `backend/tests/test_rag_quality.py` (~1,150 lines): 60+ curated questions
  across 12 categories, optional LLM-based faithfulness verification, JSON
  report output.
- Unit tests for validated-QA lookup, sort order, variant detection.

---

## 11. Known Gaps

1. No learned reranker — cosine distance only.
2. HyDE / rewrite are hard-pinned to Ollama; no graceful switch if Ollama is
   down.
3. No application-level rate limiting — relies on provider quotas.
4. `agentic_tools.py` (spec 047, ~603 lines) exists but is not reached from
   the `ask()` path.
5. No dynamic context-window trimming for very large manuals.
6. Streaming endpoint exposure to frontend is incomplete — `ask_stream()`
   exists but the HTTP route may return the full buffered response.
7. No response-level caching; embeddings re-run on every upload.
8. Parent-chunk expansion is 1 level deep (no grandparent recursion).

---

## 12. Overall Assessment

**Solid production-grade RAG**, domain-aware (civil aviation), with the
safety, auditability, and quality gates expected of a regulated environment.
Not bleeding-edge research (no learned reranker, no tool-using agent loop in
production), but the fundamentals — dual-layer retrieval, HyDE, diversity,
verified-answer short-circuit, multi-provider fallback, stage latency
profiling, and a real test harness — are all implemented and wired together.

Confidence in this inventory: high, based on direct inspection of
`manual_rag_service.py`, `ai_providers/`, `validated_qa_service.py`,
`document_search_service.py`, `document_preprocessor.py`,
`entity_extractor.py`, `pattern_engine.py`, and the Manual Assistant
frontend.
