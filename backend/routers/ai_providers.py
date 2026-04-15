from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional
from db import supabase
from utils.app_settings import get_setting, set_setting
from utils.activity import log_activity
from services.ai_providers import PROVIDERS
from services.ai_providers.resolver import get_active_provider_key, _cache

router = APIRouter(tags=["ai-providers"])


class SetProviderRequest(BaseModel):
    provider: str


class ProviderInfo(BaseModel):
    key: str
    display_name: str


class ProviderListResponse(BaseModel):
    providers: List[ProviderInfo]
    active: str


@router.get("/ai/providers", response_model=ProviderListResponse)
async def list_providers():
    try:
        available_str = await get_setting("ai_providers_available")
        if available_str:
            import json

            available = json.loads(available_str)
        else:
            available = ["local"]
    except Exception:
        available = ["local"]

    active = await get_active_provider_key()

    providers_list = []
    for key in available:
        if key in PROVIDERS:
            p = PROVIDERS[key]()
            providers_list.append(ProviderInfo(key=key, display_name=p.display_name))

    return ProviderListResponse(providers=providers_list, active=active)


@router.post("/ai/provider")
async def set_provider(
    request: SetProviderRequest,
    admin_email: str = Query(...),
):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    try:
        available_str = await get_setting("ai_providers_available")
        if available_str:
            import json

            available = json.loads(available_str)
        else:
            available = ["local"]
    except Exception:
        available = ["local"]

    if request.provider not in available:
        raise HTTPException(
            status_code=400, detail=f"Provider '{request.provider}' not available"
        )

    if request.provider not in PROVIDERS:
        raise HTTPException(
            status_code=400, detail=f"Provider '{request.provider}' not found"
        )

    old = await get_active_provider_key()
    await set_setting("ai_provider", request.provider, admin_email)
    _cache["expires_at"] = 0.0

    log_activity(
        admin_email,
        category="admin",
        action="ai_provider_changed",
        target_label=request.provider,
        target_id=old,
        detail=f"old={old}",
    )

    return {"active": request.provider, "updated_at": "now()"}


class HealthResponse(BaseModel):
    provider: str
    healthy: bool
    reason: Optional[str] = None


@router.get("/ai/provider/health", response_model=HealthResponse)
async def provider_health(admin_email: str = Query(...)):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    active_key = await get_active_provider_key()
    provider = PROVIDERS[active_key]()

    try:
        healthy = await provider.health_check()
    except Exception as e:
        return HealthResponse(provider=active_key, healthy=False, reason=str(e)[:50])

    reason = None
    if not healthy:
        reason = "missing_credentials"

    return HealthResponse(provider=active_key, healthy=healthy, reason=reason)
