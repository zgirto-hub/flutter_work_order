# API Contract: Upload Letter Image

## Endpoint

```
POST /api/letters-v2/upload-image
Content-Type: multipart/form-data
```

## Request

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| file | File (binary) | Yes | Image file to upload |

**Accepted formats**: PNG, JPG, JPEG, GIF, WebP  
**Max file size**: 5MB

## Response — Success (200)

```json
{
  "status": "success",
  "url": "/files/letters/letter_img_20260408143022_a1b2c3d4.png"
}
```

| Field | Type | Description |
|-------|------|-------------|
| status | string | Always "success" |
| url | string | Server-relative URL path to the uploaded image |

## Response — Validation Error (400)

```json
{
  "detail": "File size exceeds 5MB limit"
}
```

```json
{
  "detail": "Unsupported file format. Accepted: png, jpg, jpeg, gif, webp"
}
```

## Response — Server Error (500)

```json
{
  "detail": "Failed to process image"
}
```

## Server-Side Processing

1. Validate file extension against whitelist
2. Validate file size <= 5MB
3. Generate unique filename: `letter_img_{YYYYMMDDHHMMSS}_{uuid8}.{ext}`
4. If image width > 1920px: resize to 1920px width (preserve aspect ratio), compress to 80% quality
5. Save to `uploaded_files/letters/{filename}`
6. Return URL path

## PostMessage Protocol (Iframe ↔ Flutter)

| Direction | Message Format | Description |
|-----------|---------------|-------------|
| Iframe → Flutter | `INSERT_IMAGE_REQUEST` | User clicked image button |
| Flutter → Iframe | `INSERT_IMAGE:/files/letters/{filename}` | Upload succeeded, insert at cursor |
| Flutter → Iframe | `INSERT_IMAGE_ERROR:{message}` | Upload failed, display error |

## HTML Output (Inserted in Editor)

```html
<img src="/files/letters/letter_img_20260408143022_a1b2c3d4.png" style="max-width: 100%;">
```

## PDF Generation (Data URI Conversion)

During PDF generation, `<img src="/files/letters/...">` tags in `body_html` are converted to base64 data URIs before passing to WeasyPrint:

```html
<img src="data:image/png;base64,iVBOR..." style="max-width: 100%;">
```
