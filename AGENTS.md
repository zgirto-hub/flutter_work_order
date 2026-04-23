# flutter_work_order Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-23

## Active Technologies

- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, `services.ai_providers.resolver` (existing), `services.ollama_generator` (existing); `http`, `supabase_flutter`, Flutter Material (frontend)
- Department-scoped file visibility: `files.department_id` FK, `GET /api/files/list`, `GET /api/files/{id}`, `PATCH /api/files/{id}/department`, `GET /api/departments/mine`, `backend/utils/file_visibility.py`

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

- 092-dept-file-visibility: Added `files.department_id` column, department-scoped visibility endpoints, `file_visibility.py` helper, frontend department badge + scope label, upload department picker, `PATCH /files/{id}/department`
- 091-ai-work-order-toggle: Added Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, `services.ai_providers.resolver` (existing), `services.ollama_generator` (existing); `http`, `supabase_flutter`, Flutter Material (frontend)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
