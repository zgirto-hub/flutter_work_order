from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel

from db import supabase

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
