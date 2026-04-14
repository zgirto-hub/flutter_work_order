# Feature Specification: RAG Pipeline — Manual Knowledge Assistant

**Feature Branch**: `058-rag-pipeline`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "RAG Pipeline — Manual Knowledge Assistant: Backend services + API endpoints + Flutter service layer enabling the AI assistant to answer questions using uploaded technical manuals (PDF, DOCX, TXT) via local embedding, chunking, and generation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Upload a Technical Manual (Priority: P1)

A maintenance supervisor uploads a PDF technical manual for a navigation system so that technicians can later ask questions about it. The supervisor selects the file, provides a title, and submits it. The system processes the document — splitting it into searchable chunks and indexing them — then confirms the upload with the number of chunks created.

**Why this priority**: Without uploaded and indexed manuals, no queries can be answered. This is the foundational capability that all other stories depend on.

**Independent Test**: Can be fully tested by uploading a sample PDF and verifying a manual record is created with indexed chunks. Delivers value as a standalone document ingestion pipeline.

**Acceptance Scenarios**:

1. **Given** the system is running and the embedding service is available, **When** a user uploads a 10-page PDF with a title, **Then** the system returns a confirmation with the manual ID and a chunk count greater than zero.
2. **Given** a user attempts to upload an unsupported file type (e.g., .xlsx), **When** the upload is submitted, **Then** the system rejects the upload with a clear error message indicating the file type is not supported.
3. **Given** the embedding service is temporarily unavailable, **When** a user uploads a valid PDF, **Then** the system returns an appropriate error indicating the service is unavailable (not a cryptic internal error).

---

### User Story 2 - Ask a Question About a Manual (Priority: P1)

A technician working on equipment opens the AI assistant and types a question about a specific procedure (e.g., "What is the calibration interval for the ILS localizer?"). The system finds the most relevant passages from uploaded manuals, generates an answer using those passages as context, and displays the answer alongside source references (manual title and page number).

**Why this priority**: This is the core user-facing value — answering questions from manuals. Equal priority with upload because together they form the minimum viable feature.

**Independent Test**: Can be fully tested by querying against a pre-uploaded manual and verifying the answer references correct source material. Delivers immediate value to technicians seeking procedural information.

**Acceptance Scenarios**:

1. **Given** one or more manuals have been uploaded and indexed, **When** a user asks a question in Arabic, **Then** the system returns an answer in formal Arabic along with source chunks that include manual title, page number, and relevance score.
2. **Given** one or more manuals have been uploaded and indexed, **When** a user asks a question in English, **Then** the system returns an answer in English with corresponding source references.
3. **Given** no manuals have been uploaded (or the question has no relevant matches), **When** a user asks a question, **Then** the system returns a clear "no information found" message rather than fabricating an answer.
4. **Given** multiple manuals are uploaded, **When** a user asks a question without specifying a manual, **Then** the system searches across all manuals and returns the best matches.
5. **Given** a user asks a question targeting a specific manual, **When** the query is submitted with a manual filter, **Then** only chunks from that manual are searched.

---

### User Story 3 - Query from the Mobile App (Priority: P2)

A field technician using the Flutter PWA on a tablet queries the assistant while performing maintenance. The app sends the question to the backend, displays the answer, and shows which manual pages the answer came from — allowing the technician to look up the original source if needed.

**Why this priority**: Extends the query capability to the mobile/PWA frontend. Depends on the backend query endpoint (Story 2) being functional first.

**Independent Test**: Can be tested by calling the Flutter service method with a question and verifying a structured result (answer + source chunks) is returned and parseable by the app.

**Acceptance Scenarios**:

1. **Given** the backend query endpoint is operational, **When** the Flutter app sends a query via the service layer, **Then** the app receives a structured response containing the answer text and a list of source chunks with manual title, page number, content preview, and distance score.
2. **Given** the backend is unreachable or times out, **When** the Flutter app attempts a query, **Then** the app receives a descriptive error (not an unhandled crash) that can be displayed to the user.

---

### User Story 4 - Upload from the Mobile App (Priority: P2)

A supervisor uses the Flutter PWA to upload a new manual directly from their device. They select a file, enter a title, and the app handles the multipart upload to the backend, showing progress or completion status.

**Why this priority**: Completes the mobile experience by enabling uploads from the app, not just queries. Depends on the backend upload endpoint (Story 1).

**Independent Test**: Can be tested by calling the Flutter upload method with a file and verifying the backend returns a valid manual ID and chunk count.

**Acceptance Scenarios**:

1. **Given** the backend upload endpoint is operational, **When** the Flutter app submits a file via multipart upload, **Then** the app receives a structured response with manual ID, title, and chunk count.
2. **Given** a large file is being uploaded and embedded, **When** the process takes significant time, **Then** the app handles the long wait gracefully (extended timeout) without crashing or showing a false error.

---

### Edge Cases

- What happens when a PDF contains only images (no extractable text)? The system produces zero chunks and should either warn the user or return a zero-chunk confirmation.
- What happens when a DOCX file is corrupted or password-protected? The system should return a clear error rather than a server crash.
- What happens when a single page contains more text than the maximum chunk size? The chunking service splits it into multiple overlapping chunks preserving context.
- How does the system handle mixed Arabic and English text within the same document? Both languages are chunked correctly using bilingual sentence boundary detection.
- What happens if the embedding service returns vectors of an unexpected dimension? The system raises a specific error identifying the dimension mismatch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST accept file uploads in PDF, DOCX, and TXT formats and reject all other file types with a clear error message.
- **FR-002**: System MUST split uploaded documents into overlapping text chunks with configurable size and overlap, preserving page number references where available (PDF).
- **FR-003**: System MUST generate vector embeddings for each text chunk using a local embedding model and store them alongside the chunk content.
- **FR-004**: System MUST accept natural language questions and return answers generated from the most relevant manual chunks.
- **FR-005**: System MUST return source references (manual title, page number, content excerpt, relevance score) alongside every answer.
- **FR-006**: System MUST support querying across all manuals or filtered to a specific manual.
- **FR-007**: System MUST support both Arabic and English — for document chunking, question embedding, and answer generation — with correct handling of right-to-left text.
- **FR-008**: System MUST return a clear "no information found" response when no relevant chunks match a query, rather than generating an unsupported answer.
- **FR-009**: System MUST provide a Flutter service layer with methods for uploading manuals and querying the assistant, following existing service patterns.
- **FR-010**: System MUST handle service unavailability (embedding model down, generation model down) with specific, distinguishable error types — not generic 500 errors.
- **FR-011**: System MUST preserve all existing manual management endpoints (list, get, delete) without modification.

### Key Entities

- **Manual**: An uploaded document with a title, filename, file type, size, upload timestamp, and uploader reference. Parent of many chunks.
- **Manual Chunk**: A segment of text extracted from a manual, with a sequential index, optional source page number, text content, and a vector embedding. Belongs to one manual.
- **Query Result**: A transient response containing a generated answer and a list of source chunks with relevance scores. Not persisted.
- **Source Chunk Reference**: A pointer to a specific chunk used to generate an answer, including the manual title, page number, content excerpt, and distance/relevance score.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can upload a 50-page PDF manual and receive confirmation within 5 minutes.
- **SC-002**: Users receive an answer to a manual-related question within 30 seconds of submitting the query.
- **SC-003**: Answers include at least one source reference with manual title and page number for every successful query (where relevant chunks exist).
- **SC-004**: 100% of unsupported file types are rejected at upload time with a user-friendly error message.
- **SC-005**: When the AI service is unavailable, users see a specific "service unavailable" message rather than a generic error, within 5 seconds.
- **SC-006**: The mobile app can complete both upload and query operations without unhandled errors or crashes.

## Assumptions

- The local embedding model (nomic-embed-text) and generation model (gemma4:e2b) are pre-installed and running on the server via Ollama.
- The database schema (manuals, manual_chunks tables, RPC functions, pgvector index) is already deployed and functional — this feature builds application logic on top of it.
- The Flutter UI screens (upload screen, chat screen, rating widget) are out of scope and will be built as separate features consuming the service layer created here.
- File uploads are expected to be in the range of 1–100 pages; extremely large documents (500+ pages) are not a primary use case for this iteration.
- The existing `ollama_generator.py` service provides the `generate()` function used for answer generation, and it is already tested and operational.
- Users have network connectivity to the server (this is a web/PWA application).
