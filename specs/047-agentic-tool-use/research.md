# Research: Agentic Tool Use (Layer 5)

**Date**: 2026-04-13
**Feature**: 047-agentic-tool-use

## R1: Prompt-Based Tool Calling with Gemma via Ollama

**Decision**: Use prompt-based tool calling with structured text markers (not Ollama's native tool-use API).

**Rationale**: The current codebase has zero existing tool/function-calling patterns. All LLM interactions use `generate(prompt) → raw text`. Gemma 4 E2B supports instruction following well enough to output structured tool-call blocks when given clear formatting instructions. This avoids adding a dependency on Ollama's tool-use API (which requires JSON mode and specific model support), keeps the implementation simple, and aligns with Constitution Principle VII (Simplicity & YAGNI).

**Alternatives considered**:
- Ollama native tool-use API (`/api/chat` with `tools` parameter): Requires JSON mode, not all Gemma variants support it reliably, adds complexity.
- Langchain/LlamaIndex agent framework: Massive dependency, overkill for 3 tools, violates YAGNI.
- Hardcoded routing (regex on question → tool): Brittle, can't handle multi-tool chains, defeats the purpose of agentic behavior.

## R2: Tool Call Parsing Strategy

**Decision**: Use a simple text-block format with delimiters that the model outputs, parsed with regex.

**Rationale**: The model will be instructed to output tool calls in a format like:
```
TOOL_CALL: work_orders
PARAMS: {"work_order_number": 1042}
```
If the model outputs no `TOOL_CALL:` block, the entire output is treated as a direct answer. This is robust, easy to parse, and degrades gracefully (if parsing fails, treat the output as a direct answer).

**Alternatives considered**:
- JSON-only output: Gemma sometimes produces malformed JSON; text markers are more reliable.
- XML tags: More verbose, no benefit over simple markers.
- Structured output via Ollama `format: json`: Not reliably supported by all Gemma variants.

## R3: Agentic Loop Architecture

**Decision**: Iterative loop in a single async function (`run_agentic_loop`) that calls `generate()` repeatedly, parsing each response for tool calls.

**Rationale**: The loop:
1. Builds initial prompt with tool manifest + user question + history context
2. Calls `generate()` 
3. Parses response for `TOOL_CALL:` blocks
4. If tool call found: executes tool, appends result to conversation, loops (up to 3 times)
5. If no tool call: response is the final answer
6. After 3 tool calls or 60-second timeout: forces final answer generation with all gathered context

This keeps the entire agentic logic in one function, easy to test and debug.

## R4: Work Orders Tool — Query Strategy

**Decision**: Query Supabase directly using the existing `supabase` client from `db.py`, with parameterized filters parsed from the model's tool call.

**Rationale**: The existing `work_orders.py` router already queries work orders with various filters. The tool executor will replicate this pattern with a focused query returning the operational field set (job_no, status, description, type, department, technician, dates, signature_status). Results capped at 20 rows.

**Alternatives considered**:
- Call the work_orders API endpoint internally: Adds HTTP overhead, auth complexity for internal calls.
- Create a shared query function: Could be done, but direct Supabase query in the tool executor is simpler and self-contained.

## R5: Compare Tool — Implementation

**Decision**: The compare tool sends a dedicated prompt to `generate()` with the work order data and manual procedure text, asking for structured comparison output.

**Rationale**: The comparison is qualitative (does the work order's description/actions match the manual procedure?) and best handled by the LLM itself. The compare tool constructs a prompt with both data sources and asks for: overall verdict + per-item breakdown. This is a single `generate()` call, not a separate agentic loop.

## R6: Integration Point — Where to Hook the Agentic Loop

**Decision**: The `ask_question` endpoint in `manuals.py` calls `run_agentic_loop()` which internally decides whether to use tools or fall through to the existing `manual_rag_service.ask()` pipeline.

**Rationale**: The agentic loop wraps the existing pipeline. If the model decides to call the `manuals` tool, the tool executor calls `manual_rag_service.ask()`. If the model decides no tools are needed, the loop still calls `manual_rag_service.ask()` as the default path (maintaining backward compatibility). The agentic loop only adds value when the model detects a work-order or comparison query.

**Alternatives considered**:
- Replace `manual_rag_service.ask()` entirely: Too risky, breaks existing behavior.
- Add a separate endpoint: Breaks the existing frontend contract, requires UI changes to route questions differently.

## R7: Frontend Changes

**Decision**: Minimal — parse `tools_used` array from the response and display it as metadata (e.g., small badges or a collapsible section showing which tools contributed to the answer).

**Rationale**: The existing `AiAssistService` and chat UI already handle the response. Adding a `tools_used` field to the response is backward-compatible (frontend ignores unknown fields). Display is informational only.
