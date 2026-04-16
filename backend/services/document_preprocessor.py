import os
import asyncio
import logging
from dataclasses import dataclass
from typing import List, Tuple, Dict, Optional

logger = logging.getLogger(__name__)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")


@dataclass
class PreprocessResult:
    preprocessed_text: str
    success: bool
    fallback_used: bool
    rate_limited: bool = False


SYSTEM_PROMPT = """You are a document preprocessing expert. Your task is to transform raw extracted text from documents into clean, structured, and searchable content.

Follow these rules:

1. For terse bullet points or incomplete sentences: Rewrite them into complete, self-contained sentences that preserve all original factual content. Add implicit context from headings/titles to make the information understandable on its own.

2. Preserve all original factual content - NEVER hallucinate, invent, or add information not present or directly implied by the original text.

3. Preserve heading hierarchy and paragraph structure. Use appropriate Markdown heading levels (# for main titles, ## for sections, ### for subsections).

4. Output clean, well-formatted Markdown.

5. For already-rich prose with full paragraphs: Apply only minimal cleanup (whitespace normalization, consistent heading levels). DO NOT rewrite or expand content that is already complete and clear.

6. NEVER add any wrapper Markdown like "# Page N" unless it was in the original text."""


async def preprocess_page(
    raw_text: str, page_number: int, document_title: str = ""
) -> PreprocessResult:
    if len(raw_text.strip()) < 50:
        return PreprocessResult(
            preprocessed_text=raw_text, success=True, fallback_used=False
        )

    if not GEMINI_API_KEY:
        logger.warning(
            f"Gemini API key not set, falling back to raw text for page {page_number}"
        )
        return PreprocessResult(
            preprocessed_text=raw_text, success=False, fallback_used=True
        )

    try:
        from google.generativeai import GenerativeModel

        model = GenerativeModel("gemini-2.5-flash")

        user_prompt = ""
        if document_title:
            user_prompt = f"Document: {document_title}\n\n"
        user_prompt += raw_text

        full_prompt = f"{SYSTEM_PROMPT}\n\n{user_prompt}"

        async def _call():
            return await model.generate_content_async(full_prompt)

        response = await asyncio.wait_for(_call(), timeout=30.0)

        if response and response.text and response.text.strip():
            logger.info(f"Successfully preprocessed page {page_number}")
            return PreprocessResult(
                preprocessed_text=response.text.strip(),
                success=True,
                fallback_used=False,
            )
        else:
            logger.warning(f"Empty response for page {page_number}, using fallback")
            return PreprocessResult(
                preprocessed_text=raw_text, success=False, fallback_used=True
            )

    except asyncio.TimeoutError:
        logger.warning(f"Timeout preprocessing page {page_number}, using fallback")
        return PreprocessResult(
            preprocessed_text=raw_text, success=False, fallback_used=True
        )
    except Exception as e:
        error_msg = str(e)
        is_rate_limit = "429" in error_msg or "rate_limit" in error_msg.lower()
        if is_rate_limit:
            logger.warning(f"Rate limit error for page {page_number}, using fallback")
            return PreprocessResult(
                preprocessed_text=raw_text,
                success=False,
                fallback_used=True,
                rate_limited=True,
            )
        else:
            logger.error(f"Error preprocessing page {page_number}: {error_msg}")
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

    if not GEMINI_API_KEY:
        logger.warning("GEMINI_API_KEY not set, skipping preprocessing")
        return pages, {}

    preprocessed_pages = []
    raw_mapping: Dict[int, str] = {}
    preprocessed_count = 0
    fallback_count = 0
    total = len(pages)

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

        result = await _preprocess_page_with_retry(
            page_number, raw_text, document_title
        )

        if result.success:
            logger.info(
                f"Page {page_number}: preprocessed (fallback={result.fallback_used})"
            )
            preprocessed_count += 1
        else:
            logger.info(f"Page {page_number}: fallback used")
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
            logger.warning(f"Failed to log preprocessing activity: {e}")

    return preprocessed_pages, raw_mapping


async def _preprocess_page_with_retry(
    page_number: int, raw_text: str, document_title: str = ""
) -> PreprocessResult:
    """Process a single page with retry logic for rate limit errors only."""
    backoff_times = [2, 4, 8]
    last_result = None

    for attempt in range(len(backoff_times) + 1):
        result = await preprocess_page(raw_text, page_number, document_title)
        last_result = result

        if result.success:
            return result

        if not result.rate_limited:
            return result

        if attempt < len(backoff_times):
            wait_time = backoff_times[attempt]
            logger.warning(
                f"Rate limited, retry page {page_number}, attempt {attempt + 1}/{len(backoff_times)} after {wait_time}s"
            )
            await asyncio.sleep(wait_time)

    return last_result
