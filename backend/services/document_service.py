import logging
import os
import re
from datetime import datetime, timezone
import pdfplumber
from db import supabase
from services.ollama_embedder import embed_many
from services.document_preprocessor import preprocess_pages

logger = logging.getLogger(__name__)


async def index_document(document_id: str, file_path: str) -> None:
    """Main pipeline: extract text, preprocess, create chunks, embed children, update status."""
    try:
        ext = os.path.splitext(file_path)[1].lower()

        if ext == ".pdf":
            with pdfplumber.open(file_path) as pdf:
                pages = []
                for page in pdf.pages:
                    text = page.extract_text()
                    if text:
                        pages.append((page.page_number, text))
        elif ext in (".docx", ".txt", ".md"):
            from services.manual_parser import parse

            with open(file_path, "rb") as f:
                file_bytes = f.read()
            pages = parse(file_bytes, ext.lstrip("."))
        else:
            raise ValueError(f"Unsupported file type: {ext}")

        supabase.table("knowledge_documents").update({"total_pages": len(pages)}).eq(
            "id", document_id
        ).execute()

        doc_resp = (
            supabase.table("knowledge_documents")
            .select("display_name")
            .eq("id", document_id)
            .maybe_single()
            .execute()
        )
        document_title = doc_resp.data["display_name"] if doc_resp.data else ""

        supabase.table("knowledge_documents").update({"status": "preprocessing"}).eq(
            "id", document_id
        ).execute()

        preprocessed_pages, raw_mapping = await preprocess_pages(
            pages, document_title=document_title
        )
        pages = preprocessed_pages

        supabase.table("knowledge_documents").update({"status": "indexing"}).eq(
            "id", document_id
        ).execute()

        sections = _detect_sections(pages, file_ext=ext)

        parent_chunks = []
        for i, section in enumerate(sections):
            parent_resp = (
                supabase.table("document_chunks")
                .insert(
                    {
                        "document_id": document_id,
                        "chunk_type": "parent",
                        "section_title": section["title"],
                        "content": section["content"],
                        "page_number": section["page_number"],
                    }
                )
                .execute()
            )
            parent_chunks.append(
                {
                    "id": parent_resp.data[0]["id"],
                    "title": section["title"],
                    "page_number": section["page_number"],
                    "section_index": i,
                }
            )

        child_chunks = []
        for parent in parent_chunks:
            children = _split_into_children(sections[parent["section_index"]])
            for child in children:
                raw_content = (
                    raw_mapping.get(child["page_number"]) if raw_mapping else None
                )
                child_resp = (
                    supabase.table("document_chunks")
                    .insert(
                        {
                            "document_id": document_id,
                            "chunk_type": "child",
                            "parent_id": parent["id"],
                            "section_title": child["section_title"],
                            "content": child["content"],
                            "page_number": child["page_number"],
                            "raw_content": raw_content,
                        }
                    )
                    .execute()
                )
                child_chunks.append(
                    {
                        "id": child_resp.data[0]["id"],
                        "content": child["content"],
                    }
                )

        texts_to_embed = [c["content"] for c in child_chunks]
        embeddings = await embed_many(texts_to_embed)

        for child_chunk, embedding in zip(child_chunks, embeddings):
            embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
            supabase.table("document_chunks").update({"embedding": embedding_str}).eq(
                "id", child_chunk["id"]
            ).execute()

        supabase.table("knowledge_documents").update(
            {
                "status": "ready",
                "total_chunks": len(child_chunks),
                "indexed_at": datetime.now(timezone.utc).isoformat(),
            }
        ).eq("id", document_id).execute()

        logger.info("Document indexed successfully: %s", document_id)

    except Exception as e:
        logger.error("Document indexing failed: %s", e)
        supabase.table("knowledge_documents").update(
            {
                "status": "failed",
                "error_message": str(e),
            }
        ).eq("id", document_id).execute()


# Footer patterns to strip from all pages (vendor PDFs, slide decks)
_FOOTER_PATTERNS = [
    re.compile(r"©.*(?:Frequentis|Comsoft|GmbH).*", re.IGNORECASE),
    re.compile(r"^\d+\s*\|\s*\w+.*(?:Frequentis|General)", re.IGNORECASE),
    re.compile(r"^Frequentis\s+General\s*\|", re.IGNORECASE),
    re.compile(r"^\d+\s*$"),  # bare page numbers
]


def _clean_page_text(text: str) -> str:
    """Remove footer lines, copyright notices, and bare page numbers."""
    lines = text.split("\n")
    cleaned = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            cleaned.append("")
            continue
        if any(p.search(stripped) for p in _FOOTER_PATTERNS):
            continue
        cleaned.append(line)
    return "\n".join(cleaned).strip()


def _extract_page_title(text: str) -> str:
    """Extract the first meaningful line as page/slide title."""
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped and len(stripped) > 3 and len(stripped) < 200:
            return stripped
    return "Untitled"


def _detect_sections(
    pages: list[tuple[int, str]], file_ext: str = ".pdf"
) -> list[dict]:
    """Detect section boundaries based on file type.

    - PDFs: always use page-per-section (vendor PDFs, slides, mixed layouts)
    - TXT/MD/DOCX: try heading detection first, fall back to page-per-section
    """
    # PDFs always use page-per-section — heading detection is unreliable
    # for vendor PDFs, slide decks, and mixed-layout documents.
    if file_ext == ".pdf":
        logger.info(
            "[chunker] PDF detected — using page-per-section (%d pages)", len(pages)
        )
        return _page_per_section(pages)

    # For text-based formats, try heading detection
    heading_count = 0
    for _, page_text in pages:
        for line in page_text.split("\n"):
            stripped = line.strip()
            if not stripped:
                continue
            if re.match(r"^(\d+\.)+\d*\s+\S", stripped):
                heading_count += 1
            elif re.match(r"^(Chapter|Section)\s+\d+", stripped, re.IGNORECASE):
                heading_count += 1
            elif re.match(r"^#{1,4}\s+\S", stripped):  # Markdown headings
                heading_count += 1

    min_headings = max(5, len(pages) // 3)
    logger.info(
        "[chunker] text format=%s, heading_count=%d, threshold=%d",
        file_ext,
        heading_count,
        min_headings,
    )
    if heading_count >= min_headings:
        return _heading_based_sections(pages)

    return _page_per_section(pages)


def _heading_based_sections(pages: list[tuple[int, str]]) -> list[dict]:
    """Split by detected headings (for structured documents with numbered sections)."""
    sections = []
    current_section = {"title": "Introduction", "content": "", "page_number": 1}

    for page_num, page_text in pages:
        cleaned = _clean_page_text(page_text)
        for line in cleaned.split("\n"):
            stripped = line.strip()
            if not stripped:
                continue

            is_heading = False
            if re.match(r"^(\d+\.)+\d*\s+\S", stripped):
                is_heading = True
            elif re.match(r"^(Chapter|Section)\s+\d+", stripped, re.IGNORECASE):
                is_heading = True

            if is_heading and current_section["content"].strip():
                sections.append(current_section)
                current_section = {
                    "title": stripped,
                    "content": "",
                    "page_number": page_num,
                }
            else:
                current_section["content"] += line + "\n"

    if current_section["content"].strip():
        sections.append(current_section)

    return sections if sections else _page_per_section(pages)


def _page_per_section(pages: list[tuple[int, str]]) -> list[dict]:
    """Each page becomes one section. Best for slide decks and vendor PDFs."""
    sections = []
    for page_num, page_text in pages:
        cleaned = _clean_page_text(page_text)
        if len(cleaned) < 50:
            continue  # skip cover pages, blank pages, title-only slides

        title = _extract_page_title(cleaned)
        sections.append(
            {
                "title": title,
                "content": cleaned,
                "page_number": page_num,
            }
        )

    # If all pages were too short individually but the document has content,
    # combine everything into one section so tiny docs remain searchable.
    if not sections:
        all_text = "\n".join(_clean_page_text(text) for _, text in pages).strip()
        if all_text:
            sections.append(
                {
                    "title": _extract_page_title(all_text),
                    "content": all_text,
                    "page_number": pages[0][0] if pages else None,
                }
            )

    return sections


def _split_into_children(section: dict) -> list[dict]:
    """Split section content into child chunks.

    Strategy:
    - Try splitting on double newlines first (structured documents).
    - If that produces < 2 chunks, the content likely uses single newlines
      (slide decks, bullet lists). In that case, treat the entire section
      as one child chunk — the parent already represents the page.
    """
    content = section["content"].strip()
    if not content:
        return []

    # Short content (< 50 chars) is still valuable for tiny documents
    # (e.g. password notes, single-line procedures). Always produce a child.
    if len(content) < 50:
        return [
            {
                "content": content,
                "section_title": section["title"],
                "page_number": section["page_number"],
            }
        ]

    # Try double-newline split first
    paragraphs = content.split("\n\n")
    children = [p.strip() for p in paragraphs if len(p.strip()) >= 50]

    if len(children) >= 2:
        # Structured document: multiple paragraphs per section
        return [
            {
                "content": c,
                "section_title": section["title"],
                "page_number": section["page_number"],
            }
            for c in children
        ]

    # Slide/bullet content: treat the whole section as one child chunk.
    # This ensures every page with content gets at least one searchable child.
    return [
        {
            "content": content,
            "section_title": section["title"],
            "page_number": section["page_number"],
        }
    ]


async def reindex_document(document_id: str) -> None:
    """Delete existing chunks and re-run indexing pipeline."""
    supabase.table("document_chunks").delete().eq("document_id", document_id).execute()

    doc_resp = (
        supabase.table("knowledge_documents")
        .select("file_path")
        .eq("id", document_id)
        .maybe_single()
        .execute()
    )
    if doc_resp.data:
        await index_document(document_id, doc_resp.data["file_path"])


async def delete_document(document_id: str) -> bool:
    """Delete document row, chunks (cascade), and PDF file from disk."""
    doc_resp = (
        supabase.table("knowledge_documents")
        .select("file_path")
        .eq("id", document_id)
        .maybe_single()
        .execute()
    )
    if doc_resp.data:
        file_path = doc_resp.data["file_path"]
        try:
            if os.path.exists(file_path):
                os.remove(file_path)
        except FileNotFoundError:
            pass

    supabase.table("knowledge_documents").delete().eq("id", document_id).execute()
    return True
