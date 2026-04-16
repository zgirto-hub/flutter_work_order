import logging
import time
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


async def generate_document_sub_answers(
    chunks_by_document: dict[str, list[dict]],
    question: str,
    history: list[dict] | None = None,
    memory: str | None = None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> tuple[list[dict], str, bool, str]:
    """Generate a sub-answer for each document's chunks (spec 072)."""
    from services.ai_providers.resolver import generate as provider_generate
    from services.manual_rag_service import DOCUMENT_QA_SYSTEM_PROMPT, _SENTINEL_PHRASES

    sub_answers = []
    provider_used = "local"
    fallback_used = False
    provider_display_name = "Local (Ollama)"

    for doc_id, chunks in chunks_by_document.items():
        display_name = chunks[0].get("display_name", "Unknown")

        context_parts = []
        sources = []
        for i, chunk in enumerate(chunks):
            page = chunk.get("page_number")
            content = chunk.get("content", "")
            parent_content = chunk.get("parent_content", "")
            section_title = chunk.get("section_title", "")

            part = f"[Document Source {i + 1}]\n"
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
                    "chunk_index": i,
                    "page_number": page,
                    "content_preview": content[:500],
                }
            )

        combined_context = "\n\n".join(context_parts)

        prompt = (
            f"{DOCUMENT_QA_SYSTEM_PROMPT}\n\n"
            f"CONTEXT:\n{combined_context}\n\n"
            f"QUESTION: {question}\n\nANSWER:"
        )

        try:
            (
                answer_text,
                prov_used,
                prov_display,
                fb_used,
                _fallback_info,
            ) = await provider_generate(
                prompt, [], user_email, latency_breakdown=latency_breakdown
            )
            provider_used = prov_used or provider_used
            provider_display_name = prov_display or provider_display_name
            fallback_used = fallback_used or fb_used
        except Exception as e:
            logger.warning(
                "Sub-answer generation failed for document %s: %s", doc_id, e
            )
            answer_text = ""

        grounded = answer_text and not any(
            phrase in answer_text.lower() for phrase in _SENTINEL_PHRASES
        )

        sub_answers.append(
            {
                "answer": answer_text,
                "grounded": grounded,
                "document_id": doc_id,
                "display_name": display_name,
                "sources": sources,
                "provider_used": provider_used,
                "fallback_used": fallback_used,
                "provider_display_name": provider_display_name,
            }
        )

    return sub_answers, provider_used, fallback_used, provider_display_name


async def synthesize_document_answers(
    sub_answers: list[dict],
    question: str,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> dict:
    """Combine grounded sub-answers into one synthesized answer (spec 072)."""
    from services.ai_providers.resolver import generate as provider_generate
    from services.manual_rag_service import _SENTINEL_PHRASES

    grounded = [s for s in sub_answers if s.get("grounded")]

    if not grounded:
        return {
            "answer": "This information is not in the available manuals.",
            "synthesized": False,
            "documents_consulted": [],
            "has_conflicts": False,
            "grounded": False,
        }

    if len(grounded) == 1:
        sa = grounded[0]
        return {
            "answer": sa["answer"],
            "synthesized": False,
            "documents_consulted": [
                {"id": sa["document_id"], "title": sa["display_name"]}
            ],
            "has_conflicts": False,
            "grounded": True,
            "provider_used": sa.get("provider_used", "local"),
            "fallback_used": sa.get("fallback_used", False),
            "provider_display_name": sa.get("provider_display_name", "Local (Ollama)"),
        }

    document_answers_block = "\n\n".join(
        f"[Document: {sa['display_name']}]\n{sa['answer']}" for sa in grounded
    )

    synthesis_prompt = (
        "You are a technical synthesis expert for civil aviation maintenance.\n"
        "You have answers from multiple documents to the same question.\n\n"
        "Rules:\n"
        "1. LEAD with the direct answer in 1-2 sentences. No preamble, no headers before the answer.\n"
        "2. Only add section headers if the answer spans 3+ genuinely distinct topics. "
        "For simple lookups (credentials, values, single procedures), write prose, not sections.\n"
        '3. Attribute inline when useful (e.g., "per [Document X], ..."), not as bullet lists of sources.\n'
        "4. If documents AGREE, state once and cite agreeing documents.\n"
        "5. Only flag a CONFLICT if documents directly contradict each other on the same fact. "
        "Complementary info (one says 'ask IT', another gives a procedure) is NOT a conflict — "
        "just present the concrete procedure.\n"
        "6. If one document has the concrete answer and another says 'info not available' or "
        "'verify with supervisor', IGNORE the latter — do not mention it.\n"
        "7. Reply in the same language as the question (Arabic or English).\n\n"
        f"QUESTION: {question}\n\n"
        f"DOCUMENT ANSWERS:\n{document_answers_block}\n\n"
        "ANSWER:"
    )

    try:
        (
            synthesized,
            provider_used,
            provider_display_name,
            fallback_used,
            fallback_info,
        ) = await provider_generate(
            synthesis_prompt, [], user_email, latency_breakdown=latency_breakdown
        )
    except Exception as e:
        logger.warning("Synthesis failed, returning first sub-answer: %s", e)
        first = grounded[0]
        return {
            "answer": first["answer"],
            "synthesized": False,
            "documents_consulted": [
                {"id": first["document_id"], "title": first["display_name"]}
            ],
            "has_conflicts": False,
            "grounded": True,
            "provider_used": first.get("provider_used", "local"),
            "fallback_used": first.get("fallback_used", False),
            "provider_display_name": first.get(
                "provider_display_name", "Local (Ollama)"
            ),
        }

    answer_text = synthesized.strip()
    has_conflicts = "⚠ CONFLICT:" in answer_text or "⚠ تعارض:" in answer_text

    return {
        "answer": answer_text,
        "synthesized": True,
        "documents_consulted": [
            {"id": sa["document_id"], "title": sa["display_name"]} for sa in grounded
        ],
        "has_conflicts": has_conflicts,
        "grounded": True,
        "provider_used": provider_used,
        "fallback_used": fallback_used,
        "provider_display_name": provider_display_name,
    }


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
