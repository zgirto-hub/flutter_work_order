# flutter_work_order Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-24

## Active Technologies

- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, `services.ai_providers.resolver` (existing), `services.ollama_generator` (existing); `http`, `supabase_flutter`, Flutter Material (frontend)
- Department-scoped file visibility: `files.department_id` FK, `GET /api/files/list`, `GET /api/files/{id}`, `PATCH /api/files/{id}/department`, `GET /api/departments/mine`, `backend/utils/file_visibility.py`
- Department auto-assignment on upload: Non-admin users (Technician/Reporter/Supervisor/Superintendent) have `department_id` auto-assigned from their profile; the department picker is hidden for non-admins and shown only for Admins; `GET /api/departments/mine` returns `is_admin` and `primary_department_id`; non-admins without a department are blocked (disabled upload button + server 400); server silently discards any client-supplied `department_id` from non-admins

## Project Structure

```text
backend/
frontend/
tests/
```

## Commands

cd backend; pytest; ruff check .

## Code Style

Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend): Follow standard conventions

## Recent Changes

- 094-dept-auto-assign: Department auto-assignment on upload — non-admin `department_id` auto-assigned from profile, department picker hidden for non-admins, `GET /api/departments/mine` returns `is_admin` + `primary_department_id`, server overrides `department_id` for non-admins, non-admins without department blocked (disabled upload button + server 400)
- 092-dept-file-visibility: Added `files.department_id` column, department-scoped visibility endpoints, `file_visibility.py` helper, frontend department badge + scope label, upload department picker, `PATCH /files/{id}/department`
- 091-ai-work-order-toggle: Added Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, `services.ai_providers.resolver` (existing), `services.ollama_generator` (existing); `http`, `supabase_flutter`, Flutter Material (frontend)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
