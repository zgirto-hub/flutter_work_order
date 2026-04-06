from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import httpx
import json
from enum import Enum

router = APIRouter()

OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_MODEL = "gemma4:e2b"
OLLAMA_TIMEOUT = 120.0


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

    prompt += "\nأعد فقط نص المستند بصيغة HTML. لا تضف أي مقدمة أو شرح."

    return prompt


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
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            res = await client.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
            )
    except (httpx.ConnectError, httpx.ConnectTimeout):
        raise HTTPException(
            status_code=503, detail="AI service is currently unavailable"
        )
    except httpx.ReadTimeout:
        raise HTTPException(status_code=503, detail="AI service timed out")

    if res.status_code != 200:
        raise HTTPException(status_code=502, detail="AI model error")

    try:
        data = res.json()
        response_text = data.get("response", "")
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
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            res = await client.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
            )
    except (httpx.ConnectError, httpx.ConnectTimeout):
        raise HTTPException(
            status_code=503, detail="AI service is currently unavailable"
        )
    except httpx.ReadTimeout:
        raise HTTPException(status_code=503, detail="AI service timed out")

    if res.status_code != 200:
        raise HTTPException(status_code=502, detail="AI model error")

    try:
        data = res.json()
        response_text = data.get("response", "")
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


@router.post("/ai/document-expert")
async def document_expert(request: DocumentExpertRequest):
    action = request.action.value if isinstance(request.action, DocumentExpertAction) else request.action

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
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            res = await client.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
            )
    except (httpx.ConnectError, httpx.ConnectTimeout):
        raise HTTPException(
            status_code=503, detail="AI service is currently unavailable"
        )
    except httpx.ReadTimeout:
        raise HTTPException(status_code=503, detail="AI service timed out")

    if res.status_code != 200:
        raise HTTPException(status_code=502, detail="AI model error")

    try:
        data = res.json()
        response_text = data.get("response", "")
    except Exception:
        raise HTTPException(status_code=502, detail="AI model error")

    stripped = _strip_preamble(response_text)
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
