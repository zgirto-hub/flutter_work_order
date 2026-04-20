import logging
from typing import Optional


logger = logging.getLogger(__name__)


KNOWN_SYSTEMS: list[str] = [
    "International Circuits",
    "INDRA CCTV",
    "Billing System",
    "CADAS-ATS",
    "CADAS-IMS",
    "AIDA-NG",
    "Permissions",
    "IRTOS",
    "AFTN",
    "UPS",
]

SYSTEM_ALIASES: dict[str, str] = {
    "International Circuits": "International Circuits",
    "INDRA CCTV": "INDRA CCTV",
    "Billing System": "Billing System",
    "CADAS ATS": "CADAS-ATS",
    "CADAS-ATS": "CADAS-ATS",
    "CADAS IMS": "CADAS-IMS",
    "CADAS-IMS": "CADAS-IMS",
    "AIDA NG": "AIDA-NG",
    "AIDA-NG": "AIDA-NG",
    "Permissions": "Permissions",
    "IRTOS": "IRTOS",
    "AFTN": "AFTN",
    "UPS": "UPS",
}

_SORTED_ALIASES: list[tuple[str, str]] = sorted(
    ((alias.lower(), canonical) for alias, canonical in SYSTEM_ALIASES.items()),
    key=lambda item: len(item[0]),
    reverse=True,
)


import re


def detect_system(question: str) -> Optional[str]:
    question_lower = question.lower()
    for alias_lower, canonical in _SORTED_ALIASES:
        pattern = r"(?<![a-z0-9])" + re.escape(alias_lower) + r"(?![a-z0-9])"
        if re.search(pattern, question_lower):
            return canonical
    return None


async def get_manual_ids_for_system(system_name: str, supabase_client) -> list[str]:
    """Return knowledge_documents IDs whose display_name or filename
    contains any alias of `system_name`.

    The legacy `manuals` table is empty in production; the live corpus
    lives in `knowledge_documents`. The field name `manual_ids` is kept
    as-is on the validated_qa side for compatibility.
    """
    aliases = [
        alias for alias, canonical in SYSTEM_ALIASES.items() if canonical == system_name
    ]
    if not aliases:
        return []

    try:
        response = (
            supabase_client.table("knowledge_documents")
            .select("id, display_name, filename")
            .execute()
        )
        manual_ids: list[str] = []
        seen_ids: set[str] = set()

        for row in response.data or []:
            display_name = (row.get("display_name") or "").lower()
            filename = (row.get("filename") or "").lower()
            if any(
                alias.lower() in display_name or alias.lower() in filename
                for alias in aliases
            ):
                doc_id = str(row.get("id"))
                if doc_id and doc_id not in seen_ids:
                    seen_ids.add(doc_id)
                    manual_ids.append(doc_id)

        return manual_ids
    except Exception as e:
        logger.warning("[hybrid-retrieval] knowledge_documents lookup failed: %s", e)
        return []
