print("=== THIS MAIN.PY IS RUNNING v1.5 ===")

from fastapi import FastAPI, UploadFile, File, Form, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from supabase import create_client, Client
import os
import json
import uuid
import unicodedata
import base64
import secrets
from datetime import datetime, timedelta
from PyPDF2 import PdfReader
from docx import Document
import pytesseract
from pdf2image import convert_from_path

# WebAuthn
import webauthn
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    UserVerificationRequirement,
    ResidentKeyRequirement,
)
from webauthn.helpers.cose import COSEAlgorithmIdentifier
from pydantic import BaseModel
from typing import Optional

# --------------------
# Supabase Config
# --------------------
SUPABASE_URL = "https://rydrqsjofoulwdtwfbgv.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ5ZHJxc2pvZm91bHdkdHdmYmd2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjE0MTg5MiwiZXhwIjoyMDg3NzE3ODkyfQ.HvebR7mHIz2Dp4HRiLf6nVrzbqgeIX5XLc3NuVexwII"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# --------------------
# WebAuthn Config
# --------------------
RP_ID = "zorin.taila92fe8.ts.net"
RP_NAME = "Work Order App"
ORIGIN = "https://zorin.taila92fe8.ts.net"

# In-memory challenge store (keyed by email)
# In production you'd use Redis, but this works fine for single-server setup
_pending_challenges: dict[str, str] = {}

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

class RegisterBeginRequest(BaseModel):
    email: str

class RegisterCompleteRequest(BaseModel):
    email: str
    credential: dict
    device_name: Optional[str] = None

class AuthBeginRequest(BaseModel):
    email: str

class AuthCompleteRequest(BaseModel):
    email: str
    credential: dict

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
# WEBAUTHN ENDPOINTS
# ====================

# --------------------
# Register: Begin
# Returns options for the browser to create a credential
# --------------------

@app.post("/api/webauthn/register-begin")
async def webauthn_register_begin(req: RegisterBeginRequest):
    email = req.email.strip().lower()

    # Check user exists in Supabase auth
    # (they must be logged in via password first before registering Face ID)

    # Generate a challenge
    challenge = secrets.token_bytes(32)
    _pending_challenges[f"reg:{email}"] = base64.b64encode(challenge).decode()

    # Build registration options
    options = webauthn.generate_registration_options(
        rp_id=RP_ID,
        rp_name=RP_NAME,
        user_id=email.encode(),
        user_name=email,
        user_display_name=email.split("@")[0],
        challenge=challenge,
        authenticator_selection=AuthenticatorSelectionCriteria(
            user_verification=UserVerificationRequirement.REQUIRED,
            resident_key=ResidentKeyRequirement.PREFERRED,
        ),
        supported_pub_key_algs=[
            COSEAlgorithmIdentifier.ECDSA_SHA_256,
            COSEAlgorithmIdentifier.RSASSA_PKCS1_v1_5_SHA_256,
        ],
        timeout=60000,
    )

    return json.loads(webauthn.options_to_json(options))


# --------------------
# Register: Complete
# Verifies the browser response and saves the credential
# --------------------

@app.post("/api/webauthn/register-complete")
async def webauthn_register_complete(req: RegisterCompleteRequest):
    email = req.email.strip().lower()

    stored = _pending_challenges.pop(f"reg:{email}", None)
    if not stored:
        raise HTTPException(status_code=400, detail="No pending registration for this email")

    expected_challenge = base64.b64decode(stored)

    try:
        verification = webauthn.verify_registration_response(
            credential=req.credential,
            expected_challenge=expected_challenge,
            expected_rp_id=RP_ID,
            expected_origin=ORIGIN,
            require_user_verification=True,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Verification failed: {str(e)}")

    # Store credential in Supabase
    credential_id = base64.b64encode(verification.credential_id).decode()
    public_key = base64.b64encode(verification.credential_public_key).decode()

    # Remove any existing credential for this device (re-registration)
    supabase.table("webauthn_credentials") \
        .delete() \
        .eq("user_email", email) \
        .eq("credential_id", credential_id) \
        .execute()

    supabase.table("webauthn_credentials").insert({
        "user_email": email,
        "credential_id": credential_id,
        "public_key": public_key,
        "sign_count": verification.sign_count,
        "device_name": req.device_name or "Unknown device",
    }).execute()

    return {"status": "registered"}


# --------------------
# Authenticate: Begin
# Returns a challenge for the browser to sign with Face ID
# --------------------

@app.post("/api/webauthn/auth-begin")
async def webauthn_auth_begin(req: AuthBeginRequest):
    email = req.email.strip().lower()

    # Look up credentials for this user
    result = supabase.table("webauthn_credentials") \
        .select("credential_id") \
        .eq("user_email", email) \
        .execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="No Face ID registered for this account")

    challenge = secrets.token_bytes(32)
    _pending_challenges[f"auth:{email}"] = base64.b64encode(challenge).decode()

    allow_credentials = [
        {"type": "public-key", "id": row["credential_id"]}
        for row in result.data
    ]

    options = webauthn.generate_authentication_options(
        rp_id=RP_ID,
        challenge=challenge,
        allow_credentials=allow_credentials,
        user_verification=UserVerificationRequirement.REQUIRED,
        timeout=60000,
    )

    return json.loads(webauthn.options_to_json(options))


# --------------------
# Authenticate: Complete
# Verifies Face ID response → returns a Supabase magic link token
# --------------------

@app.post("/api/webauthn/auth-complete")
async def webauthn_auth_complete(req: AuthCompleteRequest):
    email = req.email.strip().lower()

    stored = _pending_challenges.pop(f"auth:{email}", None)
    if not stored:
        raise HTTPException(status_code=400, detail="No pending authentication for this email")

    expected_challenge = base64.b64decode(stored)

    # Get stored credential
    cred_id = req.credential.get("id", "")

    result = supabase.table("webauthn_credentials") \
        .select("*") \
        .eq("user_email", email) \
        .eq("credential_id", cred_id) \
        .execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Credential not found")

    stored_cred = result.data[0]
    public_key = base64.b64decode(stored_cred["public_key"])
    sign_count = stored_cred["sign_count"]

    try:
        verification = webauthn.verify_authentication_response(
            credential=req.credential,
            expected_challenge=expected_challenge,
            expected_rp_id=RP_ID,
            expected_origin=ORIGIN,
            credential_public_key=public_key,
            credential_current_sign_count=sign_count,
            require_user_verification=True,
        )
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Face ID verification failed: {str(e)}")

    # Update sign count (replay attack prevention)
    supabase.table("webauthn_credentials") \
        .update({"sign_count": verification.new_sign_count}) \
        .eq("id", stored_cred["id"]) \
        .execute()

    # Generate a Supabase magic link for this user so Flutter can sign them in
    try:
        link_response = supabase.auth.admin.generate_link({
            "type": "magiclink",
            "email": email,
        })
        token = link_response.properties.hashed_token
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not generate login token: {str(e)}")

    return {
        "status": "authenticated",
        "email": email,
        "token": token,
    }


# --------------------
# Check if Face ID is registered
# --------------------

@app.get("/api/webauthn/status")
async def webauthn_status(email: str = Query(...)):
    result = supabase.table("webauthn_credentials") \
        .select("id, device_name, created_at") \
        .eq("user_email", email.strip().lower()) \
        .execute()

    return {
        "registered": len(result.data) > 0,
        "devices": result.data or [],
    }


# --------------------
# Remove a registered credential
# --------------------

@app.delete("/api/webauthn/remove")
async def webauthn_remove(
    email: str = Query(...),
    credential_id: str = Query(...),
):
    supabase.table("webauthn_credentials") \
        .delete() \
        .eq("user_email", email.strip().lower()) \
        .eq("credential_id", credential_id) \
        .execute()

    return {"status": "removed"}
