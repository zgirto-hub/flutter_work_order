# Data Model: RAG Query Rewrite

**Feature**: 042-rag-query-rewrite | **Date**: 2026-04-12

## No Data Model Changes

This feature does not introduce any new entities, tables, columns, or migrations.

**Existing entities used (read-only)**:
- `manual_chunks` — vector search target (unchanged)
- `manual_assistant_settings` — system instructions cache (unchanged)
- `manual_corpus_stats` — corpus existence check (unchanged)

**In-memory data flow**:

```
User question (str) + History (list[{question, answer}]) 
    → _rewrite_query() → rewritten_query (str)
    → embed_single(rewritten_query) → embedding vector (768-dim)
    → search_manual_chunks(embedding) → chunks
    → _build_prompt(chunks, original_question, history) → prompt
    → generate(prompt) → answer
```

The rewritten query is ephemeral — it exists only for the duration of a single request and is not persisted anywhere.
