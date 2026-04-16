import logging
from db import supabase
from services.ollama_embedder import embed_single

logger = logging.getLogger(__name__)

MAX_CHUNK_DISTANCE = 0.55
MAX_CHUNKS_PER_DOCUMENT = 3
MAX_DOCUMENTS_FOR_SYNTHESIS = 8


async def retrieve_chunks_per_document(
    embedding_str: str,
    max_chunks_per_doc: int = MAX_CHUNKS_PER_DOCUMENT,
    max_documents: int = MAX_DOCUMENTS_FOR_SYNTHESIS,
) -> dict[str, list[dict]]:
    """Retrieve top qualifying chunks grouped by document ID (spec 072)."""
    try:
        rpc_response = supabase.rpc(
            "search_document_chunks",
            {
                "query_embedding": embedding_str,
                "match_count": 10,
                "match_threshold": MAX_CHUNK_DISTANCE,
            },
        ).execute()
        raw_chunks = rpc_response.data or []
    except Exception as e:
        logger.warning("Per-document retrieval RPC failed: %s", e)
        return {}

    if not raw_chunks:
        return {}

    chunks_by_document: dict[str, list[dict]] = {}
    for chunk in raw_chunks:
        doc_id = str(chunk["document_id"])
        if doc_id not in chunks_by_document:
            chunks_by_document[doc_id] = []
        distance = chunk.get("distance", 1.0)
        chunks_by_document[doc_id].append(
            {
                "id": str(chunk["id"]),
                "document_id": doc_id,
                "parent_id": str(chunk["parent_id"])
                if chunk.get("parent_id")
                else None,
                "section_title": chunk.get("section_title"),
                "content": chunk["content"],
                "page_number": chunk.get("page_number"),
                "distance": distance,
                "similarity": round(1.0 - distance, 2),
            }
        )

    qualified_docs = {}
    for doc_id, chunks in chunks_by_document.items():
        capped = chunks[:max_chunks_per_doc]
        if capped:
            qualified_docs[doc_id] = capped

    if len(qualified_docs) > max_documents:
        ranked = sorted(
            qualified_docs.items(),
            key=lambda item: (
                sum(c.get("distance", 1.0) for c in item[1]) / len(item[1])
            ),
        )
        qualified_docs = dict(ranked[:max_documents])

    for doc_id in qualified_docs:
        parent_ids = [
            c["parent_id"] for c in qualified_docs[doc_id] if c.get("parent_id")
        ]
        if parent_ids:
            try:
                parents_resp = (
                    supabase.table("document_chunks")
                    .select("id, content, section_title")
                    .in_("id", list(set(parent_ids)))
                    .execute()
                )
                parent_map = {str(p["id"]): p for p in (parents_resp.data or [])}
                for chunk in qualified_docs[doc_id]:
                    parent = parent_map.get(chunk["parent_id"])
                    if parent:
                        chunk["parent_content"] = parent["content"]
                        chunk["section_title"] = chunk.get(
                            "section_title"
                        ) or parent.get("section_title", "")
            except Exception as e:
                logger.warning("Failed to fetch parent context: %s", e)

    try:
        doc_ids = list(qualified_docs.keys())
        docs_resp = (
            supabase.table("knowledge_documents")
            .select("id, display_name")
            .in_("id", doc_ids)
            .execute()
        )
        doc_map = {str(d["id"]): d["display_name"] for d in (docs_resp.data or [])}
        for doc_id in qualified_docs:
            for chunk in qualified_docs[doc_id]:
                chunk["display_name"] = doc_map.get(doc_id, "Unknown")
    except Exception as e:
        logger.warning("Failed to fetch document metadata: %s", e)

    logger.info(
        "Per-document retrieval: %d documents with qualifying chunks",
        len(qualified_docs),
    )
    return qualified_docs


async def search_document_chunks(
    query_embedding: list[float], limit: int = 3
) -> list[dict]:
    """Search document chunks using vector similarity."""
    embedding_str = "[" + ",".join(str(x) for x in query_embedding) + "]"

    resp = supabase.rpc(
        "search_document_chunks",
        {
            "query_embedding": embedding_str,
            "match_count": limit,
            "match_threshold": 0.30,
        },
    ).execute()

    if not resp.data:
        return []

    doc_ids = list(set(r["document_id"] for r in resp.data))
    docs_resp = (
        supabase.table("knowledge_documents")
        .select("id, display_name")
        .in_("id", doc_ids)
        .execute()
    )
    doc_map = {d["id"]: d["display_name"] for d in docs_resp.data}

    results = []
    for row in resp.data:
        results.append(
            {
                "id": str(row["id"]),
                "document_id": str(row["document_id"]),
                "display_name": doc_map.get(row["document_id"], "Unknown"),
                "parent_id": str(row["parent_id"]) if row.get("parent_id") else None,
                "section_title": row["section_title"],
                "content": row["content"],
                "page_number": row["page_number"],
                "similarity": round(1.0 - row["distance"], 2),
            }
        )

    logger.info("Document search returned %d results", len(results))
    return results


def build_direct_generation_prompt(
    chunks_by_document: dict[str, list[dict]],
    question: str,
    system_prompt: str,
) -> tuple[str, list[dict], list[dict]]:
    """Build a combined prompt from all document chunks for single-pass generation.

    Replaces the sub-answer + synthesis pattern (spec 074).
    Uses the same per-document formatting as generate_document_sub_answers(),
    but combines ALL chunks into a single prompt.

    Returns:
        - prompt: Complete prompt string with context + question + ANSWER:
        - sources: Flat list of source dicts for response sources array
        - documents_consulted: List of {"id": doc_id, "title": display_name}
    """
    context_parts = []
    sources = []
    documents_consulted = []
    processed_docs = set()

    for doc_id, chunks in chunks_by_document.items():
        display_name = chunks[0].get("display_name", "Unknown")

        if doc_id not in processed_docs:
            documents_consulted.append({"id": doc_id, "title": display_name})
            processed_docs.add(doc_id)

        for i, chunk in enumerate(chunks):
            page = chunk.get("page_number")
            content = chunk.get("content", "")
            parent_content = chunk.get("parent_content", "")
            section_title = chunk.get("section_title", "")

            part = f"[Document Source {len(sources) + 1}]\n"
            part += f"Document: {display_name}\n"
            if section_title:
                part += f"Section: {section_title}\n"
            if page:
                part += f"Page: {page}\n"
            part += f"\n{parent_content or content}"
            context_parts.append(part)

            sources.append(
                {
                    "document_id": chunk.get("document_id"),
                    "display_name": display_name,
                    "section_title": section_title,
                    "page_number": page,
                    "similarity": chunk.get("similarity", 0),
                }
            )

    combined_context = "\n\n".join(context_parts)

    prompt = (
        f"{system_prompt}\n\n"
        f"CONTEXT:\n{combined_context}\n\n"
        f"QUESTION: {question}\n\nANSWER:"
    )

    return prompt, sources, documents_consulted


async def fetch_parent_context(child_matches: list[dict]) -> list[dict]:
    """Fetch full parent section content for each matched child."""
    parent_ids = list(set(m["parent_id"] for m in child_matches if m.get("parent_id")))
    if not parent_ids:
        return child_matches

    parents_resp = (
        supabase.table("document_chunks")
        .select("id, content, section_title")
        .in_("id", parent_ids)
        .execute()
    )
    parent_map = {str(p["id"]): p for p in parents_resp.data}

    for m in child_matches:
        parent = parent_map.get(m["parent_id"])
        if parent:
            m["parent_content"] = parent["content"]
            m["section_title"] = m["section_title"] or parent.get("section_title", "")

    return child_matches
