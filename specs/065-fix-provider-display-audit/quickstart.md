# Quickstart: Phase 2 Cleanups

**Feature**: 065-fix-provider-display-audit
**Audience**: Developer picking up [tasks.md](./tasks.md) after `/speckit.tasks`.

## Prerequisites

- Branch `065-fix-provider-display-audit` checked out.
- Spec 063 already shipped to production (confirmed 2026-04-15).
- Backend dev loop: `sudo systemctl restart document_server.service` on Zorin server.
- Flutter dev loop: `flutter run -d chrome`.
- An admin account (e.g., `salah@admin.com`) to exercise the provider-switch endpoint.
- A cloud provider configured with a working API key (Groq, Gemini, or Mistral). For smoke testing fallback, you'll need to intentionally break the key.

## Scope recap

Three fixes — no new endpoints, no migrations, no new dependencies:

1. Add `provider_display_name` to `/manuals/ask` response; keep `model` as alias for one release.
2. Write exactly one `user_activity_log` row with `action='ai_provider_fallback'` when fallback fires; closed taxonomy for `detail`.
3. Flutter chip reacts to per-response `fallback_used`, rendering `⚠ <display_name> (fallback)` in warning state.

## Smoke test — Story 1 (truthful label)

1. Switch active provider to Groq:
   ```sh
   curl -s -X POST "http://localhost:8000/api/ai/provider?admin_email=salah@admin.com" \
     -H "Content-Type: application/json" -d '{"provider":"groq"}'
   ```
2. Hard-refresh the Ask-the-AI screen.
3. Ask a question. Verify:
   - Top chip shows `● Groq (Llama 3.3 70B)` (already works from spec 063).
   - Footer line under the answer shows `Groq (Llama 3.3 70B) · <duration>` — **not** `gemma4:e2b`.
4. Network tab → inspect `/manuals/ask` response → confirm `"provider_display_name": "Groq (Llama 3.3 70B)"` and `"model": "Groq (Llama 3.3 70B)"` (same string).

## Smoke test — Story 2 (audit row written)

1. With active provider = Gemini (or Groq), invalidate the key in `.env` on the server:
   ```sh
   sed -i 's/^GEMINI_API_KEY=.*/GEMINI_API_KEY=invalid/' backend/.env
   sudo systemctl restart document_server.service
   ```
2. Switch active to Gemini via curl (as above, but `-d '{"provider":"gemini"}'`).
3. Ask a question in Ask-the-AI. Expect a normal answer served by Local (fallback fires).
4. Query the audit log (Supabase SQL editor or MCP):
   ```sql
   SELECT user_email, action, target_label, target_id, detail, created_at
   FROM user_activity_log
   WHERE action = 'ai_provider_fallback'
   ORDER BY created_at DESC
   LIMIT 5;
   ```
5. Verify most recent row has:
   - `user_email` = the Flutter-logged-in user's email
   - `target_label` = `gemini`
   - `target_id` = `local`
   - `detail` ∈ `{quota_exceeded, missing_credentials, empty_response, timeout_30s, unknown}`
6. Restore the real key and restart the backend.

## Smoke test — Story 3 (chip warning state)

Same setup as Story 2.

1. With Gemini active and key invalid, ask a question.
2. Verify WITHOUT reloading the page:
   - Chip switches from `● Gemini 2.5 Flash` (green) to `⚠ Local (Ollama) (fallback)` (amber).
3. Restore the Gemini key; restart backend.
4. Ask another question. Verify chip returns to `● Gemini 2.5 Flash` healthy state.

## Common pitfalls

- **Chip doesn't update after fallback**: confirm `manual_rag_screen.dart` passes the last response's `fallbackUsed` into the chip, not just the screen-open active provider.
- **Audit row missing**: confirm the `log_activity()` call in `resolver.py` is reached — temporarily add a `logger.info("fallback logged")` and tail `journalctl -u document_server.service`.
- **`detail` contains SDK stack trace**: the exception scrubber is bypassed. Re-check the closed-taxonomy mapping order in the resolver helper.
- **Footer still shows `gemma4:e2b`**: the response builder in `manual_rag_service.py` wasn't updated, OR the Flutter `ManualAskResponse` model still reads a hardcoded field. Check both.
- **Legacy `model` field is missing**: the alias write was dropped — breaks FR-009. Restore the alias (same value as `provider_display_name`).

## What NOT to do in this spec

- Don't add per-user provider preferences.
- Don't route other AI features through the provider abstraction.
- Don't remove the legacy `model` field — that's a future spec.
- Don't expand the failure-reason taxonomy — stay within the five values.
- Don't add any new backend endpoints or Supabase migrations.
