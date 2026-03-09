print("=== THIS MAIN.PY IS RUNNING v2 ===")

from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from supabase import create_client, Client
import os
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
):

    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower()

    filename = f"{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    # Save file
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    # Store relative path
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
    }).execute()

    return {
        "status": "success",
        "file_url": public_url
    }

# --------------------
# Delete Endpoint
# --------------------
@app.delete("/api/delete/{doc_id}")
async def delete_document(doc_id: str):

    # Get file path from DB
    response = supabase.table("documents") \
        .select("file_path") \
        .eq("id", doc_id) \
        .execute()

    if not response.data:
        return {"error": "Document not found"}

    file_path = response.data[0]["file_path"]

    # Delete file from disk
    if file_path:
        filename = os.path.basename(file_path)
        absolute_path = os.path.join(UPLOAD_DIR, filename)

        print("DELETE DEBUG")
        print("Path:", absolute_path)

        if os.path.exists(absolute_path):
            os.remove(absolute_path)
            print("File deleted")

    # Delete DB record
    supabase.table("documents") \
        .delete() \
        .eq("id", doc_id) \
        .execute()

    return {"status": "deleted"}
