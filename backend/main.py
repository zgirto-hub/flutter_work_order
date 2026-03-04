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

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploaded_files")
os.makedirs(UPLOAD_DIR, exist_ok=True)

print("UPLOAD DIRECTORY:", UPLOAD_DIR)
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")


# --------------------
# Startup Banner
# --------------------
@app.on_event("startup")
async def startup_banner():

    banner = r"""
████████╗██╗ ██████╗██╗  ██╗███████╗████████╗
╚══██╔══╝██║██╔════╝██║ ██╔╝██╔════╝╚══██╔══╝
   ██║   ██║██║     █████╔╝ █████╗     ██║
   ██║   ██║██║     ██╔═██╗ ██╔══╝     ██║
   ██║   ██║╚██████╗██║  ██╗███████╗   ██║
   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝
"""

    print(banner)
    print("🎟  TICKETING SYSTEM API STARTED")
    print("📡 API URL: http://0.0.0.0:8000")
    print("📂 Upload Folder:", UPLOAD_DIR)
    print("🕒 Startup Time:", datetime.now())
    print("===============================================")


# --------------------
# CORS
# --------------------


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------
# Text Extraction (OCR Enabled)
# --------------------
def normalize_arabic(text):
    # Convert presentation forms to standard Arabic letters
    text = unicodedata.normalize("NFKC", text)
    return text
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

            # If empty → scanned PDF → use OCR
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

    # ---- IMAGE (OCR) ----
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

    file_path = os.path.join(UPLOAD_DIR, f"{file_id}.{extension}")

    # Save file locally
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    # Extract text (OCR supported)
    parsed_text = extract_text(file_path, extension)

    # Insert into Supabase
    supabase.table("documents").insert({
        "title": title,
        "document_type": document_type,
        "file_name": file.filename,
        "file_extension": extension,
        "mime_type": file.content_type,
        "file_path": file_path,
        "parsed_text": parsed_text,
    }).execute()

    return {"status": "success"}
    
# --------------------
# Delete Endpoint
# --------------------    
    
@app.delete("/api/delete/{doc_id}")
async def delete_document(doc_id: str):

    # 1️⃣ Get file path from database
    response = (
        supabase.table("documents")
        .select("file_path")
        .eq("id", doc_id)
        .execute()
    )

    if not response.data:
        return {"error": "Document not found"}

    file_path = response.data[0]["file_path"]

    # 🔎 DEBUG INFO
    print("----------- DELETE DEBUG -----------")
    print("Working directory:", os.getcwd())
    print("File path from DB:", file_path)
    print("Absolute path:", os.path.abspath(file_path))
    print("Exists before delete:", os.path.exists(file_path))
    print("------------------------------------")

    # 2️⃣ Delete physical file safely
    if file_path and os.path.exists(file_path):
        os.remove(file_path)
        print("File deleted successfully")
    else:
        print("File not found on disk:", file_path)

    # 3️⃣ Delete record from database
    (
        supabase.table("documents")
        .delete()
        .eq("id", doc_id)
        .execute()
    )

    return {"status": "deleted"}
