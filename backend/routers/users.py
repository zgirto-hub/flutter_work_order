from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import supabase
from utils.activity import log_activity

router = APIRouter()


class CreateUserBody(BaseModel):
    email: str
    password: str
    user_type: str  # 'fixer' | 'reporter' | 'admin'
    full_name: str
    mobile: Optional[str] = ""
    location: Optional[str] = ""


class RegisterBody(BaseModel):
    email: str
    password: str
    full_name: str
    department: str
    mobile: str
    location: str


class UpdateUserBody(BaseModel):
    full_name: Optional[str] = None
    department: Optional[str] = None
    mobile: Optional[str] = None
    location: Optional[str] = None


class ChangeRoleBody(BaseModel):
    user_type: str  # 'fixer' | 'reporter'
    department: Optional[str] = None


def _get_user_by_email(email: str):
    """Get user by email from users table"""
    normalized = email.strip().lower()
    result = supabase.table("users").select("*").eq("email", normalized).execute()
    return result.data[0] if result.data else None


def _get_user_by_id(user_id: str):
    """Get user by ID from users table"""
    result = supabase.table("users").select("*").eq("id", user_id).execute()
    return result.data[0] if result.data else None


# ================================================
# PUBLIC ENDPOINTS
# ================================================

@router.post("/register")
async def register(body: RegisterBody):
    """Self-register as reporter"""
    email = body.email.strip().lower()
    
    # Check if email already exists
    existing = _get_user_by_email(email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Create auth user
    try:
        auth_user = supabase.auth.admin.create_user({
            "email": email,
            "password": body.password,
            "email_confirm": True,
        })
        auth_id = auth_user.user.id if auth_user.user else None
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    if not auth_id:
        raise HTTPException(status_code=500, detail="Failed to create auth user")
    
    # Create user record
    result = supabase.table("users").insert({
        "auth_id": auth_id,
        "email": email,
        "full_name": body.full_name,
        "department": body.department,
        "mobile": body.mobile,
        "location": body.location,
        "user_type": "reporter",
        "is_active": True,
    }).execute()
    
    log_activity(email, "auth", "reporter_registered",
        target_label=email, detail=f"department: {body.department}")
    
    return {"status": "created", "email": email}


@router.get("/user-role")
async def get_user_role(email: str = Query(...)):
    """Get user role by email"""
    user = _get_user_by_email(email)
    if user:
        return {"user_type": user.get("user_type", "admin")}
    
    # Check auth.users directly if not in users table
    return {"user_type": "admin"}


@router.get("/users/me")
async def get_current_user(email: str = Query(...)):
    """Get current user profile"""
    user = _get_user_by_email(email)
    if user:
        return {"user": user}
    return {"user": None}


# ================================================
# ADMIN ENDPOINTS
# ================================================

@router.get("/users")
async def list_users():
    """Get all users"""
    result = supabase.table("users").select("*").execute()
    users = result.data or []
    
    for user in users:
        dept_result = supabase.table("fixer_departments") \
            .select("department") \
            .eq("fixer_id", user.get("id")) \
            .execute()
        user["departments"] = [r.get("department") for r in (dept_result.data or []) if r.get("department")]
    
    return {"users": users}


@router.get("/users/{user_id}")
async def get_user(user_id: str):
    """Get user by ID"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    dept_result = supabase.table("fixer_departments") \
        .select("department") \
        .eq("fixer_id", user.get("id")) \
        .execute()
    user["departments"] = [r.get("department") for r in (dept_result.data or []) if r.get("department")]
    
    return {"user": user}


@router.post("/users")
async def create_user(body: CreateUserBody):
    """Create new user (admin only)"""
    user_type = body.user_type.strip().lower()
    if user_type not in ("fixer", "reporter", "admin"):
        raise HTTPException(status_code=400, detail="user_type must be 'fixer', 'reporter', or 'admin'")
    
    email = body.email.strip().lower()
    
    # Check if email already exists in our users table
    existing = _get_user_by_email(email)
    if existing:
        raise HTTPException(status_code=400, detail="User already exists in database")
    
    # Create auth user
    auth_id = None
    try:
        auth_user = supabase.auth.admin.create_user({
            "email": email,
            "password": body.password,
            "email_confirm": True,
        })
        auth_id = auth_user.user.id if auth_user.user else None
    except Exception as e:
        error_msg = str(e).lower()
        if "already been registered" in error_msg or "already exists" in error_msg:
            raise HTTPException(status_code=400, detail="User already exists in authentication system")
        raise HTTPException(status_code=400, detail=f"Auth error: {str(e)}")
    
    if not auth_id:
        raise HTTPException(status_code=500, detail="Failed to create auth user")
    
    # Create user record
    result = supabase.table("users").insert({
        "auth_id": auth_id,
        "email": email,
        "full_name": body.full_name,
        "mobile": body.mobile or "",
        "location": body.location or "",
        "user_type": user_type,
        "is_active": True,
    }).execute()
    
    log_activity(email, "auth", "user_created",
        target_label=email, detail=f"type: {user_type}")
    
    return {"status": "created", "user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}")
async def update_user(user_id: str, body: UpdateUserBody):
    """Update user details"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    update_data = {}
    if body.full_name is not None:
        update_data["full_name"] = body.full_name
    if body.department is not None:
        update_data["department"] = body.department
    if body.mobile is not None:
        update_data["mobile"] = body.mobile
    if body.location is not None:
        update_data["location"] = body.location
    
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("users").update(update_data).eq("id", user_id).execute()
    
    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/role")
async def change_user_role(user_id: str, body: ChangeRoleBody):
    """Change user role (admin only)"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    user_type = body.user_type.strip().lower()
    if user_type not in ("fixer", "reporter", "admin"):
        raise HTTPException(status_code=400, detail="user_type must be 'fixer', 'reporter', or 'admin'")
    
    update_data = {"user_type": user_type}
    if body.department is not None:
        update_data["department"] = body.department
    
    result = supabase.table("users").update(update_data).eq("id", user_id).execute()
    
    log_activity(user["email"], "admin", "role_changed",
        target_label=user["email"], detail=f"from {user['user_type']} to {user_type}")
    
    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/deactivate")
async def deactivate_user(user_id: str):
    """Deactivate user"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    result = supabase.table("users").update({"is_active": False}).eq("id", user_id).execute()
    
    log_activity(user["email"], "admin", "user_deactivated",
        target_label=user["email"])
    
    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/activate")
async def activate_user(user_id: str):
    """Reactivate user"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    result = supabase.table("users").update({"is_active": True}).eq("id", user_id).execute()
    
    log_activity(user["email"], "admin", "user_activated",
        target_label=user["email"])
    
    return {"user": result.data[0] if result.data else None}


# ================================================
# ACTIVITY LOG (keep existing)
# ================================================

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
