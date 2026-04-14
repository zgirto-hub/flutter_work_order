# Research: RAG Pipeline — Manual Knowledge Assistant

**Date**: 2026-04-14
**Feature**: 058-rag-pipeline

## Primary Finding: Feature Already Implemented

All components described in the specification exist in the codebase and are production-ready.

### Embedding Service

- **Decision**: Use existing `backend/services/ollama_embedder.py`
- **Rationale**: Already wraps Ollama `/api/embeddings` endpoint with `nomic-embed-text` model. Provides `embed_single()` and `embed_many()` functions with `EmbedderTimeoutError` exception handling. Dimensions match VECTOR(768) schema.
- **Alternatives considered**: Creating a new `embeddings.py` as spec describes — rejected because identical functionality already exists under a different name.

### Chunking Service

- **Decision**: Use existing `backend/services/manual_chunker.py` + `backend/services/manual_parser.py`
- **Rationale**: `manual_parser.py` handles file type dispatch (PDF via pymupdf, DOCX via python-docx, TXT). `manual_chunker.py` handles text splitting with overlap and page tracking. Both already integrate with the upload pipeline.
- **Alternatives considered**: Creating a new `chunker.py` — rejected because functionality is split across two existing files that are already wired into the router.

### Upload Endpoint

- **Decision**: Use existing `POST /api/manuals/upload` at `routers/manuals.py:169`
- **Rationale**: Accepts multipart/form-data with file, title, and user metadata. Calls parser → chunker → embedder → Supabase RPC pipeline. Returns manual ID and chunk count. Error handling covers 422, 502, 503 patterns.
- **Alternatives considered**: None — endpoint matches spec exactly.

### Query Endpoint

- **Decision**: Use existing `POST /api/manuals/ask` at `routers/manuals.py:300`
- **Rationale**: Accepts question, manual_id filter, model selection, and conversation history. Runs full RAG pipeline via `manual_rag_service.py` (query rewriting, HyDE, vector search, reranking, generation). Returns answer with source chunks. Goes beyond spec by supporting session summaries and agentic tool use.
- **Alternatives considered**: The spec described a simpler `POST /api/manuals/query` — the existing `/ask` endpoint is a superset with more advanced RAG stages.

### Flutter Service Layer

- **Decision**: Use existing `frontend/lib/services/manual_assistant_service.dart`
- **Rationale**: 25+ methods including `uploadManual()` (line 130) and `askQuestion()` (line 211). Follows project patterns with custom exceptions (`ManualUploadException`, `ManualAskException`), timeout handling, and JSON body encoding. Also includes chunk management, rating, and verified answers methods.
- **Alternatives considered**: None — service layer is more comprehensive than spec requirements.

### Dependencies

- **Decision**: No changes needed to `requirements.txt`
- **Rationale**: `pymupdf==1.24.10`, `python-docx==1.2.0`, `httpx==0.28.1` are all present.

### Router Registration

- **Decision**: No changes needed to `main.py`
- **Rationale**: `manuals` router imported at line 31, registered at line 119 with prefix `/api`.

## Naming Differences (Spec vs. Reality)

| Spec Name | Actual Name | Notes |
|-----------|-------------|-------|
| `services/embeddings.py` | `services/ollama_embedder.py` | Same function, different module name |
| `services/chunker.py` | `services/manual_chunker.py` + `services/manual_parser.py` | Split across two files |
| `embed_text()` | `embed_single()` | Same signature pattern |
| `embed_batch()` | `embed_many()` | Same signature pattern |
| `POST /api/manuals/query` | `POST /api/manuals/ask` | Different path, superset functionality |
| `ManualQueryResult` (Dart) | `ManualQaAnswer` (Dart) | Different class name, same data shape |
| `queryManual()` (Dart) | `askQuestion()` (Dart) | Different method name |

## Conclusion

No NEEDS CLARIFICATION items remain. All research questions resolved by discovering existing implementations. The feature specification describes work that has already been completed.
