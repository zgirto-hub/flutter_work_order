from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import supabase
from utils.activity import log_activity

router = APIRouter()


class CreateUserBody(BaseModel):
    email: str
    password: str
    user_type: str  # 'technician' | 'reporter' | 'admin'
    full_name: str
    mobile: Optional[str] = ""
    location: Optional[str] = ""
    department_id: Optional[str] = None


class UpdateUserBody(BaseModel):
    full_name: Optional[str] = None
    department_id: Optional[str] = None
    mobile: Optional[str] = None
    location: Optional[str] = None


class ChangeRoleBody(BaseModel):
    user_type: str  # 'technician' | 'reporter'
    department_id: Optional[str] = None


def _get_user_by_email(email: str):
    """Get user by email from users table"""
    normalized = email.strip().lower()
    result = supabase.table("users").select("*").eq("email", normalized).execute()
    return result.data[0] if result.data else None


def _get_user_by_id(user_id: str):
    """Get user by ID from users table"""
    result = supabase.table("users").select("*").eq("id", user_id).execute()
    return result.data[0] if result.data else None


def _require_admin(email: str):
    """Verify the caller is an admin, raise 403 otherwise"""
    user = _get_user_by_email(email)
    if not user or user.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")


# ================================================
# PUBLIC ENDPOINTS
# ================================================

@router.get("/user-role")
async def get_user_role(email: str = Query(...)):
    """Get user role by email"""
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {"user_type": user.get("user_type", "reporter")}


@router.get("/users/me")
async def get_current_user(email: str = Query(...)):
    """Get current user profile"""
    user = _get_user_by_email(email)
    if user:
        td_rows = supabase.table("technician_departments") \
            .select("department_id, departments(id, name)") \
            .eq("technician_id", user.get("id")) \
            .execute().data or []
        user["technician_departments"] = [
            {"id": row["departments"]["id"], "name": row["departments"]["name"]}
            for row in td_rows if row.get("departments")
        ]
    return {"user": user}


# ================================================
# ADMIN ENDPOINTS
# ================================================

@router.get("/users")
async def list_users(department_id: Optional[str] = Query(None)):
    """Get all users, optionally filtered by department"""
    if department_id:
        td_rows = supabase.table("technician_departments") \
            .select("technician_id, departments(name), users!technician_id(*)") \
            .eq("department_id", department_id) \
            .execute().data or []
        users = []
        for row in td_rows:
            user = row.get("users")
            if user:
                user["departments"] = [row["departments"]["name"]] if row.get("departments") else []
                users.append(user)
    else:
        result = supabase.table("users") \
            .select("*, technician_departments(department_id, departments(name))") \
            .execute()
        users = result.data or []
        for user in users:
            td_rows = user.pop("technician_departments", []) or []
            user["departments"] = [
                row["departments"]["name"]
                for row in td_rows
                if row.get("departments") and row["departments"].get("name")
            ]

    return {"users": users}


@router.get("/users/{user_id}")
async def get_user(user_id: str):
    """Get user by ID"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    dept_result = supabase.table("technician_departments") \
        .select("department_id") \
        .eq("technician_id", user.get("id")) \
        .execute()
    dept_ids = [r.get("department_id") for r in (dept_result.data or []) if r.get("department_id")]

    dept_names = []
    for dept_id in dept_ids:
        d_result = supabase.table("departments").select("name").eq("id", dept_id).execute()
        if d_result.data:
            dept_names.append(d_result.data[0].get("name"))
    user["departments"] = dept_names

    return {"user": user}


@router.post("/users")
async def create_user(body: CreateUserBody, admin_email: str = Query(...)):
    """Create new user (admin only)"""
    _require_admin(admin_email)

    user_type = body.user_type.strip().lower()
    if user_type not in ("technician", "reporter", "admin"):
        raise HTTPException(status_code=400, detail="user_type must be 'technician', 'reporter', or 'admin'")

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
    user_data = {
        "auth_id": auth_id,
        "email": email,
        "full_name": body.full_name,
        "mobile": body.mobile or "",
        "location": body.location or "",
        "user_type": user_type,
        "is_active": True,
    }
    if body.department_id:
        user_data["department_id"] = body.department_id

    result = supabase.table("users").insert(user_data).execute()

    log_activity(email, "auth", "user_created",
        target_label=email, detail=f"type: {user_type}")

    return {"status": "created", "user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}")
async def update_user(user_id: str, body: UpdateUserBody, admin_email: str = Query(...)):
    """Update user details (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    update_data = {}
    if body.full_name is not None:
        update_data["full_name"] = body.full_name
    if body.department_id is not None:
        update_data["department_id"] = body.department_id
    if body.mobile is not None:
        update_data["mobile"] = body.mobile
    if body.location is not None:
        update_data["location"] = body.location

    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    result = supabase.table("users").update(update_data).eq("id", user_id).execute()

    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/role")
async def change_user_role(user_id: str, body: ChangeRoleBody, admin_email: str = Query(...)):
    """Change user role (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user_type = body.user_type.strip().lower()
    if user_type not in ("technician", "reporter", "admin"):
        raise HTTPException(status_code=400, detail="user_type must be 'technician', 'reporter', or 'admin'")

    update_data = {"user_type": user_type}
    if body.department_id is not None:
        update_data["department_id"] = body.department_id

    result = supabase.table("users").update(update_data).eq("id", user_id).execute()

    log_activity(user["email"], "admin", "role_changed",
        target_label=user["email"], detail=f"from {user['user_type']} to {user_type}")

    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/deactivate")
async def deactivate_user(user_id: str, admin_email: str = Query(...)):
    """Deactivate user (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    result = supabase.table("users").update({"is_active": False}).eq("id", user_id).execute()

    log_activity(user["email"], "admin", "user_deactivated",
        target_label=user["email"])

    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/activate")
async def activate_user(user_id: str, admin_email: str = Query(...)):
    """Reactivate user (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    result = supabase.table("users").update({"is_active": True}).eq("id", user_id).execute()

    log_activity(user["email"], "admin", "user_activated",
        target_label=user["email"])

    return {"user": result.data[0] if result.data else None}


# ================================================
# ACTIVITY LOG
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
