from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional, List, Tuple
import httpx
import json
import time
from enum import Enum

from db import supabase
from services.ollama_generator import (
    generate,
    GeneratorTimeoutError,
    GeneratorModelError,
)
from services.ai_providers.resolver import generate as resolver_generate
from utils.app_settings import get_setting
from utils.activity import log_activity
from services.rate_limiter import rate_limiter

router = APIRouter()

OLLAMA_MODEL = "gemma4:e2b"


class DocumentExpertAction(str, Enum):
    improve = "improve"
    correct = "correct"
    generate = "generate"
    translate = "translate"
    concise = "concise"
    elaborate = "elaborate"
    custom = "custom"


class DocumentExpertRequest(BaseModel):
    action: DocumentExpertAction
    html_content: Optional[str] = None
    target_language: str = "ar"
    instructions: Optional[str] = None


class AiSuggestRequest(BaseModel):
    title: str
    location: Optional[str] = None
    type: Optional[str] = None


class AiParseWorkOrderRequest(BaseModel):
    text: str
    language: str = "en"
    departments: List[str] = []
    types: List[str] = []
    statuses: List[str] = []


def _build_document_expert_prompt(
    action: str,
    html_content: Optional[str],
    target_language: str,
    instructions: Optional[str],
) -> str:
    base_persona = "أنت خبير في كتابة المراسلات الرسمية الحكومية باللغة العربية الفصحى. أنت متخصص في دواوين الحكومة الكويتية ومراسلات الطيران المدني."

    action_prompts = {
        "improve": "أعد كتابة المستند بأسلوب رسمي متميز، صحح Grammar، حسن التراكيب، حافظ على المعنى الأصلي.",
        "correct": "صححGrammar والإملاء فقط، تجنب التغييرات الجوهرية، حافظ على بنية المستند.",
        "generate": "اكتب خطاباً رسمياً كاملاً بناءً على الملاحظات أو التعليمات المقدمة.",
        "translate": "ترجم المستند إلى اللغة المطلوبة مع الحفاظ على الأسلوب الرسمي.",
        "concise": "اختصر المستند مع الاحتفاظ بجميع النقاط الأساسية.",
        "elaborate": "وسع المستند بعبارات رسمية حكومية مفصلة.",
        "custom": "",
    }

    prompt = base_persona + " " + action_prompts.get(action, "")

    if target_language == "en":
        prompt += " Write in formal English."
    else:
        prompt += " اكتب باللغة العربية الفصحى."

    if instructions:
        prompt += f" التعليمات الإضافية: {instructions}"

    if html_content:
        prompt += f" نص المستند:\n{html_content}"

    prompt += (
        "\nأعد المحتوى فقط كفقرات HTML بسيطة باستخدام وسوم <p> و <br> فقط."
        "\nلا تضع المحتوى داخل <div> أو <blockquote> أو <section> أو أي حاوية."
        "\nلا تستخدم علامات markdown مثل ```html أو ```."
        "\nلا تضف أي مقدمة أو شرح أو تعليق. أعد وسوم <p> مباشرة."
    )

    return prompt


def _strip_code_fences(text: str) -> str:
    """Remove ```html ... ``` or ``` ... ``` markdown code fences."""
    import re

    stripped = text.strip()
    # Match ```html\n...\n``` or ```\n...\n```
    fence_pattern = re.compile(
        r"^```(?:html|HTML)?\s*\n?(.*?)\n?```\s*$",
        re.DOTALL,
    )
    m = fence_pattern.match(stripped)
    if m:
        return m.group(1).strip()
    # Also strip leading/trailing single-line fences
    stripped = re.sub(r"^```(?:html|HTML)?\s*", "", stripped)
    stripped = re.sub(r"\s*```\s*$", "", stripped)
    return stripped.strip()


def _unwrap_outer_container(html: str) -> str:
    """If the entire HTML is wrapped in a single <div>/<blockquote>/<section>,
    unwrap it. Leaves content as inline <p> tags."""
    import re

    s = html.strip()
    # Match <div ...>...</div> as the sole outer element
    for tag in ("div", "blockquote", "section", "article"):
        pattern = re.compile(
            rf"^<{tag}\b[^>]*>(.*)</{tag}>\s*$",
            re.DOTALL | re.IGNORECASE,
        )
        m = pattern.match(s)
        if m:
            s = m.group(1).strip()
            break
    return s


def _build_parse_prompt(
    text: str,
    language: str,
    departments: List[str],
    types: List[str],
    statuses: List[str],
) -> str:
    prompt = "You are a work order parsing assistant.\n"
    prompt += "Parse the following user input into structured work order fields.\n"
    prompt += "Return ONLY a JSON object with these keys: title, description, location, type, department, status.\n"
    prompt += "For the description field: expand all abbreviations and shorthand into full professional language. Fix grammar and spelling errors. Write 2-4 complete sentences.\n"

    if departments:
        prompt += f"\nValid departments: {', '.join(departments)}"
    if types:
        prompt += f"\nValid types: {', '.join(types)}"
    if statuses:
        prompt += f"\nValid statuses: {', '.join(statuses)}"

    if language == "ar":
        prompt += "\nRespond in Arabic. All field values must be in Arabic."
    elif language == "en":
        prompt += "\nRespond in English."

    prompt += "\nIf you cannot determine a field, set it to null."
    prompt += "\nDo NOT include any text outside the JSON object. No preamble, no explanation."
    prompt += f"\nUser input: {text}"

    return prompt


def _extract_json(text: str) -> dict:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("No valid JSON found in response")
    json_str = text[start : end + 1]
    return json.loads(json_str)


def _validate_parse_response(
    data: dict, departments: List[str], types: List[str], statuses: List[str]
) -> dict:
    result = {}

    result["title"] = data.get("title")
    result["description"] = data.get("description")
    result["location"] = data.get("location")

    type_val = data.get("type")
    result["type"] = type_val if type_val in types else None

    dept_val = data.get("department")
    result["department"] = dept_val if dept_val in departments else None

    status_val = data.get("status")
    result["status"] = status_val if status_val in statuses else None

    return result


def _strip_preamble(text: str) -> str:
    lines = text.split("\n")
    preamble_phrases = [
        "here",
        "sure",
        "of course",
        "certainly",
        "below",
        "i'd",
        "i would",
    ]
    start_idx = 0
    for i, line in enumerate(lines):
        stripped = line.strip().lower()
        if not stripped:
            start_idx = i + 1
            continue
        is_preamble = False
        for phrase in preamble_phrases:
            if stripped.startswith(phrase):
                is_preamble = True
                break
        if is_preamble:
            start_idx = i + 1
        else:
            break
    result = "\n".join(lines[start_idx:]).strip()
    if not result:
        return text.strip()
    return result


def _build_prompt(title: str, location: Optional[str], type: Optional[str]) -> str:
    prompt = f"Write a professional 2-4 sentence work order description for the following:\nTitle: {title}\n"
    if location and location.strip():
        prompt += f"Location: {location}\n"
    if type and type.strip():
        prompt += f"Type: {type}\n"
    prompt += "\nProvide only the description text. Do not include any preamble, greeting, or commentary."
    return prompt


@router.post("/ai/suggest")
async def suggest_description(request: AiSuggestRequest):
    title = request.title.strip()
    if not title:
        raise HTTPException(status_code=422, detail="Title cannot be empty")

    prompt = _build_prompt(title, request.location, request.type)

    try:
        response_text = await generate(prompt, model=OLLAMA_MODEL, timeout=120.0)
    except (GeneratorTimeoutError, GeneratorModelError):
        raise HTTPException(status_code=503, detail="AI service timed out")
    except Exception:
        raise HTTPException(status_code=502, detail="AI model error")

    stripped = _strip_preamble(response_text)
    if not stripped:
        raise HTTPException(
            status_code=502, detail="AI model returned an empty response"
        )

    return {"description": stripped}


@router.post("/ai/parse-work-order")
async def parse_work_order(request: AiParseWorkOrderRequest):
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Text cannot be empty")

    prompt = _build_parse_prompt(
        request.text,
        request.language,
        request.departments,
        request.types,
        request.statuses,
    )

    try:
        response_text = await generate(prompt, model=OLLAMA_MODEL, timeout=120.0)
    except (GeneratorTimeoutError, GeneratorModelError):
        raise HTTPException(status_code=503, detail="AI service timed out")
    except Exception:
        raise HTTPException(status_code=502, detail="AI model error")

    try:
        parsed = _extract_json(response_text)
    except ValueError:
        raise HTTPException(status_code=502, detail="AI returned invalid response")

    validated = _validate_parse_response(
        parsed, request.departments, request.types, request.statuses
    )

    return validated


class AutofillWorkOrderRequest(BaseModel):
    description: str = Field(..., min_length=1)
    language: str = "en"
    departments: List[str] = []
    types: List[str] = []
    statuses: List[str] = []


def _build_autofill_prompt(
    description: str,
    language: str,
    departments: List[str],
    types: List[str],
    statuses: List[str],
    outcomes: List[str],
) -> str:
    prompt = (
        "You are a work order drafting assistant.\n"
        "Given the following user description, generate structured work order fields.\n"
        "Return ONLY a JSON object with these keys: "
        "title, description, priority, category, asset_name, fault_description, action_taken, outcome.\n"
        "\n"
        "Rules:\n"
        "- title: short, professional work order title (max 100 chars)\n"
        "- description: expanded professional description (2-4 sentences)\n"
        "- priority: one of 'Low', 'Medium', 'High', 'Critical' (or null if unclear)\n"
        "- category: must match one of the valid departments listed below (or null)\n"
        "- asset_name: name of the equipment/asset mentioned (or null)\n"
        "- fault_description: concise description of the fault/problem (or null)\n"
        "- action_taken: suggested action (or empty string if unknown)\n"
        "- outcome: suggested outcome (or empty string if unknown)\n"
        "- For any field you cannot determine, set it to null or empty string\n"
        "- Do NOT include any text outside the JSON object\n"
    )

    if departments:
        prompt += f"\nValid departments (for category field): {', '.join(departments)}"
    if types:
        prompt += f"\nValid types: {', '.join(types)}"
    if statuses:
        prompt += f"\nValid statuses: {', '.join(statuses)}"
    if outcomes:
        prompt += f"\nValid outcomes: {', '.join(outcomes)}"

    if language == "ar":
        prompt += "\nIMPORTANT: All field values (title, description, etc.) MUST be in Arabic. Only the JSON keys remain in English."
    else:
        prompt += "\nRespond in English."

    prompt += f"\nUser description: {description}"
    return prompt


def _validate_autofill_response(data: dict, departments: List[str], types: List[str]) -> dict:
    result = {}
    result["title"] = data.get("title")
    result["description"] = data.get("description")
    result["priority"] = data.get("priority")
    result["asset_name"] = data.get("asset_name")
    result["fault_description"] = data.get("fault_description")
    result["action_taken"] = data.get("action_taken") or ""
    result["outcome"] = data.get("outcome") or ""

    category_val = data.get("category")
    result["category"] = category_val if category_val in departments else None

    type_val = data.get("type")
    result["type"] = type_val if type_val in types else None

    return result


@router.post("/ai/autofill-work-order")
async def autofill_work_order(
    request: AutofillWorkOrderRequest,
    user_email: str = Query(...),
):
    description = request.description.strip()
    if len(description) < 20:
        raise HTTPException(
            status_code=422,
            detail="Description must be at least 20 characters",
        )
    if len(description) > 500:
        raise HTTPException(
            status_code=422,
            detail="Description must be at most 500 characters",
        )

    user_resp = (
        supabase.table("users").select("user_type,email").eq("email", user_email).execute()
    )
    if not user_resp or not getattr(user_resp, 'data', None) or len(user_resp.data) == 0:
        raise HTTPException(status_code=401, detail="Not authenticated")

    enabled = await get_setting("ai_work_order_enabled")
    if enabled != "true":
        raise HTTPException(status_code=403, detail="AI Work Order feature is disabled")

    allowed, retry_after = await rate_limiter.check(user_email)
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Too many requests. Try again in {retry_after} seconds.",
        )

    outcomes = ["Resolved", "Pending Parts", "Escalated", "Monitoring"]

    prompt = _build_autofill_prompt(
        request.description,
        request.language,
        request.departments,
        request.types,
        request.statuses,
        outcomes,
    )

    start_time = time.time()
    provider_used = "local"

    try:
        response_text, provider_key, _, _, _ = await resolver_generate(
            prompt,
            user_email=user_email,
        )
        provider_used = provider_key
    except Exception:
        elapsed = time.time() - start_time
        log_activity(
            user_email,
            category="ai",
            action="autofill_work_order_failed",
            target_id=None,
            detail=f"provider=none elapsed={elapsed:.1f}s error=generation_failed",
        )
        raise HTTPException(status_code=502, detail="AI could not generate a work order draft. Please try again.")

    elapsed = time.time() - start_time

    try:
        parsed = _extract_json(response_text)
    except ValueError:
        log_activity(
            user_email,
            category="ai",
            action="autofill_work_order_failed",
            target_id=None,
            detail=f"provider={provider_used} elapsed={elapsed:.1f}s error=invalid_json",
        )
        raise HTTPException(status_code=502, detail="AI returned invalid response")

    validated = _validate_autofill_response(
        parsed, request.departments, request.types
    )

    log_activity(
        user_email,
        category="ai",
        action="autofill_work_order",
        target_id=None,
        detail=f"provider={provider_used} elapsed={elapsed:.1f}s",
    )

    return validated


@router.get("/ai/autofill-work-order/status")
async def autofill_work_order_status():
    enabled = await get_setting("ai_work_order_enabled")
    from datetime import datetime, timezone
    return {"enabled": enabled == "true"}


@router.post("/ai/document-expert")
async def document_expert(request: DocumentExpertRequest):
    action = (
        request.action.value
        if isinstance(request.action, DocumentExpertAction)
        else request.action
    )

    if action == "custom":
        if not request.instructions or not request.instructions.strip():
            raise HTTPException(
                status_code=422, detail="instructions is required for custom action"
            )
    elif action != "generate":
        if not request.html_content or not request.html_content.strip():
            raise HTTPException(
                status_code=422, detail="html_content is required for this action"
            )

    prompt = _build_document_expert_prompt(
        action,
        request.html_content,
        request.target_language,
        request.instructions,
    )

    try:
        response_text = await generate(prompt, model=OLLAMA_MODEL, timeout=120.0)
    except (GeneratorTimeoutError, GeneratorModelError):
        raise HTTPException(status_code=503, detail="AI service timed out")
    except Exception:
        raise HTTPException(status_code=502, detail="AI model error")

    stripped = _strip_preamble(response_text)
    stripped = _strip_code_fences(stripped)
    stripped = _unwrap_outer_container(stripped)
    if not stripped:
        raise HTTPException(
            status_code=502, detail="AI model returned an empty response"
        )

    return {"html_content": stripped}


@router.get("/ai/health")
async def ai_health():
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            res = await client.get("http://localhost:11434/api/tags")
            if res.status_code == 200:
                return {"available": True}
            return {"available": False}
    except Exception:
        return {"available": False}
