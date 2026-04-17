# Data Model: RAG Pipeline Latency Optimization

**Date**: 2026-04-17  
**Feature**: 077-rag-pipeline-parallelize

## Schema Changes

None. This feature is a pure backend code optimization. No new tables, columns, or migrations.

## Existing Entities Referenced

- **`latency_breakdown`** (transient dict, not persisted): Per-response timing data with keys `rewrite_ms`, `hyde_ms`, `embed_ms`, `generator_ms`, `total_ms`. No schema change — values now reflect parallel execution timing.

## State Transitions

No new state transitions. The pipeline stages (rewrite → HyDE → embed → retrieve → generate) remain the same; only the execution order of rewrite and HyDE changes from sequential to parallel.
