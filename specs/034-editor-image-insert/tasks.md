# Tasks: Editor Image Insertion

**Input**: Design documents from `/specs/034-editor-image-insert/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/upload-image.md

**Tests**: Not requested — manual testing only.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: No new projects or dependencies needed — all dependencies exist. Phase is empty.

*(No tasks — Pillow, FilePicker, http, and WeasyPrint already in place.)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend upload endpoint that all user stories depend on.

**⚠️ CRITICAL**: US1 and US3 cannot begin until T001 is complete.

- [X] T001 Add `POST /letters-v2/upload-image` endpoint in `backend/routers/letters_v2.py`
- [X] T002 [P] Add `uploadImage()` method in `frontend/lib/services/letter_service.dart`

**Checkpoint**: Backend accepts image uploads and returns URLs; frontend service can call the endpoint.

---

## Phase 3: User Story 1 — Insert Image into Letter Body (Priority: P1) 🎯 MVP

**Goal**: User clicks toolbar button, selects image, image appears inline at cursor position in the editor.

**Independent Test**: Open letter editor → place cursor → click "Insert Image" → select PNG → image appears at cursor → save letter → reopen → image still there.

### Implementation for User Story 1

- [X] T003 [US1] Add "Insert Image" button to editor toolbar HTML in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [X] T004 [US1] Add JS message handlers for `INSERT_IMAGE` and `INSERT_IMAGE_ERROR` in iframe JS in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [X] T005 [US1] Add `INSERT_IMAGE_REQUEST` handler and `_uploadImage()` method in Flutter `_listenForMessages()` in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [X] T006 [US1] Add activity logging for image upload in `backend/routers/letters_v2.py`

**Checkpoint**: Full image insertion flow works end-to-end. Images persist in saved letters.

---

## Phase 4: User Story 2 — Image Validation and Error Handling (Priority: P2)

**Goal**: Invalid files (wrong format, too large) are rejected with clear error messages on both client and server.

**Independent Test**: Try uploading a .pdf file → error shown. Try a 6MB image → error shown. Try during network failure → error shown, editor unchanged.

### Implementation for User Story 2

- [X] T007 [US2] Add client-side validation (format + 5MB size check) before upload in `_uploadImage()` in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [X] T008 [US2] Add soft limit warning when image count exceeds 10 in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

**Checkpoint**: All validation paths produce clear error messages without disrupting editor state.

---

## Phase 5: User Story 3 — Images in Generated PDF (Priority: P1)

**Goal**: Inline images in letter body HTML are rendered correctly in the generated PDF via WeasyPrint.

**Independent Test**: Insert image(s) into letter body → generate PDF → open PDF → images appear at correct positions with proper sizing.

### Implementation for User Story 3

- [X] T009 [US3] Add `_convert_body_images_to_data_uris()` helper function in `backend/routers/letters_v2.py`
- [X] T010 [US3] Integrate `_convert_body_images_to_data_uris()` into `_build_letter_pdf_v2()` in `backend/routers/letters_v2.py`

**Checkpoint**: PDFs contain all inline images at correct positions with proper scaling.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T011 Add loading indicator in editor during image upload in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: T001 and T002 can run in parallel (different files)
- **Phase 3 (US1)**: Depends on T001 + T002. T003 and T004 can run in parallel (same file but different sections — toolbar HTML vs JS).
- **Phase 4 (US2)**: Depends on T005 (needs `_uploadImage()` to exist). T007 and T008 are independent.
- **Phase 5 (US3)**: Depends on T001 (needs images on filesystem). Independent of US1/US2 frontend work.
- **Phase 6 (Polish)**: Depends on T005.

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational (T001, T002)
- **US2 (P2)**: Depends on US1 (T005 — needs `_uploadImage()`)
- **US3 (P1)**: Depends on Foundational (T001) only — can run in parallel with US1 frontend work

### Parallel Opportunities

- T001 + T002 (different files: backend vs frontend service)
- T003 + T004 (same file but toolbar HTML section vs JS section — independent edits)
- T009 + T003/T004/T005 (backend PDF work vs frontend editor work)
- T007 + T008 (independent validation checks)

---

## Parallel Example: Foundational Phase

```
# These can run in parallel (different files):
T001: Backend upload endpoint in backend/routers/letters_v2.py
T002: Frontend uploadImage() in frontend/lib/services/letter_service.dart
```

## Parallel Example: US1 + US3

```
# After T001+T002 complete, these can run in parallel:
T003-T005: Frontend editor toolbar + postMessage (US1)
T009-T010: Backend PDF data URI conversion (US3)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete T001 + T002 (Foundational)
2. Complete T003-T006 (US1 — image insertion)
3. **STOP and VALIDATE**: Insert image, save letter, reopen, verify persistence
4. Deploy/demo if ready

### Incremental Delivery

1. T001 + T002 → Backend + service ready
2. T003-T006 → Image insertion works (MVP!)
3. T007-T008 → Validation + error handling
4. T009-T010 → PDF rendering
5. T011 → Loading indicator polish

---

## Task Details & Implementation Prompts

### T001: Backend Upload Endpoint

**File**: `backend/routers/letters_v2.py`
**What to add**: New endpoint `POST /letters-v2/upload-image` that accepts multipart file upload, validates format (png/jpg/jpeg/gif/webp) and size (<=5MB), resizes with Pillow if width > 1920px (80% quality), saves to `uploaded_files/letters/`, returns `{"status": "success", "url": "/files/letters/{filename}"}`.
**Function signature**: `async def upload_letter_image(file: UploadFile = File(...)) -> dict`
**Input**: Multipart file upload
**Output**: `{"status": "success", "url": "/files/letters/letter_img_YYYYMMDDHHMMSS_uuid8.ext"}`
**Dependencies**: None
**Acceptance criteria**: Endpoint accepts valid images, returns URL; rejects non-image files with 400; rejects >5MB with 400; resizes images >1920px width; saved files accessible at `/files/letters/` URL.

---

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Python/FastAPI developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py

Task: Add a new endpoint `POST /letters-v2/upload-image` to the existing router. The endpoint:
1. Accepts a single multipart file upload parameter: `file: UploadFile = File(...)`
2. Validates file extension is in (png, jpg, jpeg, gif, webp) — return HTTP 400 with `{"detail": "Unsupported file format. Accepted: png, jpg, jpeg, gif, webp"}` if invalid
3. Reads file bytes and validates size <= 5MB (5 * 1024 * 1024 bytes) — return HTTP 400 with `{"detail": "File size exceeds 5MB limit"}` if too large
4. Opens image with PIL (Pillow) `Image.open(io.BytesIO(file_bytes))`
5. If image width > 1920: resize to width=1920, height=proportional, using `Image.LANCZOS` resampling
6. Saves to `_uploads` directory (already defined as `os.path.join(os.path.dirname(__file__), "..", "uploaded_files", "letters")`) with filename pattern: `letter_img_{timestamp}_{uuid8}.{ext}` where timestamp is `datetime.now().strftime("%Y%m%d%H%M%S")` and uuid8 is `uuid.uuid4().hex[:8]`
7. For save: if extension in (jpg, jpeg): save as JPEG with quality=80. If png: save as PNG. If gif: save as GIF. If webp: save as WebP with quality=80.
8. Returns `{"status": "success", "url": f"/files/letters/{filename}"}`

Signatures required:
```python
@router.post("/letters-v2/upload-image")
async def upload_letter_image(file: UploadFile = File(...)) -> dict:
```

Constraints:
- Add `import uuid` and `from PIL import Image` to existing imports at top of file (uuid and Image are not yet imported)
- Use existing `_uploads` variable (line 172) for save directory — do NOT create a new directory variable
- Place the endpoint AFTER the existing `_save_attachments` function (after line 192) and BEFORE `_build_letter_pdf_v2` (line 195)
- Wrap image processing in try/except to return HTTP 500 with `{"detail": "Failed to process image"}` on unexpected errors
- Use `io.BytesIO` for in-memory image manipulation (io is already imported)
- The `File` import from fastapi is already present in the imports

Acceptance criteria:
- `POST /api/letters-v2/upload-image` with a valid PNG under 5MB returns 200 with `{"status": "success", "url": "/files/letters/letter_img_..."}`
- Uploading a .txt file returns 400 with unsupported format message
- Uploading a 6MB image returns 400 with size limit message
- A 3000px wide image is saved at 1920px width with aspect ratio preserved
- A 1000px wide image is saved as-is (no resize)
--- END PROMPT T001 ---

---

### T002: Frontend Upload Service Method

**File**: `frontend/lib/services/letter_service.dart`
**What to add**: New method `uploadImage(Uint8List bytes, String filename)` that sends multipart POST to `/letters-v2/upload-image` and returns the image URL string.
**Function signature**: `Future<String> uploadImage(Uint8List bytes, String filename) async`
**Input**: Raw image bytes and original filename
**Output**: Server URL path string (e.g., `/files/letters/letter_img_...`)
**Dependencies**: None
**Acceptance criteria**: Method sends multipart request, parses JSON response, returns URL string. Throws on non-200 status.

---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/services/letter_service.dart

Task: Add a new method `uploadImage` to the existing `LetterService` class. The method:
1. Creates a `http.MultipartRequest('POST', uri)` where uri is `Uri.parse('${AppConfig.baseUrl}/letters-v2/upload-image')`
2. Adds the file as `http.MultipartFile.fromBytes('file', bytes, filename: filename)`
3. Sends the request and reads the response
4. If status == 200, parses the JSON body and returns `response['url']` as a `String`
5. If status != 200, throws an `Exception` with the error detail from the response body

Signatures required:
```dart
Future<String> uploadImage(Uint8List bytes, String filename) async
```

Constraints:
- Use existing imports (`http`, `dart:convert`, `dart:typed_data`, `AppConfig`) — no new imports needed
- Follow the same error handling pattern as `generateV2` method
- Place the method after the `generateV2` method in the class
- Do NOT use `_email` or authentication headers — the endpoint does not require them

Acceptance criteria:
- Calling `uploadImage(pngBytes, 'photo.png')` sends a multipart POST to `/api/letters-v2/upload-image`
- Returns the URL string (e.g., `/files/letters/letter_img_20260408143022_a1b2c3d4.png`) on success
- Throws Exception with server error message on failure
--- END PROMPT T002 ---

---

### T003: Editor Toolbar Image Button

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: An "Insert Image" button (camera icon 📷) in the toolbar HTML, positioned before the zoom dropdown, with a separator.
**Dependencies**: None (HTML-only change in the `_editorHtml` string constant)
**Acceptance criteria**: Button visible in toolbar. Clicking it calls `parent.postMessage("INSERT_IMAGE_REQUEST", "*")`.

---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert HTML/JavaScript developer working inside a Dart string constant.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (embedded HTML/JS)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: In the `_editorHtml` string constant, add an "Insert Image" button to the toolbar. Insert it BEFORE the zoom dropdown `<select id="zoomSelect"` and its preceding `<div class="sep"></div>`.

Find this exact HTML in the _editorHtml string:
```html
  <button onclick="clearFormatting()" title="Clear formatting">&#9108;</button>
  <div class="sep"></div>
  <select id="zoomSelect"
```

Replace with:
```html
  <button onclick="clearFormatting()" title="Clear formatting">&#9108;</button>
  <div class="sep"></div>
  <button onclick="requestInsertImage()" title="Insert Image">&#128247;</button>
  <div class="sep"></div>
  <select id="zoomSelect"
```

Then add the `requestInsertImage()` JavaScript function in the `<script>` section, BEFORE the `window.addEventListener("message"` line:
```javascript
function requestInsertImage(){parent.postMessage("INSERT_IMAGE_REQUEST","*");}
```

Constraints:
- Use HTML entity &#128247; for the camera emoji (📷)
- The button must match existing toolbar button style (no extra classes needed — inherits from `.toolbar button` CSS)
- The JS function must be a single line, placed with the other function definitions
- Do NOT modify any existing buttons or functions

Acceptance criteria:
- Camera icon button visible in toolbar between "Clear formatting" and "Zoom" dropdown
- Clicking the button sends `INSERT_IMAGE_REQUEST` postMessage to parent window
--- END PROMPT T003 ---

---

### T004: Iframe JS Message Handlers for Image Insertion

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: In the iframe JS message listener, handle `INSERT_IMAGE:` and `INSERT_IMAGE_ERROR:` messages from Flutter parent.
**Dependencies**: T003 (same file, different section)
**Acceptance criteria**: Receiving `INSERT_IMAGE:{url}` inserts an `<img>` tag at cursor. Receiving `INSERT_IMAGE_ERROR:{msg}` shows an alert.

---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert JavaScript developer working inside a Dart string constant.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (embedded JavaScript in HTML string)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: In the `_editorHtml` string constant, modify the existing `window.addEventListener("message", ...)` handler to add two new message types. The current handler code is:

```javascript
window.addEventListener("message", function(e) {
  if (e.data === "GET_HTML") {
    var html = document.getElementById("editor").innerHTML || "";
    parent.postMessage("EDITOR_HTML:" + html, "*");
  } else if (typeof e.data === "string" && e.data.startsWith("SET_HTML:")) {
    document.getElementById("editor").innerHTML = e.data.substring(9);
  }
});
```

Add two new `else if` branches AFTER the `SET_HTML:` branch and BEFORE the closing `});`:

1. `INSERT_IMAGE:` — extracts the URL after the colon, focuses the editor, and inserts an `<img>` tag at the current cursor position using `document.execCommand("insertHTML", false, imgTag)` where `imgTag` is `'<img src="' + url + '" style="max-width:100%;">'`. Note: Use the `AppConfig.downloadUrl` base to build the full URL. Actually, the URL from the server is relative (`/files/letters/...`), so just use it as-is since the editor iframe can resolve it relative to the app origin.

   Actually, since the iframe uses `srcdoc`, relative URLs won't resolve. The Flutter side will send the FULL absolute URL (including the server base). So just use the URL as received.

2. `INSERT_IMAGE_ERROR:` — extracts the error message after the colon and shows it via `alert(msg)`.

The updated handler should be:
```javascript
window.addEventListener("message", function(e) {
  if (e.data === "GET_HTML") {
    var html = document.getElementById("editor").innerHTML || "";
    parent.postMessage("EDITOR_HTML:" + html, "*");
  } else if (typeof e.data === "string" && e.data.startsWith("SET_HTML:")) {
    document.getElementById("editor").innerHTML = e.data.substring(9);
  } else if (typeof e.data === "string" && e.data.startsWith("INSERT_IMAGE:")) {
    var url = e.data.substring(13);
    document.getElementById("editor").focus();
    document.execCommand("insertHTML", false, '<img src="' + url + '" style="max-width:100%;">');
  } else if (typeof e.data === "string" && e.data.startsWith("INSERT_IMAGE_ERROR:")) {
    alert(e.data.substring(19));
  }
});
```

Constraints:
- Modify ONLY the existing `window.addEventListener("message", ...)` block
- Preserve the existing `GET_HTML` and `SET_HTML:` handlers exactly as-is
- Use `document.execCommand("insertHTML")` to insert at cursor (matches existing table insertion pattern)
- Use `alert()` for error messages (simple, works in iframe context)
- The `<img>` tag must include `style="max-width:100%;"` for responsive sizing

Acceptance criteria:
- Sending `INSERT_IMAGE:https://server/files/letters/img.png` to the iframe inserts `<img src="https://server/files/letters/img.png" style="max-width:100%;">` at the current cursor position
- Sending `INSERT_IMAGE_ERROR:File too large` shows an alert with "File too large"
- Existing GET_HTML and SET_HTML handlers still work correctly
--- END PROMPT T004 ---

---

### T005: Flutter postMessage Handler and Upload Flow

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: Handle `INSERT_IMAGE_REQUEST` in `_listenForMessages()`, add `_uploadImage()` method that opens FilePicker, uploads via LetterService, and sends result back to iframe.
**Function signatures**: `Future<void> _uploadImage() async`
**Dependencies**: T002 (uploadImage service method), T004 (iframe handlers)
**Acceptance criteria**: Clicking toolbar image button opens file picker, successful upload sends `INSERT_IMAGE:{fullUrl}` to iframe, failed upload sends `INSERT_IMAGE_ERROR:{msg}`.

---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: Two changes in this file:

**Change 1**: In the `_listenForMessages()` method, add a new `else if` branch to handle `INSERT_IMAGE_REQUEST`. The current method ends with:
```dart
      } else if (str == 'EDITOR_READY' && _initialBodyHtml != null) {
        final cw = _editorIframe?.contentWindow;
        cw?.postMessage('SET_HTML:$_initialBodyHtml'.toJS, '*'.toJS);
        _initialBodyHtml = null;
      }
    });
  }
```

Add BEFORE the closing `});`:
```dart
      } else if (str == 'INSERT_IMAGE_REQUEST') {
        _uploadImage();
      }
```

So the full end of the method becomes:
```dart
      } else if (str == 'EDITOR_READY' && _initialBodyHtml != null) {
        final cw = _editorIframe?.contentWindow;
        cw?.postMessage('SET_HTML:$_initialBodyHtml'.toJS, '*'.toJS);
        _initialBodyHtml = null;
      } else if (str == 'INSERT_IMAGE_REQUEST') {
        _uploadImage();
      }
    });
  }
```

**Change 2**: Add a new `_uploadImage()` method to the State class. Place it AFTER the `_pickAttachments()` method. The method:

1. Opens FilePicker with `type: FileType.custom`, `allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp']`, `allowMultiple: false`, `withData: true`
2. If result is null or empty, return early
3. Gets the first file from result
4. If file.bytes is null, return early
5. Calls `LetterService().uploadImage(file.bytes!, file.name)` — use the existing `LetterService` (already imported)
6. On success, builds the full URL: `'${AppConfig.downloadUrl}$url'` where `url` is the returned relative path
7. Sends to iframe: `_editorIframe?.contentWindow?.postMessage('INSERT_IMAGE:$fullUrl'.toJS, '*'.toJS)`
8. On error (catch Exception), sends: `_editorIframe?.contentWindow?.postMessage('INSERT_IMAGE_ERROR:${e.toString()}'.toJS, '*'.toJS)`

```dart
Future<void> _uploadImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;
  final file = result.files.first;
  if (file.bytes == null) return;
  try {
    final url = await LetterService().uploadImage(file.bytes!, file.name);
    final fullUrl = '${AppConfig.downloadUrl}$url';
    _editorIframe?.contentWindow?.postMessage(
      'INSERT_IMAGE:$fullUrl'.toJS,
      '*'.toJS,
    );
  } catch (e) {
    _editorIframe?.contentWindow?.postMessage(
      'INSERT_IMAGE_ERROR:${e.toString()}'.toJS,
      '*'.toJS,
    );
  }
}
```

Constraints:
- Use existing imports: `FilePicker`, `LetterService`, `AppConfig` are all already imported
- Follow the same pattern as `_pickAttachments()` for FilePicker usage
- Use `AppConfig.downloadUrl` (not `baseUrl`) for building the full image URL — this is the URL the browser/iframe can reach (e.g., `http://localhost:8000` or production URL)
- Do NOT add any SnackBar or other UI feedback — errors go through the iframe postMessage channel

Acceptance criteria:
- Clicking the toolbar image button triggers `_uploadImage()` via the postMessage handler
- FilePicker opens filtered to image types only
- Successful upload sends `INSERT_IMAGE:https://server/files/letters/letter_img_...` to iframe
- Failed upload sends `INSERT_IMAGE_ERROR:...` to iframe
--- END PROMPT T005 ---

---

### T006: Activity Logging for Image Upload

**File**: `backend/routers/letters_v2.py`
**What to add**: Call `log_activity()` after successful image upload in the `upload_letter_image` endpoint.
**Dependencies**: T001
**Acceptance criteria**: Each successful image upload creates an activity log entry.

---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Python/FastAPI developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py

Task: In the `upload_letter_image` endpoint (added in T001), add a `log_activity()` call BEFORE the return statement. The `log_activity` function is already imported from `utils.activity`.

Add this line before the `return {"status": "success", ...}` line:
```python
    log_activity("system", "uploaded_image", "letter", filename)
```

Note: We use "system" as user_email because the upload endpoint does not receive user identity. The existing pattern uses positional args: `log_activity(user_email, action, category, target_label)`.

Constraints:
- `log_activity` is already imported (line 20: `from utils.activity import log_activity`)
- Follow the existing usage pattern: `log_activity(data.created_by_email, "created", "letter", str(letter_id))` (line 415)
- Single line addition, placed just before the return statement

Acceptance criteria:
- Each successful image upload creates an activity log entry with action "uploaded_image" and category "letter"
--- END PROMPT T006 ---

---

### T007: Client-Side Validation in Upload Flow

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: Add file size validation (5MB) in `_uploadImage()` before calling the service, with error feedback via postMessage.
**Dependencies**: T005
**Acceptance criteria**: Files >5MB are rejected client-side before upload with a clear error message.

---

--- IMPLEMENTATION PROMPT T007 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: In the `_uploadImage()` method (added in T005), add a file size check AFTER the `if (file.bytes == null) return;` line and BEFORE the `try {` block.

Add this validation:
```dart
  if (file.bytes!.lengthInBytes > 5 * 1024 * 1024) {
    _editorIframe?.contentWindow?.postMessage(
      'INSERT_IMAGE_ERROR:File exceeds 5MB limit. Please choose a smaller image.'.toJS,
      '*'.toJS,
    );
    return;
  }
```

Constraints:
- 5MB = 5 * 1024 * 1024 bytes
- Error message goes through the iframe postMessage channel (matching T005 error pattern)
- Do NOT add a SnackBar — keep all feedback in the iframe
- Place BEFORE the try/catch block so oversized files never reach the server

Acceptance criteria:
- Selecting a 6MB image shows "File exceeds 5MB limit" error in the editor (via alert from T004)
- Selecting a 4MB image proceeds to upload normally
- The 5MB check happens client-side, before any network request
--- END PROMPT T007 ---

---

### T008: Soft Limit Warning for Image Count

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: Track image count and show a warning dialog when exceeding 10 images.
**Dependencies**: T005
**Acceptance criteria**: After inserting 10 images, user sees a warning but can continue.

---

--- IMPLEMENTATION PROMPT T008 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: Add a soft limit of 10 images per letter with a warning dialog.

**Change 1**: Add an instance variable `int _imageCount = 0;` to the State class, near the other state variables (e.g., near `_attachments` list).

**Change 2**: In the `_uploadImage()` method, AFTER the size validation check (added in T007) and BEFORE the `try {` block, add an image count check:

```dart
  _imageCount++;
  if (_imageCount > 10) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image Limit Warning'),
        content: const Text(
          'This letter already has more than 10 images. '
          'Adding more may affect performance. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) {
      _imageCount--;
      return;
    }
  }
```

Constraints:
- Use a simple `int` counter — no need to parse the editor HTML to count images
- The counter resets naturally when the widget is recreated (navigating away and back)
- Use `showDialog<bool>` with AlertDialog (Flutter Material, already imported)
- If user cancels, decrement the counter and return without uploading
- Place AFTER size validation (T007) and BEFORE the `try {` block

Acceptance criteria:
- First 10 images insert without any warning
- 11th image shows a warning dialog with "Cancel" and "Continue" options
- Clicking "Cancel" does not upload the image
- Clicking "Continue" proceeds with the upload normally
--- END PROMPT T008 ---

---

### T009: Backend Data URI Conversion Helper

**File**: `backend/routers/letters_v2.py`
**What to add**: New helper function `_convert_body_images_to_data_uris(html: str) -> str` that finds `<img src="/files/letters/...">` tags and replaces the URL with a base64 data URI by reading the file from disk.
**Function signature**: `def _convert_body_images_to_data_uris(html: str) -> str`
**Input**: HTML string containing `<img>` tags with `/files/letters/` URLs
**Output**: HTML string with those URLs replaced by `data:image/{ext};base64,...` data URIs
**Dependencies**: T001 (images must exist on filesystem)
**Acceptance criteria**: All `/files/letters/letter_img_*` URLs in `<img>` tags are converted to data URIs. Missing files are silently skipped (tag left as-is).

---

--- IMPLEMENTATION PROMPT T009 ---
You are an expert Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py

Task: Add a new helper function `_convert_body_images_to_data_uris` that converts inline image URLs to base64 data URIs for WeasyPrint PDF rendering. Place it AFTER the `_sanitize_editor_html` function (after line ~58) and BEFORE `_build_letter_pdf_v2`.

```python
def _convert_body_images_to_data_uris(html: str) -> str:
    """Replace /files/letters/... image URLs with base64 data URIs for PDF rendering."""
    import mimetypes

    def _replace_img_src(match):
        rel_path = match.group(1)  # e.g., /files/letters/letter_img_20260408_abc.png
        # Strip leading /files/ to get filesystem path relative to uploaded_files/
        fs_rel = rel_path.lstrip("/").replace("files/", "", 1)
        abs_path = os.path.join(
            os.path.dirname(__file__), "..", "uploaded_files", fs_rel
        )
        if not os.path.exists(abs_path):
            return match.group(0)  # File missing — leave tag as-is
        mime, _ = mimetypes.guess_type(abs_path)
        if not mime:
            mime = "image/png"
        with open(abs_path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
        return f'src="data:{mime};base64,{data}"'

    # Match src="/files/letters/..." (with optional server prefix stripped by sanitizer)
    return re.sub(
        r'src="(?:https?://[^/]+)?(/files/letters/[^"]+)"',
        _replace_img_src,
        html,
    )
```

Constraints:
- Use `os`, `re`, `base64` which are all already imported
- Import `mimetypes` inline (standard library, no pip install needed)
- The regex must handle both relative URLs (`/files/letters/...`) and absolute URLs (`https://server/files/letters/...`) since the editor may store either form
- If the file doesn't exist on disk, leave the `<img>` tag unchanged (don't break PDF generation)
- Follow the pattern of `_logo_data_uri()` (line 31-38) for reading files and encoding to base64
- Place AFTER `_sanitize_editor_html` and BEFORE `_build_letter_pdf_v2`

Acceptance criteria:
- `<img src="/files/letters/letter_img_20260408_a1b2c3d4.png" style="max-width:100%;">` is converted to `<img src="data:image/png;base64,..." style="max-width:100%;">`
- `<img src="https://server/files/letters/letter_img_20260408_a1b2c3d4.png">` is also converted correctly
- If the referenced file doesn't exist, the tag is left unchanged
- Non-letter-image `<img>` tags (e.g., external URLs) are not modified
--- END PROMPT T009 ---

---

### T010: Integrate Data URI Conversion into PDF Generation

**File**: `backend/routers/letters_v2.py`
**What to add**: Call `_convert_body_images_to_data_uris()` on `body_html` inside `_build_letter_pdf_v2()`, after `_sanitize_editor_html()`.
**Dependencies**: T009
**Acceptance criteria**: Generated PDFs contain inline images rendered from data URIs.

---

--- IMPLEMENTATION PROMPT T010 ---
You are an expert Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py

Task: In the `_build_letter_pdf_v2` function, add a call to `_convert_body_images_to_data_uris()` on the body_html AFTER the `_sanitize_editor_html()` call.

Find the line in the template rendering where `body_html` is passed:
```python
body_html=_sanitize_editor_html(data.body_html),
```

Replace with:
```python
body_html=_convert_body_images_to_data_uris(_sanitize_editor_html(data.body_html)),
```

This chains the two transformations: first sanitize the HTML, then convert image URLs to data URIs.

Constraints:
- Single line change — wrap the existing `_sanitize_editor_html(data.body_html)` call with `_convert_body_images_to_data_uris()`
- Do NOT modify any other template variables
- Do NOT modify `_sanitize_editor_html` itself

Acceptance criteria:
- When generating a PDF for a letter containing inline images, the images appear in the PDF output
- Letters without inline images are unaffected (no regression)
- The sanitize step still runs first (font cleanup), then image conversion
--- END PROMPT T010 ---

---

### T011: Loading Indicator During Upload

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to add**: Show a loading placeholder in the editor during upload, replace with actual image on completion.
**Dependencies**: T004, T005
**Acceptance criteria**: User sees a "Uploading image..." indicator in the editor while upload is in progress.

---

--- IMPLEMENTATION PROMPT T011 ---
You are an expert Dart/Flutter developer working with embedded JavaScript.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (embedded JavaScript + Dart method)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart

Task: Add a loading indicator that appears in the editor at the cursor position during image upload.

**Change 1**: In the `_uploadImage()` method, BEFORE the `try {` block (and after the image count check from T008), send a loading placeholder to the iframe:

```dart
  _editorIframe?.contentWindow?.postMessage(
    'INSERT_IMAGE_LOADING'.toJS,
    '*'.toJS,
  );
```

**Change 2**: In the `_uploadImage()` catch block, also send a message to remove the loading placeholder:

After the `INSERT_IMAGE_ERROR` postMessage, add:
```dart
    _editorIframe?.contentWindow?.postMessage(
      'REMOVE_IMAGE_LOADING'.toJS,
      '*'.toJS,
    );
```

**Change 3**: In the iframe JS message listener (the `window.addEventListener("message", ...)` block), add two more handlers AFTER the `INSERT_IMAGE_ERROR:` handler:

```javascript
  } else if (e.data === "INSERT_IMAGE_LOADING") {
    document.getElementById("editor").focus();
    document.execCommand("insertHTML", false, '<span id="img-loading" style="display:inline-block;padding:8px 16px;background:#f0f0f0;border:1px dashed #999;border-radius:4px;color:#666;font-style:italic;">Uploading image...</span>');
  } else if (e.data === "REMOVE_IMAGE_LOADING") {
    var el = document.getElementById("img-loading");
    if (el) el.remove();
  }
```

**Change 4**: In the existing `INSERT_IMAGE:` handler, add removal of the loading placeholder BEFORE inserting the actual image:

Update the `INSERT_IMAGE:` handler to:
```javascript
  } else if (typeof e.data === "string" && e.data.startsWith("INSERT_IMAGE:")) {
    var url = e.data.substring(13);
    var ld = document.getElementById("img-loading");
    if (ld) ld.remove();
    document.getElementById("editor").focus();
    document.execCommand("insertHTML", false, '<img src="' + url + '" style="max-width:100%;">');
  }
```

Constraints:
- The loading placeholder uses a unique ID `img-loading` so it can be removed later
- Styled as a dashed-border inline block with "Uploading image..." text
- Removed automatically on both success (INSERT_IMAGE replaces it) and error (REMOVE_IMAGE_LOADING)
- Uses `document.execCommand("insertHTML")` to insert at cursor position (same as image insertion)
- Only one loading placeholder exists at a time (ID-based)

Acceptance criteria:
- When image upload starts, "Uploading image..." placeholder appears at cursor position in editor
- When upload succeeds, placeholder is replaced by the actual image
- When upload fails, placeholder is removed and error alert is shown
--- END PROMPT T011 ---

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- T003 + T004 modify the same file but different sections (toolbar HTML vs JS listener) — can be combined into one edit session
