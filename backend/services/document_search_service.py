import logging
from db import supabase

logger = logging.getLogger(__name__)


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
