# OPENCODE.md — Instructions for opencode when implementing specs in flutter_work_order

**Audience**: you (opencode), running against this repo to implement a SpecKit feature spec.
**When used**: every time the user says "implement spec NNN" (or similar). Re-read this file each run — it supersedes your defaults.

## How the user invokes you

You will be handed a spec folder path like `specs/086-per-asset-status/`. That folder always contains:

- `tasks.md` — your step-by-step checklist. Execute in ID order.
- `spec.md` — WHAT the feature does and why.
- `plan.md` — HOW it's structured (Tech Context + Constitution Check).
- `research.md` — design decisions and rejected alternatives. Don't re-litigate.
- `data-model.md` — exact migration SQL.
- `contracts/api.md` — exact request/response shapes.
- `quickstart.md` — manual verification procedure.

Also always read:
- `CLAUDE.md` — project coding guidelines.
- `AGENT.md` — architecture / where-to-add-things map.
- `.specify/memory/constitution.md` — 7 non-negotiable principles for this repo.

**If any of the above is missing, STOP and ask the user. Don't infer.**

---

## Source of truth (read in this order, every run)

1. `specs/<NNN-name>/tasks.md`
2. `specs/<NNN-name>/spec.md`
3. `specs/<NNN-name>/plan.md`
4. `specs/<NNN-name>/research.md`
5. `specs/<NNN-name>/data-model.md`
6. `specs/<NNN-name>/contracts/`
7. `specs/<NNN-name>/quickstart.md`
8. `CLAUDE.md`
9. `AGENT.md`
10. `.specify/memory/constitution.md`
11. Each existing file you're about to edit — **in full**, before touching it.

---

## Execution model

### Task order

- Work `tasks.md` in ID order (T001, T002, ...). Tasks tagged `[P]` may be parallelized only if they touch different files and have no dependency on an incomplete task.
- Mark each `- [ ]` → `- [x]` in `tasks.md` as you complete it. Commit `tasks.md` alongside the code change for that task.

### Commits

- **One commit per task** (or a tight inseparable group — e.g., migration + its first backend usage). Unrelated work never shares a commit.
- **Commit message format**: `spec <NNN>: T00X — <verb> <short object>`
  - Good: `spec 086: T008 — add GET /system-status/systems/{id}/assets endpoint`
  - Bad: `updates`, `progress`, `more stuff for spec`
- Do **NOT** squash. The reviewer walks commit-by-commit.
- **NEVER** use `--no-verify`, `--no-gpg-sign`, or `-c commit.gpgsign=false`. If a pre-commit hook fails, fix the underlying issue.
- **NEVER** commit `backend/version.json`. It's managed on the server.
- **NEVER** open a PR yourself. The user hands the branch to a reviewer first.

### Backend restart

- After **any** change to `backend/routers/*.py` or backend model code, restart the backend on the deployment server:
  `sudo systemctl restart document_server.service`
- Do not claim a backend task is complete until restart has happened and a smoke-test (curl against the modified endpoint) returns the expected shape.
- After adding new Python deps to `backend/requirements.txt`, `pip install -r requirements.txt` on the server **BEFORE** the restart.

### Migrations

- Create the SQL file exactly as specified in `data-model.md`. Do NOT hand-edit the Supabase console.
- Apply via the Supabase MCP (`apply_migration`) or the project's migration tool — never manually.
- Verify the migration landed: `list_tables` or inspect the changed table.

### Stop conditions

- **Stop and ask** before deviating from `tasks.md`, the API contract in `contracts/api.md`, or the schema in `data-model.md`.
- **Stop and ask** if reality contradicts the spec (e.g., the migration won't apply, an endpoint returns an unexpected shape, a model field is already named something else).
- **Stop and ask** if you genuinely don't understand a task. A best-guess commit is worse than a question.
- When you stop, describe: *what I expected*, *what I observed*, *what I think the fix is*. Wait for the user.

---

## Coding policy (hard rules, from CLAUDE.md)

1. **Don't add features, refactor, or abstract beyond what the task requires.** No premature abstractions, no speculative helpers. Three similar lines is better than a clever abstraction.
2. **Don't add error handling, fallbacks, or validation for scenarios that can't happen.** Validate only at system boundaries (HTTP body → backend, user input → UI). Trust framework and internal-code guarantees.
3. **Default to writing NO comments.** Only add a comment when the WHY is non-obvious: a hidden constraint, subtle invariant, workaround for a specific bug. Never explain WHAT the code does — well-named identifiers already do that.
4. **Never reference the current task/spec/PR in a comment.** ("added for spec 086", "used by the drill-in sheet", "fixes issue #123"). That belongs in the commit message, not the code.
5. **No backwards-compat hacks, no dead-code markers, no re-exports "just in case."** If something becomes unused, delete it. Don't rename to `_unused` or leave `// removed` comments.
6. **For UI changes, start the dev server and exercise the feature in a browser** before reporting the task done. `flutter analyze` verifies code, not feature correctness.
7. **Match the project's existing patterns, not your training priors.** Name things the way neighboring code names them. Use the same error-return style, the same theme-token style, the same service-call pattern.

---

## Must do

- ✅ Read each file in full before editing.
- ✅ Run the affected surface after every change (compile / typecheck / curl / browse).
- ✅ Use `AppColors` / `AppShadows` / `AppTheme` tokens from `frontend/lib/theme/app_theme.dart`. Hardcoded hex is allowed ONLY when you're matching an existing palette already used in the same screen (e.g., status green/red).
- ✅ Return nullable fields as nullable all the way through (Pydantic `Optional[str] = None` → JSON `null` → Dart `String?`). Never coerce a real null to an empty string silently.
- ✅ Use the Supabase client's idiomatic PostgREST style: `.is_("col", "null")`, `.eq(...)`, `.in_(...)`. Match what's already in neighboring routers.
- ✅ For Flutter, defend every `json['foo']` with `?? <default>` at parse time. The wire is untrusted.
- ✅ Prefer editing existing files over creating new ones. Only create a new file when `tasks.md` explicitly says so, or when a task describes a genuinely new widget/service with no natural home.
- ✅ Re-read your own diff before committing. Check imports, types, nullability, naming, and that you didn't delete something still referenced.

---

## Must NOT do

- ❌ Do NOT add new dependencies to `pubspec.yaml` or `backend/requirements.txt` unless the spec explicitly calls for one. If you think you need one, stop and ask.
- ❌ Do NOT modify files outside the scope listed in `plan.md` § Project Structure. Touching adjacent screens, services, or modules "while you're at it" is scope creep.
- ❌ Do NOT introduce auth/RBAC or audit-log calls that don't already exist in the router you're editing. If a principle violation is pre-existing, `plan.md` documents it — do not "fix" it as a side quest.
- ❌ Do NOT invent endpoints, model fields, service methods, or widget APIs. If you're about to type `SomeService.foo()`, first Read `some_service.dart` and confirm `foo` exists with that signature. If not, check `tasks.md` — the task will tell you to create it, or it was a hallucination.
- ❌ Do NOT swallow errors with broad `try/except` or `catch (_)`. Let the root cause surface. Fix it or stop and ask.
- ❌ Do NOT copy the spec's pseudocode or TypeScript-ish examples literally — translate them to the target language's idioms (Python/Dart).
- ❌ Do NOT mark a task complete until its verification step has passed (typecheck + running call / browser exercise).
- ❌ Do NOT force-push. Do not amend pushed commits. Do not run destructive git commands (`reset --hard`, `clean -fd`, `checkout .`) without explicit user approval.
- ❌ Do NOT commit secrets, `.env` files, or `backend/version.json`.

---

## Behavior loop (run this for EVERY task — no shortcuts)

### Before touching a file

1. Read the WHOLE file you're about to edit. Not a grep snippet — the whole file, or at minimum the target function + ~30 lines of surrounding context.
2. Read one SIMILAR existing feature in the same file/module to learn conventions: error-handling style, naming, service return shapes, theme-token usage, widget composition.
3. For backend tasks, read the real DB schema (`list_tables`, or the migration). Never guess column names. If DB disagrees with spec, DB wins — stop and ask.
4. For frontend tasks, read the existing model/service/screen to confirm import paths, theme tokens, widget patterns. Don't invent imports.

### While editing

5. In one sentence, state what you're changing and why. If the "why" isn't a direct clause from `tasks.md` or the spec, STOP and ask.
6. Make the smallest edit that satisfies the task. If you find yourself refactoring nearby code, STOP — that's scope creep.
7. Never fabricate an API you haven't read. Confirm signatures exist.
8. No try/except for can't-happen cases. No defensive null checks at internal call sites.

### After editing, before commit

9. Re-read your own diff end-to-end. Check:
   - imports — all resolved, none unused
   - types — parameters, returns, model field types match what callers expect
   - naming — consistent with surrounding code (camelCase vs snake_case, AppColors vs hardcoded hex)
   - nullability — every `?` / `Optional` defended at use site where needed
   - did you delete anything that's still referenced?
10. Compile / typecheck / run the affected surface:
    - **Backend**: `uvicorn` starts cleanly; `curl` the modified endpoint; confirm response shape matches `contracts/api.md` byte-for-byte for fields.
    - **Frontend**: `flutter analyze` is clean; `flutter run` the PWA; exercise the changed path in the browser.
    - **Migration**: the migration applies cleanly; `list_tables` shows the expected column/index.
11. Only commit after 9 and 10 both pass. If anything fails, fix the root cause. Do NOT catch/swallow/comment-out the failure.

### Commit

12. Message: `spec <NNN>: T00X — <verb> <object>`.
13. Check `- [ ]` → `- [x]` in `tasks.md` in the same commit.
14. If a pre-commit hook fails, the commit did not happen — fix the issue, re-stage, and create a NEW commit. Do NOT `--amend` to work around hook failures.

---

## Anti-patterns (the common LLM failure modes — recognize and avoid)

If you catch yourself reaching for any of these, STOP and re-read `tasks.md`:

- ❌ "I'll add a TODO comment for the rest." → No. Finish the task or ask.
- ❌ "I'll wrap this in try/except to be safe." → No. Fix the root cause.
- ❌ "I'll define a helper since this might be useful later." → No. YAGNI.
- ❌ "Let me also clean up this unrelated thing." → No. Scope.
- ❌ "I'll add a compatibility shim for the old shape." → No. Additive-only is the norm; existing shape is already preserved unless the spec says otherwise.
- ❌ "The test won't pass — I'll modify the test." → No. Fix the code.
- ❌ Marking a task done without running step 10.
- ❌ Inventing field names, endpoint paths, widget names.
- ❌ Copying the spec's example code literally into Dart/Python without translation.
- ❌ "Let me re-architect this module while I'm here." → No. Hard no.

---

## Project-specific gotchas

### Supabase / PostgREST

- `is_("col", "null")` checks NULL; `.eq("col", None)` does NOT. Match existing query style.
- Unique indexes treat NULL as distinct by default — the `COALESCE(col, sentinel)` pattern is used intentionally when the spec calls for it.
- `ON DELETE CASCADE` is visible in the migration, not inferred by the app layer.

### FastAPI / Pydantic

- Response dicts must be JSON-safe: no raw UUIDs, no `datetime` without `.isoformat()`. Follow existing `result.data[0]` conventions.
- `Optional[str] = None` on request models is how "field may be omitted" is expressed — the client sends it or not.
- Raise `HTTPException(status_code=NNN, detail="...")` — match existing 400/404/409 style in the router you're in.

### Flutter

- Theming: use `AppColors.*` / `AppShadows.*` / `AppTheme.*` from `frontend/lib/theme/app_theme.dart`.
- Bottom sheets on tall content: `showModalBottomSheet(isScrollControlled: true, ...)` with `DraggableScrollableSheet` inside the builder. Match that pattern.
- Dart null-safety: every `json['foo']` from the wire is nullable. Defend: `json['foo'] ?? ''` / `?? 0` / etc.
- `_` prefix on widget names = private to file. Match existing visibility conventions.

### PWA / web deploy

- Deploy via `./scripts/deploy_frontend.sh`. Do not invoke `flutter build web` directly — the script handles Nginx, versioning, and cache busting.
- URL handling in the app uses `openInNewTab()` from `download_helper_web.dart` via conditional import — never `url_launcher`.

---

## When done

1. Every task in `tasks.md` is checked off.
2. `git log` shows clean per-task commits on the feature branch.
3. Every section of `quickstart.md` passes a manual run against the deployed build.
4. Leave a short summary on the branch tip: *"Ready for Claude Code review, spec NNN."*

Then **stop**. Do not open a PR. Do not merge. The user hands the branch to Claude Code for a `superpowers:code-reviewer` pass, which may produce follow-up tasks before the PR opens.

---

## One-line starter prompt for the user

> "Read OPENCODE.md end-to-end, then implement spec NNN in `specs/NNN-slug/`. Follow `tasks.md` in order. Commit per task with the message format in OPENCODE.md. Stop after every task to verify (step 10). Do not open a PR."
