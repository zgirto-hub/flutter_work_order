# Data Model: Version-File Based PWA Update Detection

**Feature**: 017-pwa-version-update | **Date**: 2026-04-05

## Entities

### Version File (version.json)

A static JSON file generated at deploy time and served from the web root.

| Field | Type | Description |
|-------|------|-------------|
| releaseId | Integer (Unix timestamp) | Unique identifier for the deployment, seconds since epoch |
| version | String (semver) | Application version (e.g., "1.11.6") — retained for backward compatibility |
| build | String (integer) | Build number (e.g., "106") — retained for backward compatibility |

**Identity**: The `releaseId` is the primary comparison key. It changes on every deployment.

**Lifecycle**: Created by deploy script → uploaded to server → fetched by client on load and on each update check → replaced on next deployment.

### Seeded ReleaseId (in-memory)

A JavaScript variable holding the releaseId fetched on page load.

| State | Description |
|-------|-------------|
| `null` | Initial fetch failed or not yet attempted. Update checks are skipped. |
| `<integer>` | Successfully seeded. Used as baseline for all comparisons. |

**Lifecycle**: Set once on page load → read on every update check → cleared on page reload.

### Update Status (Dart enum)

The result of a version comparison check.

| Value | Condition |
|-------|-----------|
| `available` | Remote releaseId differs from seeded releaseId |
| `upToDate` | Remote releaseId matches seeded releaseId |
| `error` | Fetch failed, response malformed, or seeded value is null |

## Relationships

```
Deploy Script --generates--> version.json --served by--> Nginx (no-cache)
                                              |
Page Load --fetches--> version.json --seeds--> Seeded ReleaseId (memory)
                                              |
Update Check --fetches--> version.json --compares with--> Seeded ReleaseId
                                              |
                                        UpdateStatus enum
                                              |
                              available --> fires callback --> Dart UI
                              upToDate --> no action
                              error --> no action (graceful)
```

## State Transitions

```
[Page Load]
    |
    v
Fetch version.json ──success──> Seeded (releaseId stored)
    |                                |
    fail                        [Check Triggered]
    |                                |
    v                                v
Unseeded (null)              Fetch version.json
    |                          /        |        \
    v                    available   upToDate    error
Skip checks              fire cb    no-op       no-op
                            |
                     [User Applies]
                            |
                            v
                    Show overlay + reload (single-fire)
```

## No Database Changes

This feature operates entirely in the browser runtime and deploy pipeline. No Supabase tables, columns, or migrations are involved.
