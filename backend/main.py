print("=== THIS MAIN.PY IS RUNNING v1.4 ===")

from fastapi import FastAPI, UploadFile, File, Form, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from supabase import create_client, Client
import os
import json
import uuid
import unicodedata
from datetime import datetime
from PyPDF2 import PdfReader
from docx import Document
import pytesseract
from pdf2image import convert_from_path


# --------------------
# Supabase Config
# --------------------
SUPABASE_URL = "https://rydrqsjofoulwdtwfbgv.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5ZHJxc2pvZm91bHdkdHdmYmd2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjE0MTg5MiwiZXhwIjoyMDg3NzE3ODkyfQ.HvebR7mHIz2Dp4HRiLf6nVrzbqgeIX5XLc3NuVexwII"  # VERY IMPORTANT

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
# --------------------
# FastAPI Setup
# --------------------
app = FastAPI()



UPLOAD_DIR = "uploaded_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------
# Check for Update 
# --------------------

@app.get("/api/version")
def get_version():
    with open("version.json") as f:
        return json.load(f)



# --------------------
# Arabic Normalization
# --------------------
def normalize_arabic(text):
    text = unicodedata.normalize("NFKC", text)
    return text

# --------------------
# Text Extraction
# --------------------
def extract_text(file_path, extension):

    text = ""

    # ---- PDF ----
    if extension == "pdf":
        try:
            reader = PdfReader(file_path)

            for page in reader.pages:
                extracted = page.extract_text()
                if extracted:
                    text += extracted

            # OCR fallback for scanned PDFs
            if not text.strip():
                images = convert_from_path(file_path)

                for img in images:
                    text += pytesseract.image_to_string(
                        img,
                        lang="ara+eng"
                    )

        except Exception:
            images = convert_from_path(file_path)

            for img in images:
                text += pytesseract.image_to_string(
                    img,
                    lang="ara+eng"
                )

    # ---- DOCX ----
    elif extension == "docx":
        doc = Document(file_path)

        for para in doc.paragraphs:
            text += para.text + "\n"

    # ---- TXT ----
    elif extension == "txt":
        with open(file_path, "r", encoding="utf-8") as f:
            text = f.read()

    # ---- IMAGE OCR ----
    elif extension in ["jpg", "jpeg", "png"]:
        try:
            text = pytesseract.image_to_string(
                file_path,
                lang="ara+eng"
            )
        except Exception:
            text = ""

    return normalize_arabic(text)

# --------------------
# Upload Endpoint
# --------------------
@app.post("/api/upload")
async def upload_file(
    file: UploadFile = File(...),
    title: str = Form(...),
    document_type: str = Form(...),
    is_private: bool = Form(False),
    uploaded_by: str = Form(...)
):

    print("UPLOAD DEBUG -> private:", is_private)
    print("UPLOAD DEBUG -> uploaded_by:", uploaded_by)

    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower()

    filename = f"{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    # Save file
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    # Public URL
    public_url = f"/files/{filename}"

    # Extract text
    parsed_text = extract_text(file_path, extension)

    supabase.table("documents").insert({
        "title": title,
        "document_type": document_type,
        "file_name": file.filename,
        "file_extension": extension,
        "mime_type": file.content_type,
        "file_path": public_url,
        "parsed_text": parsed_text,
        "is_private": is_private,
        "uploaded_by": uploaded_by
    }).execute()

    return {
        "status": "success",
        "file_url": public_url
    }
# --------------------
# Delete Endpoint
# --------------------

@app.delete("/api/delete/{doc_id}")
async def delete_document(
    doc_id: str,
    user_email: str = Query(...)
):

    print("DELETE DEBUG -> user_email:", user_email)

    response = supabase.table("documents") \
        .select("file_path, uploaded_by") \
        .eq("id", doc_id) \
        .execute()

    if not response.data:
        return {"error": "Document not found"}

    doc = response.data[0]

    owner = doc["uploaded_by"]

    print("DELETE DEBUG -> owner:", owner)

    if owner != user_email:
        raise HTTPException(
            status_code=403,
            detail="You are not allowed to delete this document"
        )

    print("DELETE ALLOWED")

    file_path = doc["file_path"]

    if file_path:
        filename = os.path.basename(file_path)
        absolute_path = os.path.join(UPLOAD_DIR, filename)

        if os.path.exists(absolute_path):
            os.remove(absolute_path)

    supabase.table("documents") \
        .delete() \
        .eq("id", doc_id) \
        .execute()

    return {"status": "deleted"}


# --------------------
# Share Endpoint
# --------------------

@app.post("/api/share-document")
async def share_document(
    document_id: str = Form(...),
    owner_email: str = Form(...),
    share_with: str = Form(...)
):

    print("SHARE DEBUG -> doc:", document_id)
    print("SHARE DEBUG -> owner:", owner_email)
    print("SHARE DEBUG -> share_with:", share_with)

    # Check document owner
    response = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", document_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="Document not found")

    owner = response.data[0]["uploaded_by"]

    # Only owner can share
    if owner != owner_email:
        raise HTTPException(
            status_code=403,
            detail="Only the owner can share this document"
        )

    # Prevent sharing with yourself
    if owner_email == share_with:
        raise HTTPException(
            status_code=400,
            detail="You already own this document"
        )

    # Check if already shared
    existing = supabase.table("document_permissions") \
        .select("id") \
        .eq("document_id", document_id) \
        .eq("user_email", share_with) \
        .execute()

    if existing.data:
        raise HTTPException(
            status_code=400,
            detail="Document already shared with this user"
        )

    # Insert permission
    supabase.table("document_permissions").insert({
        "document_id": document_id,
        "user_email": share_with
    }).execute()

    return {"status": "document shared"}

# --------------------
# List Shared Users
# --------------------

@app.get("/api/document-shares/{doc_id}")
async def get_document_shares(doc_id: str):

    response = supabase.table("document_permissions") \
        .select("user_email") \
        .eq("document_id", doc_id) \
        .execute()

    if not response.data:
        return {"users": []}

    users = [row["user_email"] for row in response.data]

    return {
        "users": users
    }