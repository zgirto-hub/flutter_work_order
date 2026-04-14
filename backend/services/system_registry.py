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
    aliases = [
        alias for alias, canonical in SYSTEM_ALIASES.items() if canonical == system_name
    ]
    if not aliases:
        return []

    try:
        response = (
            supabase_client.table("manuals").select("id, title, file_name").execute()
        )
        manual_ids: list[str] = []
        seen_ids: set[str] = set()

        for row in response.data or []:
            title = (row.get("title") or "").lower()
            file_name = (row.get("file_name") or "").lower()
            if any(
                alias.lower() in title or alias.lower() in file_name
                for alias in aliases
            ):
                manual_id = str(row.get("id"))
                if manual_id and manual_id not in seen_ids:
                    seen_ids.add(manual_id)
                    manual_ids.append(manual_id)

        return manual_ids
    except Exception as e:
        logger.warning("[hybrid-retrieval] manual lookup failed: %s", e)
        return []
