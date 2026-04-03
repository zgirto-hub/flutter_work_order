# flutter_work_order Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-03

## Active Technologies
- Dart 3.x / Flutter 3.x + `pdf` ^3.10.7 (existing), `printing` ^5.12.0 (existing), `htmltopdfwidgets` (NEW) (002-use-html-css)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, Flutter Material (frontend) (006-edit-resolve-date)
- Supabase (PostgreSQL) — `system_status_reports` table (006-edit-resolve-date)
- Dart 3.x / Flutter 3.x + Flutter Material, GoogleFonts, app_theme.dart (centralized theme) (007-increase-font-size)
- N/A (no data changes) (007-increase-font-size)
- Dart 3.x / Flutter 3.x + Flutter Material, GoogleFonts, app_theme.dart (centralized theme), ThemeController (007-increase-font-size)
- SharedPreferences (already used by ThemeController for fontScale persistence) (007-increase-font-size)
- Dart 3.x / Flutter 3.x + Flutter Material, MediaQuery.textScaler (008-fix-status-font-scale)
- Dart 3.x / Flutter 3.x (frontend), Bash (deploy scripts), Nginx (server config) + Flutter Web (canvaskit renderer), OneSignal SDK, Supabase, Nginx (009-optimize-pwa-launch)
- N/A (no data model changes) (009-optimize-pwa-launch)

- Dart 3.x / Flutter 3.x + Flutter Material, fl_chart, supabase_flutter, app_theme (001-status-cards-redesign)

## Project Structure

```text
backend/
frontend/
tests/
```

## Commands

# Add commands for Dart 3.x / Flutter 3.x

## Code Style

Dart 3.x / Flutter 3.x: Follow standard conventions

## Recent Changes
- 009-optimize-pwa-launch: Added Dart 3.x / Flutter 3.x (frontend), Bash (deploy scripts), Nginx (server config) + Flutter Web (canvaskit renderer), OneSignal SDK, Supabase, Nginx
- 008-fix-status-font-scale: Added Dart 3.x / Flutter 3.x + Flutter Material, MediaQuery.textScaler
- 007-increase-font-size: Added Dart 3.x / Flutter 3.x + Flutter Material, GoogleFonts, app_theme.dart (centralized theme), ThemeController


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
