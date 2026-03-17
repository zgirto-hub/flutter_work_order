from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional

from db import supabase
from utils.activity import log_activity

router = APIRouter()


class CreateUserBody(BaseModel):
    email: str
    password: str
    user_type: str  # 'tech' | 'requester'


@router.post("/admin/create-user")
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
    supabase.table("user_profiles").upsert({
        "email": email,
        "user_type": role,
    }).execute()
    log_activity(email, "auth", "account_created",
        target_label=email, detail=role)
    return {"status": "created"}


@router.get("/user-role")
async def get_user_role(email: str = Query(...)):
    result = supabase.table("user_profiles") \
        .select("user_type") \
        .eq("email", email.strip().lower()) \
        .execute()
    if not result.data:
        return {"user_type": "admin"}
    return {"user_type": result.data[0]["user_type"]}


@router.get("/activity-log")
async def get_activity_log(
    category: Optional[str] = Query(None),
    limit: int = Query(100),
    offset: int = Query(0),
):
    query = supabase.table("user_activity_log") \
        .select("*") \
        .order("created_at", desc=True) \
        .limit(limit) \
        .offset(offset)

    if category and category != "all":
        query = query.eq("category", category)

    result = query.execute()
    return {"logs": result.data or [], "total": len(result.data or [])}


class SignInBody(BaseModel):
    user_email: str


@router.post("/activity-log/sign-in")
async def log_sign_in(body: SignInBody):
    log_activity(body.user_email, "auth", "signed_in",
        target_label=body.user_email)
    return {"status": "logged"}
