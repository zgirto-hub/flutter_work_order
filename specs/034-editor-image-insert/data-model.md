# Data Model: Editor Image Insertion

**Feature**: 034-editor-image-insert  
**Date**: 2026-04-08

## Entities

### Letter Image (Filesystem Only)

Letter images are stored as files on the server filesystem. No database table is created — the image reference lives solely in the letter body HTML as an `<img src="...">` tag.

**Storage Location**: `backend/uploaded_files/letters/`

**Filename Pattern**: `letter_img_{YYYYMMDDHHMMSS}_{uuid8}.{ext}`

**Attributes**:

| Attribute | Description | Constraints |
|-----------|-------------|-------------|
| filename | Unique generated filename | `letter_img_` prefix + timestamp + UUID |
| extension | File format | One of: png, jpg, jpeg, gif, webp |
| file_path | Server filesystem path | `uploaded_files/letters/{filename}` |
| public_url | URL for HTTP access | `/files/letters/{filename}` |
| width | Image width in pixels | Max 1920px (auto-resized) |
| file_size | Size in bytes | Max 5MB (enforced pre-upload) |
| compression | JPEG/WebP quality | 80% when resized |

### Existing Entity: Generated Letter (Modified Usage)

The `generated_letters` table is NOT modified. The `body_text` column already stores the full HTML of the letter body. After this feature, `body_text` may contain `<img>` tags referencing `/files/letters/letter_img_*` URLs.

**Impact**: No schema migration required.

## Relationships

```
generated_letters.body_text (HTML) --contains--> <img src="/files/letters/letter_img_...">
                                                          |
                                                          v
                                              uploaded_files/letters/letter_img_...
```

- One letter body can reference zero or many inline images
- One image file can be referenced by one letter (no sharing across letters in practice, though not enforced)
- Deleting a letter does NOT delete the image files (orphan cleanup is out of scope)

## State Transitions

Letter images have no state — they are static files once uploaded. The lifecycle is:

1. **Created**: File uploaded via `POST /api/letters-v2/upload-image`, saved to filesystem
2. **Referenced**: URL embedded in letter body HTML via `<img>` tag
3. **Rendered**: Displayed in editor preview and converted to data URI for PDF generation
4. **Orphaned** (optional): If letter is deleted or image removed from body, file remains on disk

## Validation Rules

| Rule | Enforcement Point | Behavior |
|------|-------------------|----------|
| File format whitelist (png, jpg, jpeg, gif, webp) | Client + Server | Reject with error message |
| Max file size 5MB | Client + Server | Reject before/during upload |
| Max width 1920px | Server | Auto-resize with Pillow, preserve aspect ratio |
| Compression 80% quality | Server | Applied during resize (JPEG/WebP output) |
| Soft limit 10 images per letter | Client | Warning displayed, user can proceed |
