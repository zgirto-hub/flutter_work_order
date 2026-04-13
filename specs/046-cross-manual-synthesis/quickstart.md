# Quickstart: Cross-Manual Synthesis (Layer 4)

**Branch**: `046-cross-manual-synthesis`

## Prerequisites

- Multiple manuals uploaded to the assistant (at least 2 for synthesis to activate)
- Ollama running with `gemma4:e2b` model loaded
- Backend running (`document_server.service`)

## Testing the Feature

### Cross-manual synthesis (new behavior)

1. Open the Manual Assistant in the PWA
2. Select **"All Manuals"** from the manual dropdown
3. Ask a question that spans multiple manuals (e.g., "What is the torque specification for engine mount bolts?")
4. Verify:
   - The answer references multiple manual titles by name
   - A "Synthesized from N manuals" notice appears below the answer
   - Sources include chunks from different manuals
   - If manuals disagree, an amber conflict warning appears

### Single-manual queries (unchanged behavior)

1. Select a specific manual from the dropdown
2. Ask a question
3. Verify: No synthesis notice, no "manuals consulted" metadata — identical to current behavior

### Conflict detection

1. Upload two manuals with contradictory information on the same topic
2. Select "All Manuals" and ask about the contradictory topic
3. Verify: The answer includes "⚠ CONFLICT:" markers and the conflict warning banner shows

## Key Files

| File | Role |
|------|------|
| `backend/services/manual_rag_service.py` | Pipeline logic: retrieval, sub-answers, synthesis |
| `frontend/lib/models/manual_qa_answer.dart` | Response model with new fields |
| `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` | UI for synthesis notice + conflicts |
