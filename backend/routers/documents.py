import logging
from datetime import datetime, timezone
from fastapi import (
    APIRouter,
    UploadFile,
    File,
    Form,
    HTTPException,
    BackgroundTasks,
    Query,
)
from pydantic import BaseModel
import os
import uuid
from typing import Optional
from db import supabase
from utils.activity import log_activity
from services.document_service import index_document, delete_document, reindex_document
from services.ollama_embedder import embed_single
from services.contextual_prefix import apply_contextual_prefix

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/documents", tags=["documents"])


def _get_document_title(document_id: str) -> str:
    """Fetch display_name for contextual embedding prefix."""
    resp = supabase.table("knowledge_documents").select("display_name").eq("id", document_id).maybe_single().execute()
    return resp.data.get("display_name", "") if resp.data else ""

UPLOAD_DIR = "uploaded_files"
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB


# --- Pydantic request bodies (Fix 7: avoid query params for content) ---


class ChunkAddBody(BaseModel):
    parent_id: str
    content: str
    user_email: str
    insert_after: Optional[int] = None


class ChunkUpdateBody(BaseModel):
    content: str
    user_email: str


# --- Helpers ---


def _admin_check(user_email: str):
    """Shared admin check pattern (replicated from manuals.py)."""
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", user_email)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})


def _reindex_siblings(document_id: str, parent_id: str):
    """Reindex chunk_index for all children of a given parent, ordered by current index."""
    siblings = (
        supabase.table("document_chunks")
        .select("id, chunk_index")
        .eq("document_id", document_id)
        .eq("parent_id", parent_id)
        .order("chunk_index")
        .execute()
    )
    for i, s in enumerate(siblings.data or []):
        if s.get("chunk_index") != i:
            supabase.table("document_chunks").update({"chunk_index": i}).eq(
                "id", s["id"]
            ).execute()


# --- Migration status (module-level state) ---

_migration_status = {
    "status": "idle",
    "completed": 0,
    "total": 0,
    "failed": [],
    "current": "",
}


# ============================================================
# IMPORTANT: Specific path routes MUST come before parameterized
# /{document_id} routes to avoid FastAPI route shadowing.
# ============================================================


# --- Document CRUD ---


@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    display_name: str = Form(...),
    uploaded_by: str = Form(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(uploaded_by)

    ALLOWED_EXTENSIONS = {"pdf", "docx", "txt", "md"}
    extension = file.filename.split(".")[-1].lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail="Unsupported file type. Accepted: PDF, DOCX, TXT, MD",
        )

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413, detail="File too large. Maximum size is 50 MB"
        )

    file_id = str(uuid.uuid4())
    filename = f"{file_id}.{extension}"
    manuals_dir = os.path.join(UPLOAD_DIR, "manuals")
    os.makedirs(manuals_dir, exist_ok=True)
    file_path = os.path.join(manuals_dir, filename)

    with open(file_path, "wb") as f:
        f.write(content)

    doc_row = {
        "filename": file.filename,
        "display_name": display_name,
        "file_path": file_path,
        "status": "pending",
        "uploaded_by": uploaded_by,
        "file_extension": extension,
    }
    resp = supabase.table("knowledge_documents").insert(doc_row).execute()
    document_id = resp.data[0]["id"]

    background_tasks.add_task(index_document, document_id, file_path)

    log_activity(uploaded_by, "document", "uploaded", display_name, str(document_id))

    return {
        "document_id": document_id,
        "status": "indexing",
        "message": f"Indexing started for '{display_name}'",
    }


@router.get("/")
async def list_documents(user_email: str = Query(...)):
    _admin_check(user_email)

    resp = (
        supabase.table("knowledge_documents")
        .select(
            "id, display_name, filename, status, error_message, total_pages, "
            "total_chunks, preprocessing_progress, indexed_at, uploaded_by, created_at, file_extension"
        )
        .order("created_at", desc=True)
        .execute()
    )

    return resp.data


# --- Migration endpoints (BEFORE parameterized routes to avoid shadowing) ---


@router.post("/migrate-all")
async def migrate_all_documents(
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(user_email)

    global _migration_status

    manuals_resp = supabase.table("manuals").select("*").execute()
    all_manuals = manuals_resp.data or []

    if not all_manuals:
        return {"status": "completed", "total_manuals": 0}

    _migration_status = {
        "status": "migrating",
        "completed": 0,
        "total": len(all_manuals),
        "failed": [],
        "current": "",
    }

    background_tasks.add_task(_run_migration, all_manuals, user_email)

    return {"status": "migrating", "total_manuals": len(all_manuals)}


async def _run_migration(all_manuals: list, user_email: str):
    """Background task: processes manuals sequentially with progress tracking."""
    global _migration_status

    for i, manual in enumerate(all_manuals):
        _migration_status["current"] = manual.get("title", "")
        _migration_status["completed"] = i

        try:
            # Build file path from manual ID + extension (manuals table has no file_path column)
            file_ext = manual.get("file_extension", "pdf")
            file_path = os.path.join(
                "uploaded_files", "manuals", f"{manual['id']}.{file_ext}"
            )
            if not os.path.exists(file_path):
                _migration_status["failed"].append(
                    {"id": manual["id"], "error": f"File not found: {file_path}"}
                )
                continue

            # Resolve uploaded_by UUID to email
            uploader_email = user_email
            if manual.get("uploaded_by"):
                user_resp = (
                    supabase.table("users")
                    .select("email")
                    .eq("id", manual["uploaded_by"])
                    .maybe_single()
                    .execute()
                )
                if user_resp.data:
                    uploader_email = user_resp.data["email"]

            doc_row = {
                "filename": manual.get("file_name", ""),
                "display_name": manual.get("title", ""),
                "file_path": file_path,
                "status": "pending",
                "uploaded_by": uploader_email,
                "file_extension": file_ext,
            }
            doc_resp = supabase.table("knowledge_documents").insert(doc_row).execute()
            doc_id = doc_resp.data[0]["id"]

            await index_document(doc_id, file_path)

            _migration_status["completed"] = i + 1

        except Exception as e:
            logger.error("Migration failed for manual %s: %s", manual["id"], e)
            _migration_status["failed"].append({"id": manual["id"], "error": str(e)})

    _migration_status["status"] = (
        "completed_with_errors" if _migration_status["failed"] else "completed"
    )

    log_activity(user_email, "document", "migrated", f"{len(all_manuals)} manuals", "")


@router.get("/migration-status")
async def get_migration_status(user_email: str = Query(...)):
    _admin_check(user_email)
    return _migration_status


@router.delete("/migrate-cleanup")
async def migrate_cleanup(user_email: str = Query(...)):
    _admin_check(user_email)

    if _migration_status.get("status") not in ("completed", "completed_with_errors"):
        raise HTTPException(status_code=400, detail="Migration not completed")

    manuals_resp = supabase.table("manuals").select("id", count="exact").execute()
    manuals_count = manuals_resp.count or 0

    chunks_resp = supabase.table("manual_chunks").select("id", count="exact").execute()
    chunks_count = chunks_resp.count or 0

    supabase.table("manual_chunks").delete().neq("id", "").execute()
    supabase.table("manuals").delete().neq("id", "").execute()

    supabase.table("manual_corpus_stats").update(
        {"manual_count": 0, "total_chunks": 0}
    ).eq("id", 1).execute()

    log_activity(user_email, "document", "cleanup", f"{manuals_count} manuals", "")

    return {"deleted_manuals": manuals_count, "deleted_chunks": chunks_count}


# --- Parameterized document routes (AFTER specific paths) ---


@router.get("/{document_id}/status")
async def get_document_status(document_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    resp = (
        supabase.table("knowledge_documents")
        .select(
            "id, status, total_chunks, total_pages, preprocessing_progress, error_message"
        )
        .eq("id", document_id)
        .maybe_single()
        .execute()
    )

    if not resp.data:
        raise HTTPException(status_code=404, detail="Document not found")

    return {
        "document_id": resp.data["id"],
        "status": resp.data["status"],
        "total_chunks": resp.data["total_chunks"],
        "total_pages": resp.data.get("total_pages"),
        "preprocessing_progress": resp.data.get("preprocessing_progress", 0),
        "error_message": resp.data["error_message"],
    }


@router.delete("/{document_id}")
async def delete_document_endpoint(document_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    doc_resp = (
        supabase.table("knowledge_documents")
        .select("display_name")
        .eq("id", document_id)
        .maybe_single()
        .execute()
    )
    if not doc_resp.data:
        raise HTTPException(status_code=404, detail="Document not found")

    display_name = doc_resp.data.get("display_name", "")
    await delete_document(document_id)

    log_activity(user_email, "document", "deleted", display_name, str(document_id))

    return {"deleted": True}


@router.post("/{document_id}/reindex")
async def reindex_document_endpoint(
    document_id: str,
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(user_email)

    doc_resp = (
        supabase.table("knowledge_documents")
        .select("display_name")
        .eq("id", document_id)
        .maybe_single()
        .execute()
    )
    if not doc_resp.data:
        raise HTTPException(status_code=404, detail="Document not found")

    supabase.table("knowledge_documents").update(
        {"status": "indexing", "error_message": None}
    ).eq("id", document_id).execute()

    background_tasks.add_task(reindex_document, document_id)

    log_activity(
        user_email,
        "document",
        "reindexed",
        doc_resp.data.get("display_name", ""),
        str(document_id),
    )

    return {
        "document_id": document_id,
        "status": "indexing",
        "message": "Re-indexing started",
    }


# --- Chunk CRUD ---


@router.get("/{document_id}/chunks")
async def list_chunks(
    document_id: str,
    user_email: str = Query(...),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    _admin_check(user_email)

    # Get total count
    count_resp = (
        supabase.table("document_chunks")
        .select("id", count="exact")
        .eq("document_id", document_id)
        .execute()
    )
    total = count_resp.count or 0

    # Get paginated chunks ordered by parent then child index
    offset = (page - 1) * page_size
    resp = (
        supabase.table("document_chunks")
        .select(
            "id, chunk_type, parent_id, chunk_index, section_title, "
            "content, page_number, embedding_stale, created_at"
        )
        .eq("document_id", document_id)
        .order("chunk_index")
        .range(offset, offset + page_size - 1)
        .execute()
    )

    chunks = []
    for c in resp.data or []:
        chunk = {
            "id": c["id"],
            "chunk_type": c.get("chunk_type"),
            "parent_id": c.get("parent_id"),
            "chunk_index": c.get("chunk_index"),
            "section_title": c.get("section_title"),
            "content": c.get("content", ""),
            "page_number": c.get("page_number"),
            "char_count": len(c.get("content", "")),
            "embedding_stale": c.get("embedding_stale", False),
        }
        # Add children_count for parent chunks
        if c.get("chunk_type") == "parent":
            children = (
                supabase.table("document_chunks")
                .select("id", count="exact")
                .eq("parent_id", c["id"])
                .execute()
            )
            chunk["children_count"] = children.count or 0
        chunks.append(chunk)

    return {"chunks": chunks, "total": total, "page": page, "page_size": page_size}


@router.post("/{document_id}/chunks")
async def add_chunk(document_id: str, body: ChunkAddBody):
    _admin_check(body.user_email)

    parent_id = body.parent_id
    content = body.content
    insert_after = body.insert_after

    # Verify parent exists
    parent_resp = (
        supabase.table("document_chunks")
        .select("id, page_number, section_title")
        .eq("id", parent_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not parent_resp.data:
        raise HTTPException(status_code=404, detail="Parent chunk not found")

    # Determine chunk_index
    siblings = (
        supabase.table("document_chunks")
        .select("id, chunk_index")
        .eq("document_id", document_id)
        .eq("parent_id", parent_id)
        .order("chunk_index")
        .execute()
    )
    if insert_after is not None and insert_after >= 0:
        new_index = insert_after + 1
        # Shift siblings after insertion point
        for s in siblings.data or []:
            if s.get("chunk_index", 0) >= new_index:
                supabase.table("document_chunks").update(
                    {"chunk_index": s["chunk_index"] + 1}
                ).eq("id", s["id"]).execute()
    else:
        new_index = len(siblings.data or [])

    # Embed the new chunk with contextual prefix
    embedding_str = None
    embedding_stale = False
    try:
        doc_title = _get_document_title(document_id)
        prefixed = apply_contextual_prefix(content, doc_title, parent_resp.data.get("section_title"))
        emb = await embed_single(prefixed)
        embedding_str = "[" + ",".join(str(x) for x in emb) + "]"
    except Exception:
        embedding_stale = True

    row = {
        "document_id": document_id,
        "chunk_type": "child",
        "parent_id": parent_id,
        "section_title": parent_resp.data.get("section_title"),
        "content": content,
        "page_number": parent_resp.data.get("page_number"),
        "chunk_index": new_index,
        "embedding_stale": embedding_stale,
    }
    if embedding_str:
        row["embedding"] = embedding_str

    resp = supabase.table("document_chunks").insert(row).execute()

    log_activity(body.user_email, "chunk", "added", content[:50], resp.data[0]["id"])

    return {
        "id": resp.data[0]["id"],
        "chunk_index": new_index,
        "embedding_stale": embedding_stale,
    }


@router.get("/{document_id}/chunks/{chunk_id}")
async def get_chunk(document_id: str, chunk_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    resp = (
        supabase.table("document_chunks")
        .select(
            "id, chunk_type, parent_id, chunk_index, section_title, "
            "content, page_number, embedding_stale"
        )
        .eq("id", chunk_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Chunk not found")

    chunk = resp.data
    return {
        "id": chunk["id"],
        "chunk_type": chunk.get("chunk_type"),
        "parent_id": chunk.get("parent_id"),
        "chunk_index": chunk.get("chunk_index"),
        "section_title": chunk.get("section_title"),
        "content": chunk.get("content", ""),
        "page_number": chunk.get("page_number"),
        "char_count": len(chunk.get("content", "")),
        "embedding_stale": chunk.get("embedding_stale", False),
    }


@router.put("/{document_id}/chunks/{chunk_id}")
async def update_chunk(document_id: str, chunk_id: str, body: ChunkUpdateBody):
    _admin_check(body.user_email)

    resp = (
        supabase.table("document_chunks")
        .select("id, chunk_type, section_title")
        .eq("id", chunk_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Chunk not found")

    chunk_type = resp.data.get("chunk_type")
    update_data = {"content": body.content}

    if chunk_type == "child":
        # Re-embed child chunk with contextual prefix
        try:
            doc_title = _get_document_title(document_id)
            prefixed = apply_contextual_prefix(body.content, doc_title, resp.data.get("section_title"))
            emb = await embed_single(prefixed)
            embedding_str = "[" + ",".join(str(x) for x in emb) + "]"
            update_data["embedding"] = embedding_str
            update_data["embedding_stale"] = False
        except Exception:
            update_data["embedding_stale"] = True
    # Parent chunks: just update content, no embedding

    supabase.table("document_chunks").update(update_data).eq("id", chunk_id).execute()

    log_activity(body.user_email, "chunk", "updated", body.content[:50], chunk_id)

    return {
        "id": chunk_id,
        "chunk_type": chunk_type,
        "embedding_stale": update_data.get("embedding_stale", False),
    }


@router.delete("/{document_id}/chunks/{chunk_id}")
async def delete_chunk(document_id: str, chunk_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    resp = (
        supabase.table("document_chunks")
        .select("id, parent_id, chunk_type")
        .eq("id", chunk_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Chunk not found")

    parent_id = resp.data.get("parent_id")
    chunk_type = resp.data.get("chunk_type")

    # If deleting a parent, explicitly delete children first (before CASCADE)
    if chunk_type == "parent":
        supabase.table("document_chunks").delete().eq("parent_id", chunk_id).execute()

    # Delete the chunk itself
    supabase.table("document_chunks").delete().eq("id", chunk_id).execute()

    # Reindex siblings if this was a child chunk
    if parent_id:
        _reindex_siblings(document_id, parent_id)

    log_activity(user_email, "chunk", "deleted", "", chunk_id)

    return {"deleted": True}


@router.post("/{document_id}/chunks/{chunk_id}/split")
async def split_chunk(
    document_id: str,
    chunk_id: str,
    split_position: int = Query(...),
    user_email: str = Query(...),
):
    _admin_check(user_email)

    resp = (
        supabase.table("document_chunks")
        .select("id, parent_id, content, chunk_index, section_title, page_number")
        .eq("id", chunk_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Chunk not found")

    content = resp.data.get("content", "")
    if split_position <= 0 or split_position >= len(content):
        raise HTTPException(status_code=400, detail="Invalid split position")

    parent_id = resp.data.get("parent_id")
    current_index = resp.data.get("chunk_index", 0)
    first_content = content[:split_position]
    second_content = content[split_position:]

    # Embed both halves with contextual prefix
    first_emb_str = None
    first_stale = False
    second_emb_str = None
    second_stale = False
    doc_title = _get_document_title(document_id)
    section_title = resp.data.get("section_title")

    try:
        prefixed_first = apply_contextual_prefix(first_content, doc_title, section_title)
        first_emb = await embed_single(prefixed_first)
        first_emb_str = "[" + ",".join(str(x) for x in first_emb) + "]"
    except Exception:
        first_stale = True

    try:
        prefixed_second = apply_contextual_prefix(second_content, doc_title, section_title)
        second_emb = await embed_single(prefixed_second)
        second_emb_str = "[" + ",".join(str(x) for x in second_emb) + "]"
    except Exception:
        second_stale = True

    # Shift siblings after current index to make room
    siblings = (
        supabase.table("document_chunks")
        .select("id, chunk_index")
        .eq("document_id", document_id)
        .eq("parent_id", parent_id)
        .order("chunk_index")
        .execute()
    )
    for s in siblings.data or []:
        if (s.get("chunk_index") or 0) > current_index:
            supabase.table("document_chunks").update(
                {"chunk_index": s["chunk_index"] + 1}
            ).eq("id", s["id"]).execute()

    # Delete original chunk
    supabase.table("document_chunks").delete().eq("id", chunk_id).execute()

    # Insert first half at current_index
    first_row = {
        "document_id": document_id,
        "chunk_type": "child",
        "parent_id": parent_id,
        "section_title": resp.data.get("section_title"),
        "content": first_content,
        "page_number": resp.data.get("page_number"),
        "chunk_index": current_index,
        "embedding_stale": first_stale,
    }
    if first_emb_str:
        first_row["embedding"] = first_emb_str
    first_resp = supabase.table("document_chunks").insert(first_row).execute()

    # Insert second half at current_index + 1
    second_row = {
        "document_id": document_id,
        "chunk_type": "child",
        "parent_id": parent_id,
        "section_title": resp.data.get("section_title"),
        "content": second_content,
        "page_number": resp.data.get("page_number"),
        "chunk_index": current_index + 1,
        "embedding_stale": second_stale,
    }
    if second_emb_str:
        second_row["embedding"] = second_emb_str
    second_resp = supabase.table("document_chunks").insert(second_row).execute()

    log_activity(user_email, "chunk", "split", "", chunk_id)

    return {
        "chunks": [
            {"id": first_resp.data[0]["id"], "content": first_content[:100]},
            {"id": second_resp.data[0]["id"], "content": second_content[:100]},
        ]
    }


@router.post("/{document_id}/chunks/{chunk_id}/merge")
async def merge_chunk(
    document_id: str,
    chunk_id: str,
    user_email: str = Query(...),
):
    _admin_check(user_email)

    # Get the chunk to merge
    resp = (
        supabase.table("document_chunks")
        .select("id, parent_id, content, chunk_index, section_title, page_number")
        .eq("id", chunk_id)
        .eq("document_id", document_id)
        .maybe_single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Chunk not found")

    parent_id = resp.data.get("parent_id")
    current_index = resp.data.get("chunk_index", 0)

    # Find next sibling with same parent
    next_resp = (
        supabase.table("document_chunks")
        .select("id, content, parent_id")
        .eq("document_id", document_id)
        .eq("parent_id", parent_id)
        .eq("chunk_index", current_index + 1)
        .maybe_single()
        .execute()
    )
    if not next_resp.data:
        raise HTTPException(status_code=400, detail="No adjacent sibling to merge with")
    if next_resp.data.get("parent_id") != parent_id:
        raise HTTPException(
            status_code=400, detail="Cannot merge chunks from different parents"
        )

    # Combine content
    combined_content = resp.data["content"] + "\n\n" + next_resp.data["content"]

    # Embed combined content with contextual prefix
    embedding_str = None
    embedding_stale = False
    try:
        doc_title = _get_document_title(document_id)
        prefixed = apply_contextual_prefix(combined_content, doc_title, resp.data.get("section_title"))
        emb = await embed_single(prefixed)
        embedding_str = "[" + ",".join(str(x) for x in emb) + "]"
    except Exception:
        embedding_stale = True

    # Update the first chunk with combined content
    update_data = {
        "content": combined_content,
        "embedding_stale": embedding_stale,
    }
    if embedding_str:
        update_data["embedding"] = embedding_str

    supabase.table("document_chunks").update(update_data).eq("id", chunk_id).execute()

    # Delete the second chunk
    supabase.table("document_chunks").delete().eq("id", next_resp.data["id"]).execute()

    # Reindex siblings
    _reindex_siblings(document_id, parent_id)

    log_activity(user_email, "chunk", "merged", combined_content[:50], chunk_id)

    return {
        "id": chunk_id,
        "content": combined_content[:100],
        "embedding_stale": embedding_stale,
    }


@router.post("/{document_id}/chunks/re-embed")
async def re_embed_all_chunks(
    document_id: str,
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(user_email)

    # Count children for response
    children_resp = (
        supabase.table("document_chunks")
        .select("id", count="exact")
        .eq("document_id", document_id)
        .eq("chunk_type", "child")
        .execute()
    )
    total_children = children_resp.count or 0

    async def _re_embed_task():
        doc_resp = (
            supabase.table("knowledge_documents")
            .select("display_name")
            .eq("id", document_id)
            .maybe_single()
            .execute()
        )
        display_name = doc_resp.data["display_name"] if doc_resp.data else ""

        chunks_resp = (
            supabase.table("document_chunks")
            .select("id, content, section_title")
            .eq("document_id", document_id)
            .eq("chunk_type", "child")
            .execute()
        )
        for chunk in chunks_resp.data or []:
            try:
                prefixed = apply_contextual_prefix(
                    content=chunk["content"],
                    doc_title=display_name,
                    section_title=chunk.get("section_title"),
                )
                emb = await embed_single(prefixed)
                emb_str = "[" + ",".join(str(x) for x in emb) + "]"
                supabase.table("document_chunks").update(
                    {"embedding": emb_str, "embedding_stale": False}
                ).eq("id", chunk["id"]).execute()
            except Exception:
                supabase.table("document_chunks").update({"embedding_stale": True}).eq(
                    "id", chunk["id"]
                ).execute()

        # Spec 080: bump updated_at so validated_qa entries derived from
        # this document surface in the "Needs Review" queue
        supabase.table("knowledge_documents").update(
            {"updated_at": datetime.now(timezone.utc).isoformat()}
        ).eq("id", document_id).execute()

    background_tasks.add_task(_re_embed_task)

    log_activity(user_email, "document", "re-embed started", "", document_id)

    return {"status": "re-embedding", "total_children": total_children}


@router.delete("/{document_id}/chunks/bulk-delete")
async def bulk_delete_chunks(
    document_id: str,
    chunk_ids: str = Query(...),
    user_email: str = Query(...),
):
    _admin_check(user_email)

    import json

    try:
        chunk_id_list = json.loads(chunk_ids)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid chunk_ids format")

    if not isinstance(chunk_id_list, list):
        raise HTTPException(status_code=400, detail="chunk_ids must be a JSON array")

    # Collect parent_ids for reindexing
    parent_ids = set()
    for cid in chunk_id_list:
        chunk_resp = (
            supabase.table("document_chunks")
            .select("parent_id")
            .eq("id", cid)
            .eq("document_id", document_id)
            .maybe_single()
            .execute()
        )
        if chunk_resp.data and chunk_resp.data.get("parent_id"):
            parent_ids.add(chunk_resp.data["parent_id"])

    # Delete all specified chunks
    for cid in chunk_id_list:
        supabase.table("document_chunks").delete().eq("id", cid).eq(
            "document_id", document_id
        ).execute()

    # Reindex affected parents
    for pid in parent_ids:
        _reindex_siblings(document_id, pid)

    log_activity(
        user_email, "chunk", "bulk-deleted", f"{len(chunk_id_list)} chunks", document_id
    )

    return {"deleted": len(chunk_id_list)}
