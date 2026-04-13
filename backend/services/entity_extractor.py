import json
import logging
import re
import sys
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)

from db import supabase
from services.ollama_generator import generate
from services.ollama_embedder import embed_single
from services.pattern_engine import evaluate_patterns


EXTRACTION_PROMPT = """You are an expert at extracting structured information from work order descriptions.

The input text may be in Arabic, English, or mixed. You MUST output all field values in English regardless of input language.

Extract the following fields from the work order text below. Return a JSON object with these exact field names:
- equipment_id (required, non-empty string — the equipment identifier, asset tag, or equipment name)
- equipment_type (optional string — type/class of equipment like "HVAC", "generator", "pump", etc.)
- fault_type (optional string — the category of fault like "mechanical", "electrical", "plumbing", "structural", etc.)
- fault_code (optional string — any fault/error code mentioned in the text)
- action_taken (optional string — what was done to address the issue)
- procedure_followed (optional string — any standard procedure or reference followed)
- parts_replaced (optional JSON array of strings — list of parts that were replaced)
- outcome (optional string — result of the work like "resolved", "pending parts", "escalated", etc.)
- technician_id (optional string — ID or name of the technician who performed the work)
- date (optional string — date of the work or service)

Example:
Input: "صيانة مولد كهربائي رقم G-102. تم تغيير بلف الضغط. الفني: أحمد. النتيجة: تم الإصلاح."
Output: {{"equipment_id": "G-102", "equipment_type": "generator", "fault_type": "mechanical", "fault_code": "", "action_taken": "replaced pressure valve", "procedure_followed": "", "parts_replaced": ["pressure valve"], "outcome": "repaired", "technician_id": "Ahmed", "date": ""}}

Input: {{work_order_text}}
Output ONLY the JSON object. No other text."""


def _clean_json_response(raw: str) -> str:
    stripped = re.sub(r"```json\s*", "", raw, flags=re.IGNORECASE)
    stripped = re.sub(r"```\s*", "", stripped)
    first_brace = stripped.find("{")
    last_brace = stripped.rfind("}")
    if first_brace == -1 or last_brace == -1:
        raise ValueError("No JSON object found in response")
    return stripped[first_brace : last_brace + 1]


def _validate_entities(data: dict) -> bool:
    if not isinstance(data, dict):
        return False
    if not isinstance(data.get("equipment_id"), str):
        return False
    if not data.get("equipment_id", "").strip():
        return False
    if data.get("parts_replaced") is None:
        data["parts_replaced"] = []
    return True


async def _embed_text(text: str) -> Optional[list[float]]:
    try:
        return await embed_single(text)
    except Exception as e:
        print(f"[entity_extractor] Embedding failed: {e}", file=sys.stderr)
        return None


def _log_extraction_failure(
    work_order_id: str,
    error_message: str,
    raw_response: Optional[str],
    attempt: int,
) -> None:
    print(
        f"[entity_extractor] FAIL WO {work_order_id} attempt {attempt}: {error_message}",
        file=sys.stderr,
    )
    try:
        supabase.table("extraction_failures").insert(
            {
                "work_order_id": work_order_id,
                "error_message": error_message,
                "raw_response": raw_response,
                "attempt_number": attempt,
            }
        ).execute()
    except Exception as e:
        print(
            f"[entity_extractor] Failed to log extraction failure: {e}",
            file=sys.stderr,
        )


async def extract_entities(work_order_id: str) -> Optional[dict]:
    try:
        result = (
            supabase.table("work_orders")
            .select("id, description, tech_notes")
            .eq("id", work_order_id)
            .execute()
        )
        if not result.data:
            print(
                f"[entity_extractor] Work order {work_order_id} not found",
                file=sys.stderr,
            )
            return None

        wo = result.data[0]
        combined = (wo.get("description") or "") + "\n" + (wo.get("tech_notes") or "")
        combined = combined.strip()
        if not combined:
            print(
                f"[entity_extractor] Skipping WO {work_order_id}: empty text",
                file=sys.stderr,
            )
            return None

        prompt = EXTRACTION_PROMPT.replace("{{work_order_text}}", combined)

        raw_response: Optional[str] = None
        parsed_data: Optional[dict] = None

        for attempt in range(1, 3):
            try:
                raw_response = await generate(prompt, model="gemma4:e2b", timeout=120.0)
                cleaned = _clean_json_response(raw_response)
                parsed_data = json.loads(cleaned)
                if _validate_entities(parsed_data):
                    break
                else:
                    _log_extraction_failure(
                        work_order_id, "empty equipment_id", raw_response, attempt
                    )
                    return None
            except Exception as e:
                if attempt == 1:
                    _log_extraction_failure(
                        work_order_id, str(e), raw_response, attempt
                    )
                    continue
                else:
                    _log_extraction_failure(
                        work_order_id, str(e), raw_response, attempt
                    )
                    print(
                        f"[entity_extractor] WO {work_order_id} failed after 2 attempts: {e}",
                        file=sys.stderr,
                    )
                    return None

        if parsed_data is None:
            return None

        embedding = await _embed_text(combined)

        payload = {
            "work_order_id": work_order_id,
            "equipment_id": parsed_data.get("equipment_id", ""),
            "equipment_type": parsed_data.get("equipment_type") or None,
            "fault_type": parsed_data.get("fault_type") or None,
            "fault_code": parsed_data.get("fault_code") or None,
            "action_taken": parsed_data.get("action_taken") or None,
            "procedure_followed": parsed_data.get("procedure_followed") or None,
            "parts_replaced": parsed_data.get("parts_replaced") or [],
            "outcome": parsed_data.get("outcome") or None,
            "technician_id": parsed_data.get("technician_id") or None,
            "date": parsed_data.get("date") or None,
            "embedding": embedding,
            "updated_at": datetime.utcnow().isoformat(),
        }

        try:
            supabase.table("work_order_entities").upsert(
                payload, on_conflict="work_order_id"
            ).execute()
        except Exception as e:
            print(
                f"[entity_extractor] Upsert failed for WO {work_order_id}: {e}",
                file=sys.stderr,
            )

        try:
            await evaluate_patterns(work_order_id)
        except Exception as e:
            logger.warning(f"Pattern evaluation failed for {work_order_id}: {e}")

        return parsed_data
    except Exception as e:
        print(
            f"[entity_extractor] Unexpected error for WO {work_order_id}: {e}",
            file=sys.stderr,
        )
        return None
