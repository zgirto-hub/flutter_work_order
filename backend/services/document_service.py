import logging
import os
import re
import pdfplumber
from db import supabase
from services.ollama_embedder import embed_many

logger = logging.getLogger(__name__)


async def index_document(document_id: str, file_path: str) -> None:
    """Main pipeline: extract text, create chunks, embed children, update status."""
    try:
        supabase.table("knowledge_documents").update({"status": "indexing"}).eq(
            "id", document_id
        ).execute()

        pdf = pdfplumber.open(file_path)
        pages = []
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                pages.append((page.page_number, text))
        pdf.close()

        supabase.table("knowledge_documents").update({"total_pages": len(pages)}).eq(
            "id", document_id
        ).execute()

        sections = _detect_sections(pages)

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
                }
            )

        child_chunks = []
        for parent in parent_chunks:
            children = _split_into_children(
                {
                    "title": parent["title"],
                    "content": next(
                        s["content"] for s in sections if s["title"] == parent["title"]
                    ),
                    "page_number": parent["page_number"],
                }
            )
            for child in children:
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
                "indexed_at": "now()",
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


def _detect_sections(pages: list[tuple[int, str]]) -> list[dict]:
    """Detect section boundaries across pages."""
    sections = []
    current_section = {"title": "Introduction", "content": "", "page_number": 1}
    has_heading = False

    for page_num, page_text in pages:
        lines = page_text.split("\n")
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue

            is_heading = False
            if re.match(r"^(\d+\.)+\d*\s+\S", stripped):
                is_heading = True
            elif re.match(r"^(Chapter|Section)\s+\d+", stripped, re.IGNORECASE):
                is_heading = True
            elif (
                stripped == stripped.upper()
                and len(stripped) < 80
                and len(stripped) > 3
            ):
                is_heading = True
            elif stripped.endswith(":") and len(stripped) < 60:
                is_heading = True

            if is_heading and current_section["content"]:
                sections.append(current_section)
                current_section = {
                    "title": stripped,
                    "content": "",
                    "page_number": page_num,
                }
                has_heading = True
            else:
                current_section["content"] += line + "\n"

    if current_section["content"]:
        sections.append(current_section)

    if not has_heading:
        return _fixed_size_chunking(pages)

    return sections


def _fixed_size_chunking(pages: list[tuple[int, str]]) -> list[dict]:
    """Fallback: split text into fixed-size chunks when no headings detected."""
    full_text = "\n\n".join(text for _, text in pages)

    chunk_size = 2000
    overlap = 500
    sections = []
    offset = 0
    page_offset = 0

    for i, (page_num, _) in enumerate(pages):
        if i > 0:
            page_offset += len(pages[i - 1][1])

    while offset < len(full_text):
        chunk = full_text[offset : offset + chunk_size]
        estimated_page = 1
        char_count = 0
        for i, (page_num, text) in enumerate(pages):
            char_count += len(text)
            if char_count > offset:
                estimated_page = page_num
                break

        sections.append(
            {
                "title": f"Section {len(sections) + 1}",
                "content": chunk,
                "page_number": estimated_page,
            }
        )
        offset += chunk_size - overlap

    return sections


def _split_into_children(section: dict) -> list[dict]:
    """Split section content into child chunks on double newlines."""
    paragraphs = section["content"].split("\n\n")
    children = []
    for para in paragraphs:
        para = para.strip()
        if len(para) >= 50:
            children.append(
                {
                    "content": para,
                    "section_title": section["title"],
                    "page_number": section["page_number"],
                }
            )
    return children


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
