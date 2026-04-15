# Quickstart: AI Provider Manager

**Feature**: 063-ai-provider-manager
**Audience**: Developer about to pick up [tasks.md](./tasks.md) after `/speckit.tasks`.

## Prerequisites

- Repository on branch `063-ai-provider-manager`.
- Backend dev loop working (`systemctl` locally or server-side: `sudo systemctl restart document_server.service`).
- Supabase CLI configured for this project (existing).
- Flutter dev loop working (`flutter run -d chrome`).
- A Google AI Studio API key for Gemini 2.5 Flash (free tier is fine for dev).

## One-time setup

### 1. Migration

```sh
# from repo root
cat supabase/migrations/20260415_app_settings.sql | <apply via your usual path>
```

Expected result: `app_settings` table exists with two seed rows (`ai_provider=local`, `ai_providers_available=["local","gemini"]`).

### 2. Backend dependency

```sh
cd backend
pip install google-generativeai
# requirements.txt should already list it after this feature lands
```

### 3. Environment variable

Add to server `.env`:

```
GEMINI_API_KEY=<your-key>
```

Restart backend:

```sh
sudo systemctl restart document_server.service
```

## Smoke test — Story 1 (Admin switch)

1. Log in as an Admin in the Flutter PWA.
2. Open Settings → "AI Assistant" section.
3. Verify the selector lists **Local (Ollama)** and **Gemini 2.5 Flash** and the current active is **Local**.
4. Select **Gemini 2.5 Flash**, Save. Verify toast "Saved".
5. Wait ≤ 60 seconds (TTL cache).
6. Open Ask-the-AI, submit a question. Verify the chip shows `● Gemini 2.5 Flash`.
7. Verify backend response JSON has `"provider_used": "gemini", "fallback_used": false`.

## Smoke test — Story 2 (fallback)

1. With active provider = Gemini, invalidate the key: set `GEMINI_API_KEY=invalid` in `.env`, restart backend.
2. Submit a question in Ask-the-AI.
3. Verify the user still receives an answer (served by Local Ollama).
4. Verify response JSON: `"provider_used": "local", "fallback_used": true`.
5. Verify chip shows fallback warning state (e.g., `⚠ Local (fallback)`).
6. Verify `user_activity_log` has a row with `action='ai_provider_fallback'`, `target_label='gemini'`, `target_id='local'`, `detail` starting with a reason string.

## Smoke test — Story 4 (extensibility check)

Without shipping a real new provider, verify the architecture by temporarily adding a stub:

1. Create `backend/services/ai_providers/stub_future.py` with a `StubFutureProvider(AIProvider)` whose `generate` returns a fixed string and `health_check` returns True.
2. Add `"future": StubFutureProvider` to `registry.py`.
3. Update `app_settings.ai_providers_available` to `["local","gemini","future"]`.
4. Reload Admin Settings (no app rebuild). Verify the new option appears.
5. Select it, submit a question, verify `provider_used="future"`.
6. Revert the stub.

## Common pitfalls

- **Chip not updating within 60s**: that's the TTL; wait it out or restart backend to force cold cache.
- **`healthy: false, reason: "missing_credentials"`**: `GEMINI_API_KEY` not loaded — check `.env` and backend restart.
- **Fallback doesn't trigger on slow Gemini**: confirm `asyncio.wait_for(..., timeout=30)` is wrapping the call — not just the SDK's internal timeout.
- **Non-Admin sees selector**: role check missing on the Settings screen; it's a UI hide + backend 403, both must be in place.
- **New provider doesn't appear in Admin UI**: verify both (a) key present in `ai_providers_available`, AND (b) class registered in `PROVIDERS` dict.

## What to NOT do in phase 1

Per the Clarifications session and FR-020:

- Don't route analytics/WO-description/NL-search/etc. AI features through the new abstraction (Q1 → phase 2+).
- Don't implement `embed()` on any provider (Q2 → reserved, NotImplementedError is correct).
- Don't add provider chips to any UI surface other than Ask-the-AI (Q5).
- Don't retry the active provider before falling back (Q4 → fail fast).
- Don't build per-user provider preferences, streaming, rotation, or cost tracking.
