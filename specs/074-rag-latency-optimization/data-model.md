# Data Model: RAG Latency Optimization

**Date**: 2026-04-16 | **Branch**: `074-rag-latency-optimization`

## Schema Changes

**None.** This feature is a pure backend refactor with no database schema changes.

## Entities Affected (read-only)

| Entity | Table | Usage |
|--------|-------|-------|
| Document Chunks | `document_chunks` | Retrieved via `search_document_chunks` RPC — unchanged |
| Knowledge Documents | `knowledge_documents` | Display name lookup — unchanged |
| Validated QA | `validated_qa` | Fast-path cache check — unchanged |
| App Settings | `app_settings` | AI provider config read — unchanged |

## Response Schema (unchanged)

The `/manuals/ask` response format remains identical. Key fields:

- `answer` (string) — the generated answer
- `grounded` (bool) — whether answer is sourced from documents
- `sources` (array) — document/chunk attribution with display_name, section_title, page_number, score
- `confidence` (string) — "high" / "medium" / "low"
- `latency_breakdown` (object) — embed_ms, hyde_ms, rewrite_ms, retrieval_ms, rerank_ms, generator_ms, total_ms
- `source_type` (string) — "validated_qa" or "document"
