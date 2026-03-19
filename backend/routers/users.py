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
    department: str
    name: str
    mobile: Optional[str] = ""
    location: Optional[str] = ""


class RegisterRequesterBody(BaseModel):
    email: str
    password: str
    name: str
    department: str
    mobile: str
    location: str


@router.post("/admin/create-user")
async def admin_create_user(body: CreateUserBody):
    role = body.user_type.strip().lower()
    if role not in ("tech", "requester"):
        raise HTTPException(status_code=400, detail="user_type must be 'tech' or 'requester'")
    email = body.email.strip().lower()
    try:
        user = supabase.auth.admin.create_user({
            "email": email,
            "password": body.password,
            "email_confirm": True,
        })
        user_id = user.user.id if hasattr(user, 'user') and user.user else None
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    supabase.table("user_profiles").upsert({
        "email": email,
        "user_type": role,
    }).execute()
    
    if user_id:
        supabase.table("profiles").upsert({
            "id": user_id,
            "full_name": body.name,
            "role": role,
        }).execute()
        
        supabase.table("employees").upsert({
            "profile_id": user_id,
            "full_name": body.name,
            "department": body.department,
            "mobile": body.mobile,
            "location": body.location,
            "user_type": role,
            "active": True,
        }).execute()
    
    log_activity(email, "auth", "account_created",
        target_label=email, detail=role)
    return {"status": "created"}


@router.post("/register-requester")
async def register_requester(body: RegisterRequesterBody):
    email = body.email.strip().lower()
    
    try:
        user = supabase.auth.admin.create_user({
            "email": email,
            "password": body.password,
            "email_confirm": True,
        })
        user_id = user.user.id if hasattr(user, 'user') and user.user else None
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    if not user_id:
        raise HTTPException(status_code=500, detail="Failed to create auth user")
    
    supabase.table("profiles").upsert({
        "id": user_id,
        "full_name": body.name,
        "role": "requester",
    }).execute()
    
    supabase.table("employees").upsert({
        "profile_id": user_id,
        "email": email,
        "full_name": body.name,
        "department": body.department,
        "mobile": body.mobile,
        "location": body.location,
        "user_type": "requester",
        "active": True,
    }).execute()
    
    supabase.table("user_profiles").upsert({
        "email": email,
        "user_type": "requester",
    }).execute()
    
    log_activity(email, "auth", "requester_registered",
        target_label=email, detail=f"department: {body.department}")
    return {"status": "created", "email": email}


@router.get("/user-role")
async def get_user_role(email: str = Query(...)):
    normalized = email.strip().lower()
    
    result = supabase.table("user_profiles") \
        .select("user_type") \
        .eq("email", normalized) \
        .execute()
    if result.data:
        return {"user_type": result.data[0]["user_type"]}
    
    emp_result = supabase.table("employees") \
        .select("user_type") \
        .eq("profile_id", normalized) \
        .execute()
    if emp_result.data:
        return {"user_type": emp_result.data[0].get("user_type", "admin")}
    
    return {"user_type": "admin"}


@router.get("/employee-profile")
async def get_employee_profile(email: str = Query(...)):
    normalized = email.strip().lower()
    
    # First try by email column in employees
    result = supabase.table("employees") \
        .select("*") \
        .eq("email", normalized) \
        .execute()
    
    if result.data:
        return {"employee": result.data[0]}
    
    # Fallback: look up in user_profiles, then sync email to employees
    profile_result = supabase.table("user_profiles") \
        .select("*") \
        .eq("email", normalized) \
        .execute()
    
    if profile_result.data:
        # Try to find employee by any matching field and update email
        # First check if there's any employee that might match
        all_employees = supabase.table("employees").select("*").execute()
        if all_employees.data:
            for emp in all_employees.data:
                # Update first unlinked employee with this email
                if not emp.get("email"):
                    supabase.table("employees").update({"email": normalized}).eq("id", emp["id"]).execute()
                    updated = supabase.table("employees").select("*").eq("id", emp["id"]).execute()
                    if updated.data:
                        return {"employee": updated.data[0]}
    
    return {"employee": None}


@router.get("/departments")
async def get_departments():
    result = supabase.table("employees") \
        .select("department") \
        .execute()
    departments = list(set([r.get("department") for r in (result.data or []) if r.get("department")]))
    if not departments:
        departments = ["General"]
    return {"departments": sorted(departments)}


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


@router.post("/activity-log/sign-out")
async def log_sign_out(body: SignInBody):
    log_activity(body.user_email, "auth", "signed_out",
        target_label=body.user_email)
    return {"status": "logged"}


@router.post("/activity-log/update-check")
async def log_update_check(body: SignInBody):
    log_activity(body.user_email, "app", "update_checked",
        target_label="Check for updates")
    return {"status": "logged"}


@router.get("/employees")
async def list_employees(tech: bool = False):
    """Get all employees, optionally filtered by user_type"""
    if tech:
        result = supabase.table("employees") \
            .select("*, user_profiles(user_type)") \
            .execute()
        # Filter in Python since PostgREST doesn't support this join well
        employees = [r for r in (result.data or []) 
                     if r.get("user_profiles", {}).get("user_type") == "tech"]
        return {"employees": employees}
    else:
        result = supabase.table("employees") \
            .select("*") \
            .execute()
        return {"employees": result.data or []}
