# Quickstart: Agentic Tool Use (Layer 5)

**Feature**: 047-agentic-tool-use

## What This Feature Does

Adds an agentic tool-calling layer to the manual assistant. The AI model can now autonomously decide to query work orders, search manuals, or compare work orders against manual procedures before generating a final answer.

## Key Files

| File | Purpose |
|------|---------|
| `backend/services/agentic_tools.py` | NEW — tool manifest, tool executors, agentic loop |
| `backend/routers/manuals.py` | Modified — ask_question routes through agentic loop |
| `backend/services/manual_rag_service.py` | Unchanged — wrapped by manuals tool |
| `frontend/lib/services/ai_assist_service.dart` | Modified — parse tools_used metadata |

## How It Works

1. User asks a question via the AI chat interface
2. The agentic loop builds a prompt with the tool manifest + question
3. Gemma decides: answer directly OR call a tool
4. If tool called → execute it → feed result back → Gemma decides again (up to 3 calls)
5. Final answer returned with `tools_used` metadata

## Testing

Ask these questions to verify each path:

| Question | Expected Tool Calls |
|----------|-------------------|
| "What is the procedure for oil change?" | None (direct manual answer) |
| "What is the status of work order 1042?" | work_orders |
| "Show me pending work orders" | work_orders |
| "Does work order 1042 follow the CADAS procedure?" | work_orders → manuals → compare |
| "Hello, how are you?" | None (direct answer) |

## Dependencies

- Ollama with Gemma 4 E2B (existing)
- Supabase with work_orders table (existing)
- Manual chunks in pgvector (existing)
- No new packages or dependencies
