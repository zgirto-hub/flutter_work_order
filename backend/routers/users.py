import os
from fastapi import APIRouter, Query, HTTPException, Request
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


class ResetPasswordBody(BaseModel):
    new_password: str


class RequestResetBody(BaseModel):
    email: str


class CompleteResetBody(BaseModel):
    access_token: Optional[str] = None
    token_hash: Optional[str] = None
    type: Optional[str] = None
    new_password: str


class UpdateScreenPermissionsBody(BaseModel):
    allowed_screens: Optional[list] = None


class UpdateApprovalRoleBody(BaseModel):
    approval_level: Optional[int] = None
    department_ids: Optional[list] = []


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

    user_id = user.get("id")
    td_result = (
        supabase.table("technician_departments")
        .select("department_id")
        .eq("technician_id", user_id)
        .execute()
    )
    department_ids = [row.get("department_id") for row in (td_result.data or [])]

    return {
        "user_type": user.get("user_type", "reporter"),
        "allowed_screens": user.get("allowed_screens"),
        "approval_level": user.get("approval_level"),
        "is_supervisor": user.get("is_supervisor", False),
        "is_superintendent": user.get("is_superintendent", False),
        "department_ids": department_ids,
    }


@router.get("/users/me")
async def get_current_user(email: str = Query(...)):
    """Get current user profile"""
    user = _get_user_by_email(email)
    if user:
        # Get department name from user's department_id
        dept_id = user.get("department_id")
        if dept_id:
            d_result = (
                supabase.table("departments")
                .select("id, name")
                .eq("id", dept_id)
                .execute()
            )
            user["technician_departments"] = [
                {"id": d["id"], "name": d["name"]} for d in (d_result.data or [])
            ]
        else:
            user["technician_departments"] = []
    return {"user": user}


# ================================================
# ADMIN ENDPOINTS
# ================================================


@router.get("/users")
async def list_users(
    department_id: Optional[str] = Query(None),
    is_supervisor: Optional[bool] = Query(None),
    is_superintendent: Optional[bool] = Query(None),
):
    """Get all users, optionally filtered by department or approval role"""
    query = supabase.table("users").select("*, dept:departments(name)")

    if department_id:
        query = query.eq("department_id", department_id)
    if is_supervisor is not None:
        query = query.eq("is_supervisor", is_supervisor)
    if is_superintendent is not None:
        query = query.eq("is_superintendent", is_superintendent)

    result = query.execute()
    users = result.data or []
    for user in users:
        direct_dept = user.pop("dept", None)
        if direct_dept and direct_dept.get("name"):
            user["departments"] = [direct_dept["name"]]
        else:
            user["departments"] = []

    return {"users": users}


@router.get("/users/{user_id}")
async def get_user(user_id: str):
    """Get user by ID"""
    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    dept_names = []
    if user.get("department_id"):
        d_result = (
            supabase.table("departments")
            .select("name")
            .eq("id", user["department_id"])
            .execute()
        )
        if d_result.data:
            dept_names = [d_result.data[0]["name"]]
    user["departments"] = dept_names

    return {"user": user}


@router.patch("/users/{user_id}/approval-role")
async def update_approval_role(
    user_id: str,
    body: UpdateApprovalRoleBody,
    admin_email: str = Query(...),
):
    """Admin sets approval role for a user (supervisor/superintendent)"""
    _require_admin(admin_email)

    admin_user = _get_user_by_email(admin_email)
    if admin_user and admin_user.get("id") == user_id:
        raise HTTPException(
            status_code=403, detail="Admin cannot set their own approval role"
        )

    target_user = _get_user_by_id(user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    approval_level = body.approval_level
    department_ids = body.department_ids or []

    update_data = {}

    if approval_level is None:
        update_data = {
            "is_supervisor": False,
            "is_superintendent": False,
            "approval_level": None,
        }
        supabase.table("technician_departments").delete().eq(
            "technician_id", user_id
        ).execute()
    elif approval_level == 1:
        update_data = {
            "is_supervisor": True,
            "is_superintendent": False,
            "approval_level": 1,
        }
        supabase.table("technician_departments").delete().eq(
            "technician_id", user_id
        ).execute()
        for dept_id in department_ids:
            supabase.table("technician_departments").insert(
                {
                    "technician_id": user_id,
                    "department_id": dept_id,
                }
            ).execute()
    elif approval_level == 2:
        update_data = {
            "is_supervisor": False,
            "is_superintendent": True,
            "approval_level": 2,
        }
        supabase.table("technician_departments").delete().eq(
            "technician_id", user_id
        ).execute()
    else:
        raise HTTPException(
            status_code=400,
            detail="Invalid approval_level. Use null, 1 (supervisor), or 2 (superintendent)",
        )

    supabase.table("users").update(update_data).eq("id", user_id).execute()

    try:
        log_activity(
            admin_email,
            "work_order",
            "approval_role_updated",
            target_label=target_user.get("full_name", ""),
            target_id=user_id,
            detail=f"Set approval_level={approval_level}",
        )
    except Exception:
        pass

    return {
        "user_id": user_id,
        "approval_level": approval_level,
        "is_supervisor": update_data.get("is_supervisor", False),
        "is_superintendent": update_data.get("is_superintendent", False),
        "department_ids": department_ids if approval_level == 1 else [],
    }


@router.get("/technician-departments/user/{user_id}")
async def get_technician_departments(user_id: str):
    """Return department IDs assigned to a supervisor/technician."""
    result = (
        supabase.table("technician_departments")
        .select("department_id")
        .eq("technician_id", user_id)
        .execute()
    )
    dept_ids = [row["department_id"] for row in (result.data or [])]
    return {"departments": dept_ids}


@router.post("/users")
async def create_user(body: CreateUserBody, admin_email: str = Query(...)):
    """Create new user (admin only)"""
    _require_admin(admin_email)

    user_type = body.user_type.strip().lower()
    if user_type not in ("technician", "reporter", "admin"):
        raise HTTPException(
            status_code=400,
            detail="user_type must be 'technician', 'reporter', or 'admin'",
        )

    email = body.email.strip().lower()

    # Check if email already exists in our users table
    existing = _get_user_by_email(email)
    if existing:
        raise HTTPException(status_code=400, detail="User already exists in database")

    # Create auth user
    auth_id = None
    try:
        auth_user = supabase.auth.admin.create_user(
            {
                "email": email,
                "password": body.password,
                "email_confirm": True,
            }
        )
        auth_id = auth_user.user.id if auth_user.user else None
    except Exception as e:
        error_msg = str(e).lower()
        if "already been registered" in error_msg or "already exists" in error_msg:
            raise HTTPException(
                status_code=400, detail="User already exists in authentication system"
            )
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

    log_activity(
        email, "auth", "user_created", target_label=email, detail=f"type: {user_type}"
    )

    return {"status": "created", "user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}")
async def update_user(
    user_id: str, body: UpdateUserBody, admin_email: str = Query(...)
):
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
async def change_user_role(
    user_id: str, body: ChangeRoleBody, admin_email: str = Query(...)
):
    """Change user role (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user_type = body.user_type.strip().lower()
    if user_type not in ("technician", "reporter", "admin"):
        raise HTTPException(
            status_code=400,
            detail="user_type must be 'technician', 'reporter', or 'admin'",
        )

    update_data = {"user_type": user_type}
    if body.department_id is not None:
        update_data["department_id"] = body.department_id

    result = supabase.table("users").update(update_data).eq("id", user_id).execute()

    log_activity(
        user["email"],
        "admin",
        "role_changed",
        target_label=user["email"],
        detail=f"from {user['user_type']} to {user_type}",
    )

    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/deactivate")
async def deactivate_user(user_id: str, admin_email: str = Query(...)):
    """Deactivate user (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    result = (
        supabase.table("users").update({"is_active": False}).eq("id", user_id).execute()
    )

    log_activity(user["email"], "admin", "user_deactivated", target_label=user["email"])

    return {"user": result.data[0] if result.data else None}


@router.patch("/users/{user_id}/reset-password")
async def reset_user_password(
    user_id: str, body: ResetPasswordBody, admin_email: str = Query(...)
):
    """Reset user password (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    auth_id = user.get("auth_id")
    if not auth_id:
        raise HTTPException(status_code=400, detail="User has no auth account")

    try:
        supabase.auth.admin.update_user_by_id(auth_id, {"password": body.new_password})
    except Exception as e:
        raise HTTPException(
            status_code=400, detail=f"Failed to reset password: {str(e)}"
        )

    log_activity(
        admin_email,
        "admin",
        "password_reset",
        target_label=user["email"],
        detail=f"Reset by {admin_email}",
    )

    return {"status": "password_reset"}


# ================================================
# SELF-SERVICE PASSWORD RESET (forgot password)
# ================================================


@router.post("/users/request-password-reset")
async def request_password_reset(body: RequestResetBody, request: Request):
    """Validate email exists, then send Supabase reset email"""
    email = body.email.strip().lower()
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=404, detail="No account found with this email")
    if not user.get("is_active", True):
        raise HTTPException(status_code=400, detail="This account has been deactivated")

    backend_base = os.environ.get("BACKEND_BASE_URL", "").rstrip("/")
    if not backend_base:
        backend_base = str(request.base_url).rstrip("/")
    redirect_url = f"{backend_base}/api/reset-password"

    supabase.auth.reset_password_for_email(email, options={"redirect_to": redirect_url})

    log_activity(email, "auth", "password_reset_requested", target_label=email)

    return {"status": "sent"}


@router.post("/users/complete-password-reset")
async def complete_password_reset(body: CompleteResetBody):
    """Verify the recovery token and set a new password"""
    user_id = None
    user_email = ""

    if body.token_hash:
        # Supabase default flow: verify token_hash via OTP verification
        try:
            response = supabase.auth.verify_otp(
                {
                    "token_hash": body.token_hash,
                    "type": "recovery",
                }
            )
            if response and response.user:
                user_id = response.user.id
                user_email = response.user.email or ""
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid or expired reset link")
    elif body.access_token:
        # Legacy flow: verify access_token JWT
        try:
            user_response = supabase.auth.get_user(body.access_token)
            if user_response and user_response.user:
                user_id = user_response.user.id
                user_email = user_response.user.email or ""
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid or expired reset link")
    else:
        raise HTTPException(status_code=400, detail="No reset token provided")

    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid or expired reset link")

    try:
        supabase.auth.admin.update_user_by_id(user_id, {"password": body.new_password})
    except Exception as e:
        raise HTTPException(
            status_code=400, detail=f"Failed to update password: {str(e)}"
        )

    log_activity(
        user_email, "auth", "password_reset_completed", target_label=user_email
    )

    return {"status": "password_updated"}


@router.patch("/users/{user_id}/screen-permissions")
async def update_screen_permissions(
    user_id: str, body: UpdateScreenPermissionsBody, admin_email: str = Query(...)
):
    """Update per-user allowed screens (admin only). Pass null to remove restrictions."""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    supabase.table("users").update({"allowed_screens": body.allowed_screens}).eq(
        "id", user_id
    ).execute()
    return {"ok": True}


@router.patch("/users/{user_id}/activate")
async def activate_user(user_id: str, admin_email: str = Query(...)):
    """Reactivate user (admin only)"""
    _require_admin(admin_email)

    user = _get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    result = (
        supabase.table("users").update({"is_active": True}).eq("id", user_id).execute()
    )

    log_activity(user["email"], "admin", "user_activated", target_label=user["email"])

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
    query = (
        supabase.table("user_activity_log")
        .select("*")
        .order("created_at", desc=True)
        .limit(limit)
        .offset(offset)
    )

    if category and category != "all":
        query = query.eq("category", category)

    result = query.execute()
    return {"logs": result.data or [], "total": len(result.data or [])}


class SignInBody(BaseModel):
    user_email: str


@router.post("/activity-log/sign-in")
async def log_sign_in(body: SignInBody):
    log_activity(body.user_email, "auth", "signed_in", target_label=body.user_email)
    return {"status": "logged"}


@router.post("/activity-log/sign-out")
async def log_sign_out(body: SignInBody):
    log_activity(body.user_email, "auth", "signed_out", target_label=body.user_email)
    return {"status": "logged"}


@router.post("/activity-log/update-check")
async def log_update_check(body: SignInBody):
    log_activity(
        body.user_email, "app", "update_checked", target_label="Check for updates"
    )
    return {"status": "logged"}
