import logging

logger = logging.getLogger(__name__)


def build_contextual_prefix(
    doc_title: str | None, section_title: str | None = None
) -> str:
    if not doc_title or not doc_title.strip():
        return ""
    doc_title = doc_title.strip()
    if section_title and section_title.strip():
        return f"{doc_title} > {section_title}: "
    return f"{doc_title}: "


def apply_contextual_prefix(
    content: str,
    doc_title: str | None,
    section_title: str | None = None,
    max_chars: int = 30000,
) -> str:
    prefix = build_contextual_prefix(doc_title, section_title)
    if not prefix:
        return content
    if len(prefix) + len(content) > max_chars:
        needed = max_chars - len(content) - 7
        if needed < 0:
            logger.warning(
                "Contextual prefix truncated: content alone exceeds max_chars (%d)",
                max_chars,
            )
            return content
        doc = doc_title.strip() if doc_title else ""
        truncated_doc = doc[:needed] if needed < len(doc) else doc
        prefix = f"...{truncated_doc}: "
        logger.warning(
            "Contextual prefix truncated: combined length exceeds %d chars", max_chars
        )
    return prefix + content
