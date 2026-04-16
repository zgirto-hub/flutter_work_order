import os
import asyncio
import logging
import httpx
from dataclasses import dataclass
from typing import List, Tuple, Dict, Optional

logger = logging.getLogger(__name__)

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_PREPROCESS_MODEL = os.environ.get("OLLAMA_PREPROCESS_MODEL", "gemma4:e2b")
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")


@dataclass
class PreprocessResult:
    preprocessed_text: str
    success: bool
    fallback_used: bool


SYSTEM_PROMPT = """You are a document preprocessing expert. Your task is to transform raw extracted text from documents into clean, structured, and searchable content.

Follow these rules:

1. For terse bullet points or incomplete sentences: Rewrite them into complete, self-contained sentences that preserve all original factual content. Add implicit context from headings/titles to make the information understandable on its own.

2. Preserve all original factual content - NEVER hallucinate, invent, or add information not present or directly implied by the original text.

3. Preserve heading hierarchy and paragraph structure. Use appropriate Markdown heading levels (# for main titles, ## for sections, ### for subsections).

4. Output clean, well-formatted Markdown.

5. For already-rich prose with full paragraphs: Apply only minimal cleanup (whitespace normalization, consistent heading levels). DO NOT rewrite or expand content that is already complete and clear.

6. NEVER add any wrapper Markdown like "# Page N" unless it was in the original text.

7. NEVER prepend the document title or filename to your output. The document title is provided only as context to help you understand the content — do NOT include it in your response.

8. Output ONLY the cleaned/enhanced version of the page content. No preamble, no explanation, no metadata."""


async def preprocess_page(
    raw_text: str, page_number: int, document_title: str = ""
) -> PreprocessResult:
    if len(raw_text.strip()) < 50:
        return PreprocessResult(
            preprocessed_text=raw_text, success=True, fallback_used=False
        )

    try:
        user_prompt = ""
        if document_title:
            user_prompt = f"Document: {document_title}\n\n"
        user_prompt += raw_text

        full_prompt = f"{SYSTEM_PROMPT}\n\n{user_prompt}"

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": OLLAMA_PREPROCESS_MODEL,
                    "prompt": full_prompt,
                    "stream": False,
                    "keep_alive": OLLAMA_KEEP_ALIVE,
                },
            )
            response.raise_for_status()
            data = response.json()
            text = data.get("response", "").strip()

        if text:
            logger.info("Successfully preprocessed page %d", page_number)
            return PreprocessResult(
                preprocessed_text=text,
                success=True,
                fallback_used=False,
            )
        else:
            logger.warning("Empty response for page %d, using fallback", page_number)
            return PreprocessResult(
                preprocessed_text=raw_text, success=False, fallback_used=True
            )

    except httpx.TimeoutException:
        logger.warning("Timeout preprocessing page %d, using fallback", page_number)
        return PreprocessResult(
            preprocessed_text=raw_text, success=False, fallback_used=True
        )
    except Exception as e:
        logger.error("Error preprocessing page %d: %s", page_number, e)
        return PreprocessResult(
            preprocessed_text=raw_text, success=False, fallback_used=True
        )


async def preprocess_pages(
    pages: List[Tuple[int, str]],
    document_title: str = "",
    document_id: Optional[str] = None,
) -> Tuple[List[Tuple[int, str]], Dict[int, str]]:
    from utils.app_settings import get_setting

    setting_value = await get_setting("smart_preprocessing_enabled")
    if setting_value == "false":
        logger.info("Smart preprocessing disabled, returning pages unchanged")
        return pages, {}

    # Quick health check — is Ollama reachable?
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{OLLAMA_URL}/api/tags")
            resp.raise_for_status()
    except Exception:
        logger.warning("Ollama not reachable at %s, skipping preprocessing", OLLAMA_URL)
        return pages, {}

    preprocessed_pages = []
    raw_mapping: Dict[int, str] = {}
    preprocessed_count = 0
    fallback_count = 0

    # Update progress in DB so frontend can show a progress bar
    def _update_progress(current: int):
        if not document_id:
            return
        try:
            from db import supabase

            supabase.table("knowledge_documents").update(
                {"preprocessing_progress": current}
            ).eq("id", document_id).execute()
        except Exception:
            pass  # fire-and-forget, don't block pipeline

    for idx, (page_number, raw_text) in enumerate(pages):
        raw_mapping[page_number] = raw_text

        result = await preprocess_page(raw_text, page_number, document_title)

        if result.success:
            logger.info(
                "Page %d: preprocessed (fallback=%s)", page_number, result.fallback_used
            )
            preprocessed_count += 1
        else:
            logger.info("Page %d: fallback used", page_number)
            fallback_count += 1

        preprocessed_pages.append((page_number, result.preprocessed_text))
        _update_progress(idx + 1)

    if document_id:
        try:
            from utils.activity import log_activity

            log_activity(
                user_email="system",
                category="document",
                action="document_preprocessed",
                target_id=document_id,
                detail=f"total_pages={len(pages)}, preprocessed={preprocessed_count}, fallback={fallback_count}",
            )
        except Exception as e:
            logger.warning("Failed to log preprocessing activity: %s", e)

    return preprocessed_pages, raw_mapping
