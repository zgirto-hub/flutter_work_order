print("=== THIS MAIN.PY IS RUNNING v1.9.2 ===")

from fastapi import FastAPI, UploadFile, File, Form, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from supabase import create_client, Client
import os
import json
import uuid
import unicodedata
import urllib.request
import urllib.error
from datetime import datetime, timedelta
from PyPDF2 import PdfReader
from docx import Document
import pytesseract
from pdf2image import convert_from_path

from pydantic import BaseModel
from typing import Optional

# --------------------
# Supabase Config
# --------------------
SUPABASE_URL = "https://rydrqsjofoulwdtwfbgv.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5ZHJxc2pvZm91bHdkdHdmYmd2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjE0MTg5MiwiZXhwIjoyMDg3NzE3ODkyfQ.HvebR7mHIz2Dp4HRiLf6nVrzbqgeIX5XLc3NuVexwII"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# --------------------
# OneSignal Config
# --------------------
ONESIGNAL_APP_ID = "760f00e5-fb08-4c0c-b898-ea35737bcc21"
ONESIGNAL_API_KEY = "os_v2_app_oyhqbzp3bbgazoey5i2xg66mehohdfs5u7seo7egubju2zkivni62u4bf6ghkbbbbmnzku63rzt4esjkoauqce6g7cuunqbnrvso7gq"

def _send_push_notification(title: str, body: str):
    try:
        data = json.dumps({
            "app_id": ONESIGNAL_APP_ID,
            "included_segments": ["All"],
            "headings": {"en": title},
            "contents": {"en": body},
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://api.onesignal.com/notifications",
            data=data,
            headers={
                "Authorization": f"Key {ONESIGNAL_API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        response = urllib.request.urlopen(req, timeout=5)
        print(f"OneSignal response: {response.status} {response.read().decode()}")
    except urllib.error.HTTPError as e:
        print(f"OneSignal HTTP {e.code}: {e.read().decode()}")
    except Exception as e:
        print(f"OneSignal error: {e}")

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
# Pydantic Models
# --------------------

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

    if extension == "pdf":
        try:
            reader = PdfReader(file_path)
            for page in reader.pages:
                extracted = page.extract_text()
                if extracted:
                    text += extracted
            if not text.strip():
                images = convert_from_path(file_path)
                for img in images:
                    text += pytesseract.image_to_string(img, lang="ara+eng")
        except Exception:
            images = convert_from_path(file_path)
            for img in images:
                text += pytesseract.image_to_string(img, lang="ara+eng")

    elif extension == "docx":
        doc = Document(file_path)
        for para in doc.paragraphs:
            text += para.text + "\n"

    elif extension == "txt":
        with open(file_path, "r", encoding="utf-8") as f:
            text = f.read()

    elif extension in ["jpg", "jpeg", "png"]:
        try:
            text = pytesseract.image_to_string(file_path, lang="ara+eng")
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

    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    public_url = f"/files/{filename}"
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

    return {"status": "success", "file_url": public_url}

# --------------------
# Delete Endpoint
# --------------------

@app.delete("/api/delete/{doc_id}")
async def delete_document(doc_id: str, user_email: str = Query(...)):
    print("DELETE DEBUG -> user_email:", user_email)

    response = supabase.table("documents") \
        .select("file_path, uploaded_by") \
        .eq("id", doc_id) \
        .execute()

    if not response.data:
        return {"error": "Document not found"}

    doc = response.data[0]
    owner = doc["uploaded_by"]

    if owner != user_email:
        raise HTTPException(status_code=403, detail="You are not allowed to delete this document")

    file_path = doc["file_path"]
    if file_path:
        filename = os.path.basename(file_path)
        absolute_path = os.path.join(UPLOAD_DIR, filename)
        if os.path.exists(absolute_path):
            os.remove(absolute_path)

    supabase.table("documents").delete().eq("id", doc_id).execute()
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
    response = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", document_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="Document not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only the owner can share this document")

    if owner_email == share_with:
        raise HTTPException(status_code=400, detail="You already own this document")

    existing = supabase.table("document_permissions") \
        .select("id") \
        .eq("document_id", document_id) \
        .eq("user_email", share_with) \
        .execute()

    if existing.data:
        raise HTTPException(status_code=400, detail="Document already shared with this user")

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
    return {"users": users}

# --------------------
# Revoke Share
# --------------------

@app.delete("/api/remove-share")
async def remove_share(
    document_id: str = Query(...),
    owner_email: str = Query(...),
    remove_user: str = Query(...)
):
    response = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", document_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="Document not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only owner can remove access")

    supabase.table("document_permissions") \
        .delete() \
        .eq("document_id", document_id) \
        .eq("user_email", remove_user) \
        .execute()

    return {"status": "access removed"}

# --------------------
# List Users
# --------------------

@app.get("/api/users")
async def list_users():
    response = supabase.table("documents").select("uploaded_by").execute()

    if not response.data:
        return {"users": []}

    users = list({row["uploaded_by"] for row in response.data if row["uploaded_by"]})
    users.sort()
    return {"users": users}

# ====================
# REQUEST ENDPOINTS
# ====================

class CreateUserBody(BaseModel):
    email: str
    password: str
    user_type: str  # 'tech' | 'requester'

@app.post("/api/admin/create-user")
async def admin_create_user(body: CreateUserBody):
    role = body.user_type.strip().lower()
    if role not in ("tech", "requester"):
        raise HTTPException(status_code=400, detail="user_type must be 'tech' or 'requester'")
    email = body.email.strip().lower()
    try:
        supabase.auth.admin.create_user({
            "email": email,
            "password": body.password,
            "email_confirm": True,
        })
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    # Upsert role in user_profiles
    supabase.table("user_profiles").upsert({
        "email": email,
        "user_type": role,
    }).execute()
    return {"status": "created"}

class CreateRequestBody(BaseModel):
    title: str
    description: Optional[str] = None
    created_by: str
    requester_name: str
    location: Optional[str] = None

class CloseRequestBody(BaseModel):
    closed_by: str
    tech_notes: Optional[str] = None

@app.get("/api/user-role")
async def get_user_role(email: str = Query(...)):
    result = supabase.table("user_profiles") \
        .select("user_type") \
        .eq("email", email.strip().lower()) \
        .execute()
    if not result.data:
        return {"user_type": "admin"}
    return {"user_type": result.data[0]["user_type"]}

@app.get("/api/requests/count-open")
async def count_open_requests():
    result = supabase.table("requests").select("id").eq("status", "Open").execute()
    return {"count": len(result.data or [])}

@app.get("/api/requests")
async def get_requests(email: str = Query(...), user_role: str = Query(...)):
    query = supabase.table("requests").select("*")
    if user_role == "requester":
        query = query.eq("created_by", email)
    result = query.order("created_at", desc=True).execute()
    return {"requests": result.data or []}

@app.post("/api/requests")
async def create_request(body: CreateRequestBody):
    supabase.table("requests").insert({
        "title": body.title,
        "description": body.description,
        "created_by": body.created_by,
        "requester_name": body.requester_name,
        "location": body.location,
        "status": "Open",
    }).execute()
    _send_push_notification(
        title="New Request",
        body=f"{body.requester_name}: {body.title}",
    )
    return {"status": "created"}

@app.delete("/api/requests/{request_id}")
async def delete_request(request_id: str, email: str = Query(...)):
    result = supabase.table("requests") \
        .select("created_by") \
        .eq("id", request_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Request not found")
    row = result.data[0]
    if row["created_by"] != email:
        raise HTTPException(status_code=403, detail="Not allowed to delete this request")
    supabase.table("requests").delete().eq("id", request_id).execute()
    return {"status": "deleted"}

@app.patch("/api/requests/{request_id}/close")
async def close_request(request_id: str, body: CloseRequestBody):
    result = supabase.table("requests") \
        .select("status") \
        .eq("id", request_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Request not found")
    if result.data[0]["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Request already closed")
    supabase.table("requests").update({
        "status": "Closed",
        "closed_by": body.closed_by,
        "closed_at": datetime.utcnow().isoformat(),
        "tech_notes": body.tech_notes,
    }).eq("id", request_id).execute()
    return {"status": "closed"}

