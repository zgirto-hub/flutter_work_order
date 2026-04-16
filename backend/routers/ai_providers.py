from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, timezone
from db import supabase
from utils.app_settings import get_setting, set_setting
from utils.activity import log_activity
from services.ai_providers import PROVIDERS
from services.ai_providers.resolver import get_active_provider_key, invalidate_cache

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
    invalidate_cache()

    log_activity(
        admin_email,
        category="admin",
        action="ai_provider_changed",
        target_label=request.provider,
        target_id=old,
        detail=f"old={old}",
    )

    return {
        "active": request.provider,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


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


class GeminiModelInfo(BaseModel):
    id: str
    name: str
    free_quota: str


class GeminiModelResponse(BaseModel):
    models: List[GeminiModelInfo]
    active_model: str


class SetGeminiModelRequest(BaseModel):
    model: str


@router.get("/ai/gemini/models", response_model=GeminiModelResponse)
async def list_gemini_models(admin_email: str = Query(...)):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    from services.ai_providers.gemini import GEMINI_MODELS, DEFAULT_GEMINI_MODEL

    active = await get_setting("gemini_model") or DEFAULT_GEMINI_MODEL
    return GeminiModelResponse(
        models=[GeminiModelInfo(**m) for m in GEMINI_MODELS],
        active_model=active,
    )


@router.post("/ai/gemini/model")
async def set_gemini_model(
    request: SetGeminiModelRequest,
    admin_email: str = Query(...),
):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    from services.ai_providers.gemini import GEMINI_MODELS

    if not any(m["id"] == request.model for m in GEMINI_MODELS):
        raise HTTPException(status_code=400, detail=f"Unknown model: {request.model}")

    old = await get_setting("gemini_model") or "gemini-2.0-flash"
    await set_setting("gemini_model", request.model, admin_email)

    log_activity(
        admin_email,
        category="admin",
        action="gemini_model_changed",
        target_label=request.model,
        target_id=old,
        detail=f"old={old}",
    )

    return {"active_model": request.model}


class SmartPreprocessingResponse(BaseModel):
    enabled: bool
    updated_at: Optional[str] = None


class SetPreprocessingRequest(BaseModel):
    enabled: bool


@router.get("/settings/smart-preprocessing", response_model=SmartPreprocessingResponse)
async def get_smart_preprocessing(admin_email: str = Query(...)):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    value = await get_setting("smart_preprocessing_enabled")
    return SmartPreprocessingResponse(enabled=value == "true")


@router.put("/settings/smart-preprocessing", response_model=SmartPreprocessingResponse)
async def set_smart_preprocessing(
    request: SetPreprocessingRequest,
    admin_email: str = Query(...),
):
    user_resp = (
        supabase.table("users").select("user_type").eq("email", admin_email).execute()
    )
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    await set_setting(
        "smart_preprocessing_enabled",
        "true" if request.enabled else "false",
        admin_email,
    )

    log_activity(
        admin_email,
        category="admin",
        action="smart_preprocessing_toggled",
        target_label=str(request.enabled),
        detail=f"enabled={request.enabled}",
    )

    return SmartPreprocessingResponse(
        enabled=request.enabled,
        updated_at=datetime.now(timezone.utc).isoformat(),
    )
