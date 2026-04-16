from fastapi import (
    APIRouter,
    UploadFile,
    File,
    Form,
    HTTPException,
    BackgroundTasks,
    Query,
)
import os
import uuid
from db import supabase
from utils.activity import log_activity
from services.document_service import index_document, delete_document, reindex_document

router = APIRouter(prefix="/documents", tags=["documents"])

UPLOAD_DIR = "uploaded_files"
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB


def _admin_check(user_email: str):
    """Shared admin check pattern."""
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


@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    display_name: str = Form(...),
    uploaded_by: str = Form(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(uploaded_by)

    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are accepted")

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413, detail="File too large. Maximum size is 50 MB"
        )

    file_id = str(uuid.uuid4())
    filename = f"{file_id}.pdf"
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
            "id, display_name, filename, status, error_message, total_pages, total_chunks, indexed_at, uploaded_by, created_at"
        )
        .order("created_at", desc=True)
        .execute()
    )

    return resp.data


@router.get("/{document_id}/status")
async def get_document_status(document_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    resp = (
        supabase.table("knowledge_documents")
        .select("id, status, total_chunks, error_message")
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

    display_name = doc_resp.data["display_name"]

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

    display_name = doc_resp.data["display_name"]

    supabase.table("knowledge_documents").update(
        {
            "status": "indexing",
            "error_message": None,
        }
    ).eq("id", document_id).execute()

    background_tasks.add_task(reindex_document, document_id)

    log_activity(user_email, "document", "reindexed", display_name, str(document_id))

    return {
        "document_id": document_id,
        "status": "indexing",
        "message": "Re-indexing started",
    }
