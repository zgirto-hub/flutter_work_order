# AI Assistant Improvement Roadmap

**Created**: 2026-04-16
**Last Updated**: 2026-04-16
**Owner**: zgirto-hub

## Current State (Post Specs 040-076)

7-stage RAG pipeline: query rewrite → HyDE → vector search → rerank → session summary → cross-manual synthesis → generation. Markdown extraction via pymupdf4llm, AI preprocessing via local Ollama, contextual embeddings, Gemini Flash for generation with Ollama fallback.

---

## Phase 1: Search Precision (Low Effort, High Impact)

### Spec 077: Chunk Overlap + Larger Rerank Window

**Problem**: Chunks have hard boundaries — ideas that span two chunks get lost. The rerank window (top 10 → 3) is too narrow, discarding relevant candidates.

**Solution**:
- Add 2-3 sentence overlap between child chunks in `_split_into_children()`
- Increase vector search from top 10 to top 20 candidates
- Increase rerank output from top 3 to top 5
- Re-embed existing documents with new chunk boundaries

**Impact**: Catches cross-boundary information. More relevant chunks reach the generation model.

**Prompt**:
```
/speckit.specify Build Spec 077: Chunk Overlap and Rerank Window — add 2-3 sentence overlap between child chunks in the document chunking pipeline so that ideas spanning chunk boundaries are not lost. Also increase the vector search candidate pool from 10 to 20 and the rerank output from 3 to 5, giving the generation model more relevant context. Apply to both document_chunks and manual_chunks pipelines. Existing documents should be re-embeddable via the existing re-index button.
```

---

### Spec 078: Parent-Child Retrieval

**Problem**: When a child chunk matches a query, the LLM only sees that one fragment. It misses the surrounding context — what came before and after on the same page.

**Solution**:
- When vector search returns a child chunk, also fetch its parent chunk and sibling child chunks
- Pass parent as context header, siblings as supporting context
- The generation model sees the full page context, not just a paragraph

**Impact**: Dramatically better answers for procedural content where steps span multiple chunks.

**Prompt**:
```
/speckit.specify Build Spec 078: Parent-Child Retrieval — when vector search returns a matching child chunk, also retrieve its parent chunk (section context) and sibling child chunks (surrounding paragraphs). Pass the parent as a context header and siblings as supporting context to the generation model. This gives the LLM full page-level context instead of isolated fragments. The document_chunks table already has parent_id and chunk_type fields to support this. Do not change the embedding or indexing pipeline — only the retrieval and context assembly stages.
```

---

## Phase 2: Extraction Quality (Medium Effort, High Impact)

### Spec 079: Vision-Based PDF Extraction

**Problem**: pymupdf4llm extracts text and basic structure, but completely misses diagrams, flowcharts, screenshots, and visual layouts that are common in training slide decks.

**Solution**:
- For PDF pages, send the rendered page image to Gemini Flash Vision
- Gemini describes the visual content + extracts text with full layout awareness
- Falls back to pymupdf4llm if Gemini is unavailable
- Replaces the current text-only extraction for PDFs
- This replaces the Ollama preprocessing step for PDFs (Gemini Vision does both extraction and enrichment in one pass)

**Impact**: Diagrams, tables in images, flowcharts, and annotated screenshots become searchable for the first time.

**Prompt**:
```
/speckit.specify Build Spec 079: Vision-Based PDF Extraction — for PDF documents, render each page as an image and send it to Gemini Flash Vision to extract structured Markdown that includes text, table content, diagram descriptions, and visual layout. This replaces both the pymupdf4llm extraction and the Ollama preprocessing step for PDFs in a single pass. Falls back to pymupdf4llm + Ollama preprocessing if Gemini Vision is unavailable. Keep pymupdf4llm as the extractor for DOCX/TXT/MD files. The Gemini free tier supports 15 RPM which is sufficient for page-by-page processing of a few documents per day.
```

---

### Spec 080: Multi-Query Retrieval

**Problem**: A single search query may miss relevant chunks that use different terminology. "How to configure alarms" won't find chunks that say "alert setup" or "notification management."

**Solution**:
- Stage 1 (query rewrite) generates 3-4 variant queries instead of one
- Each variant searches independently against pgvector
- Results are merged and deduplicated before reranking
- Reranker scores the combined pool

**Impact**: Higher recall — catches chunks that any single query would miss.

**Prompt**:
```
/speckit.specify Build Spec 080: Multi-Query Retrieval — modify the query rewrite stage to generate 3-4 variant search queries that cover different phrasings, synonyms, and perspectives of the user's question. Run each variant through vector search independently, merge and deduplicate the results, then pass the combined pool to the reranker. This improves recall for queries where the document uses different terminology than the user. Keep the total vector search calls under 4 to limit latency.
```

---

## Phase 3: Answer Intelligence (Medium Effort, High Impact)

### Spec 081: Validated Q&A Fast Path

**Problem**: The full 7-stage pipeline runs even for questions that have been asked and verified before. This wastes 30-40 seconds when an instant answer exists.

**Solution**:
- Before entering the RAG pipeline, check `validated_qa` table for a semantic match
- If a verified answer exists with high similarity (> 0.90), return it instantly
- Show "Verified Answer" badge in the UI
- Skip all 7 pipeline stages — response in < 1 second
- Already partially built in spec 059 — wire it into the main query flow

**Impact**: Instant answers for repeated questions. Reduces load on Ollama and Gemini.

**Prompt**:
```
/speckit.specify Build Spec 081: Validated Q&A Fast Path — before running the RAG pipeline, check the validated_qa table for a semantically similar question (cosine similarity > 0.90). If a verified answer exists, return it immediately with a "Verified Answer" badge, skipping all 7 pipeline stages. Response time should be under 1 second. The validated_qa table and embedding infrastructure already exist from specs 048 and 059. This spec wires the lookup into the main /manuals/ask endpoint as the first step before query rewrite.
```

---

### Spec 082: Answer Self-Evaluation

**Problem**: The LLM sometimes says "I don't have that information" even when the retrieved chunks contain the answer. It also sometimes gives shallow answers when deeper reasoning is possible.

**Solution**:
- After generation, add a self-evaluation step: "Does your answer fully address the question using the provided sources?"
- If the model rates itself low, it regenerates with an explicit instruction to look harder at the sources
- Maximum one retry to avoid latency spiral
- Log self-evaluation scores for quality monitoring

**Impact**: Fewer false "I don't know" responses. More thorough answers from the same chunks.

**Prompt**:
```
/speckit.specify Build Spec 082: Answer Self-Evaluation — after the generation stage, add a self-evaluation step where the model rates whether its answer fully addresses the question using the provided source chunks. If the self-rating is low (e.g., model says "I don't have that information" or rates confidence below 50%), retry generation once with an explicit instruction to re-examine the source chunks more carefully. Maximum one retry. Log the self-evaluation score and whether a retry occurred for quality monitoring. Use Gemini Flash for both generation and evaluation.
```

---

## Phase 4: Advanced Capabilities (High Effort, Transformative)

### Spec 083: Agentic RAG with Tool Use

**Problem**: The current pipeline is a fixed 7-step sequence. It can't decide to search again with different terms, look up a specific document, or combine information from multiple searches.

**Solution**:
- Give the generation model tools: `search(query)`, `lookup_page(doc, page)`, `list_documents()`
- The model decides when and how to search — multi-step reasoning
- Example: "Compare alarm procedures across all manuals" → searches each manual, compares results
- Builds on spec 047 (agentic tool use) foundation

**Prompt**:
```
/speckit.specify Build Spec 083: Agentic RAG with Tool Use — give the generation model access to tools: search(query) to run vector search, lookup_page(document_id, page_number) to retrieve a specific page, and list_documents() to see available manuals. The model decides when to search, what to search, and whether to search again based on intermediate results. This enables multi-step reasoning like "find all procedures related to X across all manuals and compare them." Limit to maximum 5 tool calls per question to bound latency. Builds on the agentic tool use foundation from spec 047.
```

---

### Spec 084: Knowledge Graph from Documents

**Problem**: Vector search finds text similarity but not relationships. It can't answer "What systems depend on the AMHS gateway?" or "What happens if the NOTAM database goes down?"

**Solution**:
- During document ingestion, extract entities (systems, procedures, roles, equipment) and their relationships
- Store in a graph structure (entity nodes + relationship edges in Supabase)
- Query pipeline checks both vector search AND graph traversal
- Combines text-similar chunks with structurally-related entities

**Prompt**:
```
/speckit.specify Build Spec 084: Knowledge Graph from Documents — during document ingestion, extract entities (systems, procedures, roles, equipment) and their relationships using the AI preprocessing step. Store entities and relationships in Supabase tables (reuse entity extraction from spec 049). During query, check both vector search and graph traversal — if the query mentions a known entity, also retrieve chunks connected via relationships. This enables queries like "What depends on system X?" or "What procedures involve role Y?" that pure vector search cannot answer.
```

---

## Implementation Order

```
Phase 1 (next 2 weeks):
  077 Chunk Overlap + Rerank Window    ← quick win, immediate improvement
  078 Parent-Child Retrieval           ← big context improvement

Phase 2 (weeks 3-4):
  079 Vision-Based PDF Extraction      ← diagrams become searchable
  080 Multi-Query Retrieval            ← higher recall

Phase 3 (weeks 5-6):
  081 Validated Q&A Fast Path          ← instant answers for known questions
  082 Answer Self-Evaluation           ← fewer "I don't know" failures

Phase 4 (weeks 7-10):
  083 Agentic RAG                      ← multi-step reasoning
  084 Knowledge Graph                  ← relationship-aware search
```

## Success Metrics

| Metric | Current | After Phase 1 | After Phase 2 | After Phase 4 |
|--------|---------|---------------|---------------|---------------|
| Search hit rate (top 5) | ~80% | ~90% | ~95% | ~98% |
| Answer quality (useful response) | ~60% | ~75% | ~85% | ~95% |
| Avg response time | 30-40s | 25-35s | 25-35s | 1-10s (cached) / 30-45s (new) |
| Diagram/visual content searchable | No | No | Yes | Yes |
| Multi-step reasoning | No | No | No | Yes |
