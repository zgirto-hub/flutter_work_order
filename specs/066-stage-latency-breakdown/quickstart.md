# Quickstart: Per-Stage RAG Latency Breakdown

**Feature**: 066-stage-latency-breakdown
**Audience**: Developers picking up the implementation after `/speckit.tasks`.

---

## What this feature does

Shows users, on every Ask-the-AI answer card, how long each pipeline stage took. Makes the speed advantage of cloud providers like Groq or Mistral visible (generator ≈ 1s) even when local preprocessing dominates the total (~22s). Pure observability — no pipeline behavior changes.

## Pre-reqs

- Spec 065 (provider display audit) merged to `main`. This branch was cut from post-065 `main`.
- No new packages, no new migrations, no new environment variables.

## Acceptance walkthrough (manual test)

1. Start backend and frontend against a dev Supabase.
2. Open the Ask-the-AI screen.
3. With the active provider set to Ollama Gemma (local), ask any manual question.
   - Expected footer: `Gemma 4 E2B · 18.2s · pipeline 22.4s` (actual numbers vary).
   - Expected chevron: visible on the right edge of the footer.
4. Tap the chevron. Expected: a 7-row panel expands showing labeled stage timings (Embed, HyDE, Rewrite, Retrieval, Rerank, Generator, Total). All seven values formatted per FR-007 rules.
5. Switch active provider to Groq (via AI Provider Manager). Ask a similar question.
   - Expected footer: `Groq (Llama 3.3 70B) · 1.2s · pipeline 22.3s` (generator collapses; total roughly unchanged because preprocessing is local).
6. Ask a greeting ("hi", "thanks", "شكرا").
   - Expected footer: total only (`<1s` or similar); no provider name; chevron still present.
   - Expected breakdown: six stages show `—`, total shows `<1s`.
7. Switch to Arabic UI. Repeat step 3. Verify numbers render identically (same units, same precision).

## Where the code lives

- Backend timing: `backend/services/manual_rag_service.py` (wrap each stage with `_StageTimer`)
- Generator timing: `backend/services/ai_providers/resolver.py`
- Response wiring: `backend/routers/manuals.py`
- Frontend model: `frontend/lib/models/latency_breakdown.dart` (new), `frontend/lib/models/manual_qa_answer.dart`
- Frontend formatter: `frontend/lib/utils/latency_formatter.dart` (new)
- Frontend UI: `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`

See [plan.md](./plan.md) §Project Structure for the full file map.

## Format rules (locked, non-negotiable)

| Raw ms           | Rendered |
|------------------|----------|
| `null`           | `—`      |
| `0` ≤ ms < 100   | `<1s`    |
| `100` ≤ ms < 1000| `0.Xs` (e.g., `0.3s`) |
| `1000` ≤ ms < 60000 | `X.Ys` (e.g., `1.2s`, `22.4s`) |
| `60000` ≤ ms     | `Xm Ys` (e.g., `1m 15s`) |

These are tested at boundary values (99, 100, 999, 1000, 59999, 60000, 75000).

## Contract invariants (do not break)

- All seven keys always present in `latency_breakdown` (see [contracts/manuals-ask-response.md](./contracts/manuals-ask-response.md)).
- `total_ms` is never null.
- `generator_ms` measures the provider that actually answered (post-fallback), not the first attempt.
- No persistence — the breakdown lives only in the HTTP response.

## Out of scope (don't do these here)

- Instrumenting other AI endpoints. Phase 2 spec territory.
- Writing latency to `user_activity_log`. Explicitly rejected in clarification Q2.
- Alerting on slow stages, per-user visibility controls, optimizing the pipeline itself.

## Done when

- Manual steps 1–7 above all pass.
- `pytest backend/tests/test_manual_rag_latency.py` green.
- `flutter test test/utils/latency_formatter_test.dart test/widgets/answer_card_latency_test.dart` green.
- A legacy client (simulated by stripping `latency_breakdown` from a response fixture) still renders the answer with no regression (FR-009 verification).
