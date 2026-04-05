from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import httpx

router = APIRouter()

OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_MODEL = "gemma4:e2b"
OLLAMA_TIMEOUT = 60.0


class AiSuggestRequest(BaseModel):
    title: str
    location: Optional[str] = None
    type: Optional[str] = None


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
