# Research: Natural Language Work Order Creation

**Branch**: `024-nl-create-work-order` | **Date**: 2026-04-06

## R1: LLM Prompt Strategy for Structured Field Extraction

**Decision**: Use a single Ollama prompt that instructs the model to return JSON with specific field names, constrained to provided valid values.

**Rationale**: The existing `/ai/suggest` endpoint uses Ollama with `gemma4:e2b` for free-text generation. For structured extraction, the same model can be instructed to return JSON. The prompt will include:
- The user's free-text input
- The list of valid departments, types, and statuses
- Instructions to return a JSON object with keys: `title`, `description`, `location`, `type`, `department`, `status`
- Instructions to set fields to `null` if not determinable from the input
- Instructions to expand shorthand and clean up grammar in the description
- Language instruction (respond in the same language as the input)

The `stream: False` option ensures a complete JSON response. Post-processing strips any preamble before the JSON.

**Alternatives considered**:
- **Multiple LLM calls** (one per field): Slower (6x latency), more error-prone, unnecessary since modern LLMs handle structured output well.
- **Regex/NLP parsing without LLM**: Cannot handle abbreviations, context, or Arabic. Too brittle.
- **External API (OpenAI, etc.)**: Adds external dependency and cost. Ollama is already running locally.

## R2: JSON Response Parsing and Validation

**Decision**: Parse the LLM response as JSON, validate each field against the known valid values, and silently null-out any invalid values.

**Rationale**: LLMs occasionally return values not in the constrained list, especially for department matching. The backend should:
1. Strip any text before the first `{` and after the last `}` (LLM preamble/postamble)
2. Parse as JSON
3. Validate `type` is in the provided types list; null if not
4. Validate `department` is in the provided departments list; null if not
5. Validate `status` is in the provided statuses list; null if not
6. Pass through `title`, `description`, `location` as-is (free text fields)

This ensures the frontend never receives invalid enum values.

**Alternatives considered**:
- **Reject entire response on any invalid field**: Too aggressive; partial results are still useful.
- **Frontend validation only**: Moves complexity to the frontend and risks invalid data reaching the form dropdowns.

## R3: Frontend Auto-Fill Highlight Pattern

**Decision**: Use a temporary colored border (accent color with reduced opacity) on auto-filled fields that fades after 3 seconds, plus scroll-to-first-field.

**Rationale**: The app already uses `AppColors.accent` throughout. A subtle border highlight matches the existing design language. The 3-second fade gives users enough time to notice the change without being distracting. Scroll ensures the user sees the filled fields even if they were below the fold.

**Alternatives considered**:
- **Permanent highlight until field is edited**: More complex state management; fields already have labels that show their content.
- **Toast/summary card**: Extra UI element; the fields themselves are the best indicator of what was filled.

## R4: Arabic Language Handling

**Decision**: Detect language from the input text and include a language instruction in the LLM prompt ("Respond in Arabic" or "Respond in English").

**Rationale**: The frontend already has an EN/AR language toggle from feature 022. This value can be sent alongside the text to the backend. The LLM prompt includes an explicit instruction to generate the description and title in the specified language. The `gemma4:e2b` model supports Arabic generation.

**Alternatives considered**:
- **Auto-detect language from text content**: Unreliable for short inputs or mixed-language text. Explicit is better (per Constitution Principle II).
- **Always respond in English regardless of input**: Fails the bilingual requirement.

## R5: NL Input Area Placement and UX

**Decision**: Place a collapsible card at the top of the Add Work Order form with a multi-line text input, language toggle (EN/AR), mic button (from 022), and a "Generate" button. Only visible on Add (not Edit).

**Rationale**: A card visually separates the AI input from the manual form below. Collapsible keeps it out of the way for users who prefer manual entry. The mic button reuses the existing `DictationButton` widget. The language toggle reuses the existing chip pattern from 022/021.

**Alternatives considered**:
- **Modal/dialog approach**: Adds navigation friction; inline is faster.
- **Replace the entire form**: Too radical; users need the manual form as fallback and for review.
- **Bottom sheet**: Awkward on mobile when keyboard is open.
