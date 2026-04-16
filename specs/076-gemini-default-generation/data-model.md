# Data Model: 076 — Default Q&A Generation to Gemini Flash

**Date**: 2026-04-16

## Entities Modified

### app_settings (existing table, no schema change)

| Key | Old Default | New Default | Notes |
|-----|------------|-------------|-------|
| `ai_provider` | `"local"` | `"gemini"` | Seed value updated in migration file |

No new tables, columns, or relationships. The only data change is the seed value and the one-time runtime migration for existing deployments.

## State Transitions

```
Existing deployment startup:
  app_settings.ai_provider == "local"  →  "gemini"  (one-time migration)
  app_settings.ai_provider == "gemini" →  no change  (idempotent)
  app_settings.ai_provider == <other>  →  no change  (admin choice preserved)
  app_settings.ai_provider == NULL     →  no change  (resolver uses _DEFAULT_PROVIDER)

Fresh deployment:
  Seed inserts ai_provider = "gemini" directly
```

## No Migration File Needed

The existing migration `20260415_app_settings.sql` will have its seed value updated from `'local'` to `'gemini'`. No new migration file is required since:
- Supabase migrations run once per deployment
- The runtime lifespan handler handles existing data migration
