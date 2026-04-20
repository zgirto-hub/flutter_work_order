import asyncio
import logging
import re
import time
from uuid import UUID
from typing import Optional, AsyncIterator
from db import supabase
from services.ollama_embedder import embed_single
from services.system_registry import detect_system, get_manual_ids_for_system
import services.validated_qa_service as validated_qa_service
from services.document_search_service import (
    search_document_chunks,
    fetch_parent_context,
)
from pydantic import BaseModel, Field
from typing import Optional as TypingOptional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LatencyBreakdown(BaseModel):
    embed_ms: TypingOptional[int] = Field(default=None, ge=0)
    hyde_ms: TypingOptional[int] = Field(default=None, ge=0)
    rewrite_ms: TypingOptional[int] = Field(default=None, ge=0)
    retrieval_ms: TypingOptional[int] = Field(default=None, ge=0)
    rerank_ms: TypingOptional[int] = Field(default=None, ge=0)
    generator_ms: TypingOptional[int] = Field(default=None, ge=0)
    total_ms: int = Field(ge=0)


class _StageTimer:
    """Context manager for timing a pipeline stage."""

    def __init__(self, breakdown: dict, key: str):
        self.breakdown = breakdown
        self.key = key
        self._start = 0.0

    def __enter__(self):
        self._start = time.perf_counter()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.breakdown[self.key] = None
        else:
            self.breakdown[self.key] = round((time.perf_counter() - self._start) * 1000)
        return False


def _record_stage(diagnostic: dict | None, stage: str, data: dict) -> None:
    if diagnostic is None:
        return
    diagnostic[stage] = data


def _empty_latency_breakdown() -> dict:
    return {
        "embed_ms": None,
        "hyde_ms": None,
        "rewrite_ms": None,
        "retrieval_ms": None,
        "rerank_ms": None,
        "generator_ms": None,
        "total_ms": None,
    }


# System instructions cache (avoids DB round-trip on every question)
_si_cache: dict = {"value": "", "ts": 0.0}
_SI_CACHE_TTL = 60.0  # seconds

# Chunk reranking thresholds (spec 044)
# MAX_CHUNK_DISTANCE: cosine distance ceiling; 0.30 distance = 0.70 similarity
MAX_CHUNK_DISTANCE = 0.55
# MAX_PROMPT_CHUNKS: max chunks sent to LLM after filtering
MAX_PROMPT_CHUNKS = 3

# Cross-manual synthesis limits (spec 046)
MAX_CHUNKS_PER_MANUAL = 3
MAX_MANUALS_FOR_SYNTHESIS = 8

# Direct lookup patterns for spec 077
_DIRECT_LOOKUP_RE = re.compile(
    r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"  # IP addresses
    r"|\b[a-z]{2,5}\d?-(ops|cont|mux)\b"  # Server hostnames
    r"|\b(AIDA|ATS|CISECA|IMS|eAIP|Mux|EFG)\s*\d+\b",  # Component names with numbers
    re.IGNORECASE,
)


def _is_direct_lookup(query: str) -> bool:
    """Check if query contains direct technical identifiers that bypass HyDE (spec 077)."""
    result = bool(_DIRECT_LOOKUP_RE.search(query))
    logger.info("[direct-lookup] query=%s, is_direct=%s", query[:80], result)
    return result


# --- Validated QA confidence thresholds (spec 069) ---
RAG_CONFIDENCE_THRESHOLD = 0.75  # Minimum similarity to proceed to LLM
RAG_HIGH_CONFIDENCE = 0.85  # Score >= this → confidence: "high"
VERBATIM_MIN_SIMILARITY = 0.85  # top-1 floor for verbatim short-circuit (FR-001)
VERBATIM_DOMINANCE_GAP = 0.05   # required gap between top-1 and top-2 (FR-001)


def _should_return_verbatim(matches: list[dict]) -> bool:
    """
    Return True iff the top-1 match is strong enough (>= VERBATIM_MIN_SIMILARITY)
    AND clearly dominates the top-2 (gap >= VERBATIM_DOMINANCE_GAP), OR is a lone
    match at/above the floor. Pure function of the similarity scores — no side
    effects, no I/O.

    Callers MUST have already confirmed the entry gate (max score >=
    RAG_CONFIDENCE_THRESHOLD) before consulting this helper.
    """
    if not matches:
        return False
    top1 = matches[0]["similarity"]
    if top1 < VERBATIM_MIN_SIMILARITY:
        return False
    if len(matches) == 1:
        return True
    top2 = matches[1]["similarity"]
    return (top1 - top2) >= VERBATIM_DOMINANCE_GAP


# A verbatim answer is one `validated_qa` row. If the user asks for multiple
# entities, one row can't cover the request — fall through to synthesis so
# context_parts stitches both matches together.
_COMPOUND_QUERY_RE = re.compile(
    r"\b(?:both|list\s+all|all\s+\w+s?\s+and)\b"
    r"|\b(?:server|system|device|node|site|unit)\s*\d+\b[^?]{0,60}"
    r"\band\b[^?]{0,60}\b(?:server|system|device|node|site|unit)\s*\d+\b",
    re.IGNORECASE,
)


def _is_compound_query(question: str | None) -> bool:
    """Does this query ask about multiple distinct enumerated entities?"""
    if not question:
        return False
    return bool(_COMPOUND_QUERY_RE.search(question))


# Compound queries phrase multiple entities in one sentence ("A and B"),
# which embeds further from any single curated row. Lower the entry gate
# just enough to keep them on the verified-synthesis path instead of
# falling through to manual chunks.
_COMPOUND_RAG_THRESHOLD = 0.70


def _effective_rag_threshold(question: str | None) -> float:
    if _is_compound_query(question):
        return _COMPOUND_RAG_THRESHOLD
    return RAG_CONFIDENCE_THRESHOLD


def _count_distinct_sources(matches: list[dict]) -> int:
    """Count distinct underlying curated answers (spec 068 variants share text)."""
    return len({m["validated_answer"] for m in matches}) if matches else 0


def _should_compound_verbatim(question: str | None, matches: list[dict]) -> bool:
    """Fire the compound-verbatim path when the query names multiple entities
    AND we have multiple distinct curated answers to concatenate.

    Paraphrase variants (spec 068) share validated_answer text — treat those
    as a single source, not grounds for compounding.
    """
    if not question or not matches:
        return False
    if not _is_compound_query(question):
        return False
    distinct = {m.get("validated_answer") for m in matches}
    return len(distinct) >= 2


def _build_compound_verbatim_answer(matches: list[dict]) -> str:
    """Concatenate each distinct validated_answer with blank-line separators.

    Deterministic, no LLM, preserves every answer verbatim. Used when the
    query is compound and the LLM keeps refusing one entity despite seeing
    both sources.
    """
    seen: set[str] = set()
    parts: list[str] = []
    for m in matches:
        ans = m.get("validated_answer") or ""
        if ans and ans not in seen:
            seen.add(ans)
            parts.append(ans)
    return "\n\n".join(parts)


# Same entity tokens that drive _is_compound_query. Capture each
# enumerated entity ("server 1", "device 7") so we can verify a match
# actually addresses at least one of them.
_COMPOUND_ENTITY_RE = re.compile(
    r"\b(server|system|device|node|site|unit)\s*\d+\b",
    re.IGNORECASE,
)


def _extract_compound_entities(question: str | None) -> set[str]:
    """Return the set of enumerated entities named in the query, normalized.

    E.g. "ip of cadas ats server 1 and server 2" → {"server 1", "server 2"}.
    """
    if not question:
        return set()
    out = set()
    for match in _COMPOUND_ENTITY_RE.finditer(question):
        # Collapse internal whitespace and lowercase so "Server  1" and
        # "server 1" collapse to the same token
        raw = match.group(0)
        normalized = " ".join(raw.lower().split())
        out.add(normalized)
    return out


def _filter_matches_by_entities(
    matches: list[dict], entities: set[str]
) -> list[dict]:
    """Keep only matches whose question_text mentions any of the given
    entities. If entities is empty, passthrough — the filter is no-op.

    Prevents a high-similarity but topically-irrelevant row (e.g. a
    CADAS-ATS credentials row matching a CADAS-ATS IPs query) from
    contaminating compound-verbatim output.
    """
    if not entities:
        return matches
    kept = []
    for m in matches:
        q = (m.get("question_text") or "").lower()
        q_norm = " ".join(q.split())
        if any(e in q_norm for e in entities):
            kept.append(m)
    return kept


def _build_compound_verbatim_answer_filtered(
    question: str, matches: list[dict]
) -> str:
    """Compound-verbatim with entity filter applied. Returns "" when the
    entity filter leaves fewer than 2 distinct answers — caller should
    fall back to single-row verbatim or synthesis rather than return a
    partial/misleading answer.
    """
    entities = _extract_compound_entities(question)
    filtered = _filter_matches_by_entities(matches, entities)
    distinct = {m.get("validated_answer") for m in filtered if m.get("validated_answer")}
    if len(distinct) < 2:
        return ""
    return _build_compound_verbatim_answer(filtered)


def _sub_query_for_entity(
    original: str, entity: str, other_entities: set[str]
) -> str:
    """Collapse compound 'A and B' phrasing down to just the target entity.

    For "what is the ip of server 1 and server 2" with entity="server 1"
    and other_entities={"server 2"}, returns "what is the ip of server 1".
    Handles both "A and B" and "B and A" orders.
    """
    result = original
    for other in other_entities:
        result = re.sub(
            rf"\b{re.escape(entity)}\s+and\s+{re.escape(other)}\b",
            entity, result, flags=re.IGNORECASE,
        )
        result = re.sub(
            rf"\b{re.escape(other)}\s+and\s+{re.escape(entity)}\b",
            entity, result, flags=re.IGNORECASE,
        )
    # Handle lingering "and other" fragments left behind by 3+ entity queries
    for other in other_entities:
        result = re.sub(
            rf"\s+and\s+{re.escape(other)}\b",
            "", result, flags=re.IGNORECASE,
        )
        result = re.sub(
            rf"\b{re.escape(other)}\s+and\s+",
            "", result, flags=re.IGNORECASE,
        )
    return " ".join(result.split())


async def _try_compound_verbatim(
    question: str, detected_system: str | None
) -> tuple[str | None, list[dict], int]:
    """Decompose a compound query into per-entity sub-queries and look
    each up independently.

    Compound phrasings like "A and B" poison embedding similarity so a
    single pooled query can rank both individual rows below unrelated
    rows that happen to mention either entity. Per-entity lookups avoid
    the pool entirely.

    Returns (answer_text, per_entity_matches, distinct_count) on success,
    or (None, [], 0) when we found fewer than 2 entity-matched rows.
    """
    entities = _extract_compound_entities(question)
    if len(entities) < 2:
        return (None, [], 0)

    # Import here so top-level module stays free of async dependency cycles
    import services.validated_qa_service as _vqa

    per_entity: list[dict] = []
    seen_ids: set[str] = set()

    for entity in entities:
        others = entities - {entity}
        sub_query = _sub_query_for_entity(question, entity, others)
        try:
            sub_res = await _vqa.check_validated_match(
                sub_query, detected_system=detected_system, match_count=5
            )
        except Exception as e:
            logger.warning("per-entity sub-lookup failed for %r: %s", entity, e)
            continue
        for m in sub_res.get("matches", []):
            q_norm = " ".join((m.get("question_text") or "").lower().split())
            if entity in q_norm and m["id"] not in seen_ids:
                per_entity.append(m)
                seen_ids.add(m["id"])
                break

    distinct = {
        m.get("validated_answer") for m in per_entity if m.get("validated_answer")
    }
    if len(distinct) < 2:
        return (None, [], 0)

    return (_build_compound_verbatim_answer(per_entity), per_entity, len(distinct))


async def _validated_match_for_verbatim(
    search_query: str, detected_system: str | None
) -> dict:
    """Wrap check_validated_match with a per-entity decomposition for
    compound queries. When the per-entity path yields at least 2 distinct
    entity-matched rows, return those directly — they're guaranteed to
    be on-topic. Otherwise fall back to the normal RPC.
    """
    import services.validated_qa_service as _vqa

    if _is_compound_query(search_query):
        ce_text, ce_matches, _ = await _try_compound_verbatim(
            search_query, detected_system
        )
        if ce_text:
            return {"matches": ce_matches}
    return await _vqa.check_validated_match(
        search_query,
        detected_system=detected_system,
        match_count=15 if _is_compound_query(search_query) else 5,
    )


def _resolve_verbatim_strategy(
    question: str, matches: list[dict]
) -> tuple[str | None, str | None, int]:
    """Decide how (or whether) to short-circuit to a verbatim answer.

    Returns (strategy, answer_text, source_count):
      ("compound", text, N) — concatenate entity-matched curated answers
      ("single", text, 1)   — single-row verbatim short-circuit
      (None, None, 0)       — no verbatim; caller should synthesize via LLM

    When the query is compound and the entity filter yields fewer than 2
    distinct on-topic answers, we intentionally refuse single-verbatim —
    a single answer cannot truthfully cover a multi-entity question.
    """
    if not matches:
        return (None, None, 0)

    is_compound = _is_compound_query(question)

    if is_compound and _should_compound_verbatim(question, matches):
        text = _build_compound_verbatim_answer_filtered(question, matches)
        if text:
            entities = _extract_compound_entities(question)
            filtered = _filter_matches_by_entities(matches, entities)
            return ("compound", text, _count_distinct_sources(filtered))
        # Filter failed; compound single-verbatim is wrong too → synthesize
        return (None, None, 0)

    if not is_compound and _should_return_verbatim(matches):
        return ("single", matches[0]["validated_answer"], 1)

    return (None, None, 0)


def _build_validated_qa_context(matches: list[dict]) -> str:
    """Format validated_qa matches as a labelled context block for the LLM.

    Each source header includes the question the row was curated against,
    so small models (Llama 4 Scout) can't treat Source 1 as canonical and
    dismiss the rest as "not mentioned". The question_text label surfaces
    the entity the source covers (e.g. "server 1") right in the header.
    """
    if not matches:
        return ""
    parts = []
    for i, m in enumerate(matches):
        q = (m.get("question_text") or "").strip()
        parts.append(
            f'[Source {i + 1} — answers: "{q}"]\n{m["validated_answer"]}'
        )
    return "\n\n".join(parts)


def _log_verified_served(
    user_email: str,
    question: str,
    verification_mode: str,
    top1: float,
    top2: float,
) -> None:
    """Fire-and-forget telemetry write per FR-014. Never blocks the response path."""
    try:
        from utils.activity import log_activity
        log_activity(
            user_email=user_email,
            category="manual",
            action="verified_answer_served",
            target_label=question[:80],
            target_id="",
            detail=f"mode={verification_mode};top1={top1:.3f};top2={top2:.3f}",
        )
    except Exception as e:
        logger.warning("verified_answer_served telemetry failed: %s", e)


def _build_verbatim_payload(
    matches: list[dict],
    *,
    search_query: str,
    retrieval_info: dict | None,
    latency_breakdown: dict | None,
    answer_text: str | None = None,
    source_count: int = 1,
) -> dict:
    """Build response dict for the verbatim path — NO LLM call.

    For compound-verbatim (multiple distinct rows concatenated deterministically),
    pass `answer_text` and `source_count`; otherwise defaults to single-row
    verbatim using matches[0].
    """
    top1 = matches[0]["similarity"]
    confidence = "high" if top1 >= RAG_HIGH_CONFIDENCE else "medium"
    if latency_breakdown is not None:
        latency_breakdown["generator_ms"] = 0
    return {
        "answer": answer_text if answer_text is not None else matches[0]["validated_answer"],
        "grounded": True,
        "sources": [
            {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
            for m in matches
        ],
        "confidence": confidence,
        "score": top1,
        "model": "Verbatim (no generation)",
        "provider_display_name": "Verbatim (no generation)",
        "duration_seconds": 0.0,
        "is_verified": True,
        "verified_source": {
            "validated_qa_id": str(matches[0]["id"]),
            "validated_by": matches[0]["validated_by"],
            "validated_at": (
                matches[0]["validated_at"].isoformat()
                if hasattr(matches[0]["validated_at"], "isoformat")
                else str(matches[0]["validated_at"])
            ),
            "similarity": top1,
        },
        "verification_mode": "verbatim",
        "verified_source_count": source_count,
        "retrieval_info": retrieval_info,
        "provider_used": "verbatim",
        "fallback_used": False,
        "session_summary": None,
        "search_query": search_query,
        "latency_breakdown": latency_breakdown,
        "source_type": "validated_qa",
    }

# --- Shared "not found" sentinel phrases (single source of truth) ---
_NOT_FOUND_KNOWLEDGE_BASE = "I don't have that information in the knowledge base."
_NOT_FOUND_MANUALS = "This information is not in the available manuals."
_NOT_FOUND_KNOWLEDGE_BASE_AR = "المعلومات المطلوبة غير موجودة في الأدلة المتاحة"

# --- Strict system prompt for validated QA RAG (spec 069; rule-structure port of spec 089) ---
VALIDATED_QA_SYSTEM_PROMPT = (
    "You are a technical assistant for a civil aviation maintenance management system (CMMS).\n\n"
    "Your job is to answer maintenance and operations questions using ONLY the verified "
    "context provided below. The context comes from human-approved verified answers "
    "curated by administrators.\n\n"
    "ANSWERING RULES\n"
    "===============\n\n"
    "ANSWER when:\n"
    "- The verified sources contain the procedure, values, commands, steps, or the "
    "answer the question asks for — even if phrased differently.\n"
    "- Multiple sources overlap: synthesize them into one clear answer.\n"
    "- The sources give partial information: synthesize what IS there. Do not tack "
    "on a refusal at the end.\n\n"
    "REFUSE only when:\n"
    "- The sources are about a different system or topic unrelated to the question.\n"
    "- The sources contain zero content that could address the question even partially.\n"
    "- When refusing, output this exact string and nothing else: "
    f'"{_NOT_FOUND_KNOWLEDGE_BASE}"\n\n'
    "NEVER BOTH:\n"
    "- Do not write an answer and then append a refusal sentence.\n"
    "- Either ANSWER or REFUSE — never both in the same response.\n"
    f'- Never append "{_NOT_FOUND_KNOWLEDGE_BASE}" '
    "after substantive content. If you have enough to answer, just answer.\n\n"
    "NEVER INVENT:\n"
    "- Values, credentials, commands, IP addresses, or specifications not present in "
    "the verified sources.\n"
    "- If a source mentions a topic but omits a specific value, say what the source "
    "says and flag the gap in one short sentence — do not append the refusal sentinel.\n\n"
    "MULTI-ENTITY QUESTIONS:\n"
    "- If the question names multiple distinct entities (e.g. \"server 1 and server 2\", "
    "\"both A and B\", \"list all X\"), you MUST address EACH named entity using whichever "
    "source covers it — different entities are typically in different sources.\n"
    "- Before saying an entity is \"not mentioned\" or \"not in the sources\", scan ALL "
    "provided sources for that entity. Do not declare missing after checking only Source 1.\n"
    "- Format the answer so each entity has its own labelled section or bullet group.\n\n"
    "FORMAT:\n"
    "- Be concise and direct. Use bullet points for procedures.\n"
    '- Cite the source when answering (e.g. "According to source 1...").'
)

# --- System prompt for document-sourced RAG (spec 070) ---
DOCUMENT_QA_SYSTEM_PROMPT = (
    "You are a technical assistant for a civil aviation maintenance "
    "department operating under DGCA regulations.\n"
    "The department uses these systems: CADAS-ATS, CADAS-IMS, "
    "AIDA-NG, IRTOS, and others.\n"
    "Your job is to answer maintenance and operations questions "
    "using ONLY the context provided below.\n"
    "The context comes from uploaded technical manuals.\n\n"
    # ANSWERING RULES (spec 089)
    "ANSWERING RULES\n"
    "===============\n\n"
    "ANSWER when:\n"
    "- The retrieved chunks contain the procedure, values, commands, steps, "
    "or states the question asks for — even if phrased differently.\n"
    "- The chunks give partial information: synthesize what IS there and "
    "note what is missing.\n"
    "- Technical aliases are present: ATS = CADAS-ATS, pw = password, "
    "cmd = command, ack = acknowledge, hdd = hard disk, maint = maintenance, "
    "cfg = config, db = database, ip = IP address, sw = switch, rtr = router.\n"
    "- The question uses informal technician shorthand (e.g. \"aida slow, is "
    "the disk full?\") but a chunk discusses the relevant system and "
    "metric — bridge the terminology gap.\n\n"
    "REFUSE only when:\n"
    "- The chunks are about a genuinely different system or topic unrelated "
    "to the question.\n"
    "- The chunks contain zero procedural, factual, or diagnostic content "
    "that could address the question even partially.\n"
    "- When refusing, output this exact string and nothing else: "
    f'"{_NOT_FOUND_KNOWLEDGE_BASE}"\n\n'
    "NEVER INVENT:\n"
    "- IP addresses, hostnames, credentials, or passwords not shown in a chunk.\n"
    "- Linux commands not shown in a chunk.\n"
    "- Version numbers, part numbers, or model numbers not shown in a chunk.\n"
    "- Step sequences not shown in a chunk.\n"
    "If a chunk mentions a topic but omits a specific value, say what the "
    "chunk says and flag the gap verbatim:\n"
    "\"The manual references this but does not specify the value — consult "
    "the system directly or the site password sheet.\"\n\n"
    # EXAMPLES (spec 089 — sourced from validated_qa)
    "EXAMPLES\n"
    "========\n\n"
    "Q: how to backup cadas ats\n"
    "Chunks: [CADAS-ATS Admin Manual, Database Backup section]\n"
    "A: To backup the CADAS-ATS database, follow these steps:\n\n"
    "1. Use the script `cadas_backup` on the servers.\n"
    "2. The user account used must have the Unix group.\n"
    "3. Choose from the following backup options:\n"
    "* Store the complete CADAS-ATS database (default).\n"
    "* Store only the parameter databases (`--parameters`).\n"
    "* Store only the essential parameters (`--min`).\n"
    "4. To backup data from a different CADAS-ATS server, give "
    "the IP address as an option. For example: "
    "`cadas_backup <IP address>`\n\n"
    "Q: how to make backup to cadas ats and restore\n"
    "Chunks: [CADAS-ATS Admin Manual, Backup and Restore procedures]\n"
    "A: Backup Procedure:\n"
    "1.  Use the script `cadas_backup` assigned on the servers.\n"
    "2.  Ensure the user account used has the necessary Unix group "
    "permissions.\n"
    "3.  Select the desired backup option:\n"
    "    *   Store the complete CADAS-ATS database (default option).\n"
    "    *   Store only the parameter databases (`--parameters`), "
    "which excludes dynamic data (traffic, events, statistics, "
    "active databases).\n"
    "    *   Store only the essential parameters (`--min`), which "
    "includes users, groups, mailboxes, profiles, and system "
    "parameters.\n"
    "4.  Backup files can be stored on the local file system (default "
    "option) or via CD/DVD (`--cd` or `--dvd`).\n"
    "5.  To backup data from a different CADAS-ATS server, provide "
    "the IP address as an option.\n"
    "Restore Procedure (According to Source 1, 2):\n"
    "NOTICE: When you restore the database, all existing CADAS-ATS "
    "databases are overwritten, and all current data is removed!\n"
    "Procedure:\n"
    "1.  Open a terminal window and log in as any user.\n"
    "2.  Change to the directory that contains the database backup.\n"
    "3.  Execute the restore command, specifying the necessary "
    "options and IP addresses: `sh restore_cadas_backup.sh "
    "<options> <IP addresses>`\n"
    "4.  If the terminal servers and message handlers are installed "
    "on different servers, you must specify the IP addresses of "
    "the terminal servers and the message handler servers: "
    "`msghdl <message handlers>`\n\n"
    "Q: how to stop message loop in aida ng ?\n"
    "Chunks: [AIDA-NG Admin Manual, Message Loop Troubleshooting "
    "section]\n"
    "A: To resolve a message loop in AIDA-NG, you must identify "
    "the involved Logical Addresses (LAs), disable them, analyze "
    "and solve routing problems, and remove any remaining loop "
    "messages from the queue(s).\n\n"
    "Steps to resolve a message loop:\n"
    "1. Identify the involved LA(s).\n"
    "2. Disable the involved LA(s).\n"
    "3. Analyse and solve the routing problems:\n"
    "    a. Disallow reverse transmission.\n"
    "    b. Check if the routes are configured correctly.\n"
    "    c. Check if the communication partner's routes are "
    "configured correctly.\n"
    "4. If any loop messages remain, remove them from the queue(s).\n"
    "5. Enable the involved LA(s).\n\n"
    "Q: best practices for cloud database scaling\n"
    "Chunks: [CADAS-ATS and AIDA-NG maintenance procedures — "
    "unrelated to cloud databases.]\n"
    "A: "
    f"{_NOT_FOUND_KNOWLEDGE_BASE}\n\n"
    "ANSWER FORMAT:\n"
    "- LEAD with the direct answer in 1-2 sentences. "
    'No preamble like "Based on the manual..." or '
    '"According to the provided section...".\n'
    "- Use numbered steps ONLY when the manual itself "
    "presents a procedure as steps. Do not invent structure.\n"
    "- Use bullet points for lists, thresholds, and "
    "specifications.\n"
    "- Add section headers ONLY if the answer spans 3+ "
    "genuinely distinct topics. For simple lookups "
    "(credentials, single values, single procedures), "
    "write prose.\n"
    "- Keep answers concise. Match length to complexity — "
    "short for lookups, detailed for full procedures.\n"
    "- Cite the source for each key fact "
    '(e.g. "CADAS-ATS Admin Manual, Section: Database Backup").\n\n'
    "SAFETY RULES — CRITICAL:\n"
    "- Always preserve safety warnings, cautions, and notes "
    "exactly as they appear in the source material. "
    "Never omit or summarize safety-related content.\n"
    "- If a procedure involves hazardous materials, "
    "high-voltage equipment, or critical systems, "
    "explicitly highlight the relevant precautions "
    "from the manual.\n"
    "- Never provide maintenance intervals, torque values, "
    "or technical specifications from memory. "
    "Only use values explicitly stated in the context.\n"
    "- Never recommend substituting parts, tools, "
    "or procedures not documented in the provided context.\n"
    "- Never extrapolate from one system's documentation "
    "to answer a question about a different system.\n\n"
    "REGULATORY REFERENCES:\n"
    "- Preserve all regulatory identifiers verbatim: "
    "Airworthiness Directives (ADs), Service Bulletins (SBs), "
    "AMM chapter references, DGCA regulation numbers.\n"
    "- Never paraphrase or abbreviate regulatory identifiers.\n\n"
    "CONFLICT HANDLING:\n"
    "- If two sources in the context contradict each other, "
    'clearly flag it: "⚠️ CONFLICT: Source 1 states X, '
    "but Source 2 states Y. Please verify with the "
    'original documentation."\n'
    "- Never silently pick one conflicting source over another.\n\n"
    "LANGUAGE:\n"
    "- Reply in the same language as the question.\n"
    "- If the question is in Arabic, reply fully in Arabic "
    "including all technical terms, steps, and citations.\n"
    "- Preserve Arabic text direction (RTL) in all responses.\n\n"
    "SYSTEM AMBIGUITY:\n"
    "- If the question is ambiguous about WHICH system it "
    "refers to and the conversation history does not clarify, "
    "ask the user to specify which system they mean. "
    "List the relevant systems you have documentation for.\n"
    "- If the conversation history already establishes which "
    "system is being discussed, use that context — "
    "do NOT ask again."
)

# Sentinel phrases indicating an ungrounded answer (derived from shared constants)
_SENTINEL_PHRASES = [
    _NOT_FOUND_MANUALS.lower(),
    _NOT_FOUND_KNOWLEDGE_BASE.lower(),
    _NOT_FOUND_KNOWLEDGE_BASE_AR,
]


def _get_system_instructions() -> str:
    """Read system instructions from DB, cached for 60 seconds."""
    now = time.monotonic()
    if now - _si_cache["ts"] < _SI_CACHE_TTL:
        return _si_cache["value"]
    try:
        resp = (
            supabase.table("manual_assistant_settings")
            .select("system_instructions")
            .eq("id", 1)
            .execute()
        )
        val = resp.data[0]["system_instructions"] if resp.data else ""
    except Exception:
        val = ""
    _si_cache["value"] = val
    _si_cache["ts"] = now
    return val


def _build_prompt(
    retrieved_chunks: str,
    user_question: str,
    history: list[dict] | None = None,
    memory: str | None = None,
    validated_context: str | None = None,
) -> str:
    """Assemble the 3-layer prompt: system instructions → chunks → memory → history → question."""
    parts = []

    si = _get_system_instructions()
    if si.strip():
        parts.append(si.strip())

    parts.append(
        "You are a technical assistant for a civil aviation maintenance department.\n"
        "The department uses multiple systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, and others.\n"
        "Answer the technician's question using ONLY the manual sections provided below.\n\n"
        "Rules:\n"
        "1. LEAD with the direct answer in 1-2 sentences. No preamble like "
        '"Based on the manual..." or "According to the provided section...".\n'
        "2. Only add section headers if the answer spans 3+ genuinely distinct topics. "
        "For simple lookups (credentials, values, single procedures), write prose, not sections.\n"
        "3. Keep procedures as numbered steps only when the manual itself presents steps; "
        "do not invent structure.\n"
        "4. If the answer is not found in the sections, reply exactly: "
        f'"{_NOT_FOUND_MANUALS}"\n'
        "5. Reply in the same language as the question (Arabic or English).\n"
        "6. If the question is ambiguous about WHICH system it refers to (e.g. 'forgot the admin password' "
        "without specifying CADAS-ATS or CADAS-IMS), AND the conversation history does not clarify, "
        "ask the user to specify which system they mean. List the relevant systems you have documentation for.\n"
        "7. If the conversation history already establishes which system is being discussed, "
        "use that context — do NOT ask again."
    )

    if validated_context:
        parts.append(
            "[VERIFIED REFERENCE — Expert-validated answer to a similar question]\n"
            f"{validated_context}\n\n"
        )

    parts.append(f"MANUAL SECTIONS:\n{retrieved_chunks}")

    if memory:
        parts.append(f"CONVERSATION MEMORY:\n{memory}")

    if history:
        history_block = "\n\n".join(
            f"User: {turn['question']}\nAssistant: {turn['answer']}"
            for turn in history[-10:]
        )
        parts.append(f"CONVERSATION HISTORY:\n{history_block}")

    parts.append(f"QUESTION: {user_question}\n\nANSWER:")

    return "\n\n".join(parts)


_SENT_RE = re.compile(r"(?<=[.!?؟])\s+")


class EmbedderUnavailableError(Exception):
    pass


class GeneratorUnavailableError(Exception):
    pass


def split_sentences(text: str) -> list[tuple[int, int, str]]:
    results: list[tuple[int, int, str]] = []
    cursor = 0
    for part in _SENT_RE.split(text):
        if not part.strip():
            cursor += len(part) + 1
            continue
        start = text.find(part, cursor)
        if start < 0:
            continue
        end = start + len(part)
        results.append((start, end, part))
        cursor = end
    return results


def _tokens(text: str) -> set[str]:
    return {
        w.strip(".,;:!?()[]\"'؟،").lower()
        for w in text.split()
        if len(w.strip(".,;:!?()[]\"'؟،")) >= 2
    }


def compute_highlight(
    chunk_content: str,
    answer_text: str,
    jaccard_threshold: float = 0.35,
) -> tuple[int | None, int | None]:
    chunk_sents = split_sentences(chunk_content)
    answer_sents = split_sentences(answer_text)
    if not chunk_sents or not answer_sents:
        return (None, None)

    answer_token_sets = [_tokens(s[2]) for s in answer_sents]

    best_score = 0.0
    best_range: tuple[int, int] | None = None
    for start, end, sent in chunk_sents:
        chunk_tokens = _tokens(sent)
        if not chunk_tokens:
            continue
        for a_tokens in answer_token_sets:
            if not a_tokens:
                continue
            inter = len(chunk_tokens & a_tokens)
            union = len(chunk_tokens | a_tokens)
            jaccard = inter / union if union else 0.0
            if jaccard > best_score:
                best_score = jaccard
                best_range = (start, end)

    if best_range and best_score >= jaccard_threshold:
        return best_range
    return (None, None)


# Gemma 4 E2B on the Zorin server's 15GB RAM regularly needs ~12-15s for the
# rewrite prompt; 10s was causing every follow-up to time out and fall back
# to the raw original question. 25s gives enough headroom without making
# the overall pipeline feel unresponsive.
REWRITE_GENERATE_TIMEOUT_S = 25.0


async def _rewrite_query(question: str, history: list[dict] | None, diagnostic: dict | None = None) -> str:
    # Spec 076: Intentionally hardcoded to Ollama — NOT routed through provider resolver
    """Rewrite a follow-up question into a self-contained search query using conversation context."""
    from services.ollama_generator import generate

    if not history:
        return question

    try:
        conversation_block = "\n".join(
            f"User: {turn['question']}\nAssistant: {turn['answer']}"
            for turn in history[-3:]
        )

        rewrite_prompt = (
            """You are a search query rewriter for a civil aviation maintenance department that uses multiple systems (CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, etc.).

Given a conversation history and a follow-up question, rewrite the follow-up question into a single self-contained search query. The rewritten query must:
- Resolve all pronouns and references (e.g., "it", "that", "the second point") using the conversation context
- Include the specific system name if the conversation context makes it clear which system is being discussed
- Be a complete, standalone question that would make sense without any conversation history
- Preserve the original language (Arabic or English)
- Be concise (one sentence)

Reply with ONLY the rewritten query. No explanation, no preamble.

CONVERSATION:
"""
            + conversation_block
            + """

FOLLOW-UP QUESTION: """
            + question
        )

        result = await generate(rewrite_prompt, timeout=REWRITE_GENERATE_TIMEOUT_S)
        rewritten = result.strip().strip('"').strip("'").strip()
        if not rewritten:
            logger.warning("Query rewrite returned empty, using original query")
            _record_stage(diagnostic, "rewrite", {"ran": True, "output_query": question, "input_turns": len(history)})
            return question
        logger.info(
            "[rewrite] original=%r history_turns=%d rewritten=%r",
            question, len(history), rewritten,
        )
        _record_stage(diagnostic, "rewrite", {"ran": True, "output_query": rewritten, "input_turns": len(history)})
        return rewritten
    except Exception as e:
        logger.warning("Query rewrite failed, using original query: %s", e)
        _record_stage(diagnostic, "rewrite", {"ran": True, "output_query": question, "input_turns": len(history or []), "failed": True})
        return question


async def _compress_history(
    history: list[dict],
    existing_summary: str | None = None,
    model: str | None = None,
) -> str | None:
    """Compress conversation history into a 3-4 sentence summary.

    Args:
        history: List of conversation turns (each with 'question' and 'answer' keys)
        existing_summary: Optional existing summary to potentially reuse
        model: Optional model override

    Returns:
        3-4 sentence summary string, or None on failure
    """
    from services.ollama_generator import generate, get_default_model

    turns_to_compress = history[:-4] if len(history) > 4 else history

    conversation_block = "\n".join(
        f"User: {turn['question']}\nAssistant: {turn['answer']}"
        for turn in turns_to_compress
    )

    if existing_summary:
        compression_prompt = (
            "You have a previous conversation summary and new conversation turns. "
            "Produce an updated summary of exactly 3-4 sentences that incorporates both. "
            "Preserve ALL technical facts: part numbers, specifications, procedures, "
            "measurements, and component names. "
            "Do not add information not present in the inputs.\n\n"
            f"PREVIOUS SUMMARY:\n{existing_summary}\n\n"
            f"NEW CONVERSATION:\n{conversation_block}\n\nUPDATED SUMMARY:"
        )
    else:
        compression_prompt = (
            "Summarize the following technical conversation between a user and an assistant. "
            "Produce exactly 3-4 sentences. Preserve ALL technical facts: part numbers, "
            "specifications, procedures, measurements, and component names. "
            "Do not add information not present in the conversation.\n\n"
            "CONVERSATION:\n" + conversation_block + "\n\nSUMMARY:"
        )

    try:
        result = await generate(
            compression_prompt,
            model=model or get_default_model(),
            timeout=30.0,
        )
        summary = result.strip()
        if not summary:
            logger.warning("Compression returned empty summary")
            return None
        logger.info(
            "[COMPRESS] Compressed %d turns into summary (%d chars)",
            len(turns_to_compress),
            len(summary),
        )
        return summary
    except Exception as e:
        logger.warning("[COMPRESS] Compression failed: %s", e)
        return None


async def _generate_hypothetical_answer(query: str, diagnostic: dict | None = None) -> str | None:
    # Spec 076: Intentionally hardcoded to Ollama — NOT routed through provider resolver
    """Generate a hypothetical document passage for better retrieval (HyDE)."""
    from services.ollama_generator import generate

    hyde_prompt = f"""You are a technical writer for civil aviation maintenance manuals.
Given the following question, write a short passage (1-2 paragraphs) that would appear in a civil aviation technical manual answering this question.
Write in the same language as the question (Arabic or English).
Do not add any preamble, disclaimer, or explanation. Write ONLY the manual passage.

QUESTION: {query}

MANUAL PASSAGE:
"""

    try:
        result = await generate(hyde_prompt, timeout=30.0)
        result = result.strip()
        if not result:
            logger.warning(
                "HyDE generation returned empty, falling back to direct query embedding"
            )
            _record_stage(diagnostic, "hyde", {"ran": True, "failed": True})
            return None
        logger.info("HyDE generated hypothetical answer (%d chars)", len(result))
        _record_stage(diagnostic, "hyde", {"ran": True, "output_doc": result[:500], "failed": False})
        return result
    except Exception as e:
        logger.warning(
            "HyDE generation failed, falling back to direct query embedding: %s", e
        )
        _record_stage(diagnostic, "hyde", {"ran": True, "failed": True})
        return None


# --- Layer 3 functions removed (spec 072 Phase 7) ---
# _retrieve_chunks_per_manual, _generate_sub_answers, _synthesize_answers
# replaced by document_search_service.py functions.


_LAYER3_RETIRED = True  # Layer 3 functions removed (spec 072 Phase 7)
# _retrieve_chunks_per_manual, _generate_sub_answers, _synthesize_answers
# _build_prompt, _compress_history — all retired and replaced by
# document_search_service.py functions.
# ----SPLICE_START----


async def ask_stream(
    question: str,
    manual_id_filter: Optional[UUID] = None,
    model: Optional[str] = None,
    history: list[dict] | None = None,
    session_summary: str | None = None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
    stream_meta: dict | None = None,
    diagnostic: dict | None = None,
) -> AsyncIterator[str]:
    """Streaming version of ask() — runs the full RAG pipeline, then streams generation.

    The caller passes a mutable ``stream_meta`` dict. On return it will contain:
        sources, grounded, confidence, is_verified, verified_source,
        manuals_consulted, retrieval_info, session_summary, search_query,
        provider_key, display_name, fallback_used, fallback_info.
    """
    from services.ollama_embedder import embed_single
    from services.ai_providers.resolver import (
        generate_stream as provider_generate_stream,
    )
    from services.document_search_service import (
        retrieve_chunks_per_document,
        build_direct_generation_prompt,
    )

    if latency_breakdown is None:
        latency_breakdown = _empty_latency_breakdown()
    breakdown = latency_breakdown
    if stream_meta is None:
        stream_meta = {}


    # Defaults — caller reads these after the generator is exhausted
    stream_meta.update({
        "sources": [],
        "grounded": False,
        "confidence": "low",
        "is_verified": False,
        "verified_source": None,
        "manuals_consulted": [],
        "retrieval_info": {
            "detected_system": None,
            "filtered_manual_ids": [],
            "filter_applied": False,
            "fallback_reason": None,
        },
        "session_summary": None,
        "search_query": question,
        "provider_key": "",
        "display_name": "",
        "fallback_used": False,
        "fallback_info": None,
    })

    detected_system = detect_system(question)
    stream_meta["retrieval_info"]["detected_system"] = detected_system
    search_query: str = question

    # ── Pre-rewrite validated-QA fast path (spec 067, 069) ──
    try:
        pre_rewrite_match = await _validated_match_for_verbatim(
            question, detected_system
        )
        vqa_matches = pre_rewrite_match.get("matches", [])
        if vqa_matches:
            top1 = vqa_matches[0]["similarity"]
            top2 = vqa_matches[1]["similarity"] if len(vqa_matches) > 1 else 0.0
            if top1 >= _effective_rag_threshold(question):
                max_score = top1
                verbatim_strategy, verbatim_answer_text, verbatim_source_count = (
                    _resolve_verbatim_strategy(question, vqa_matches)
                )
                is_verbatim = verbatim_strategy is not None
                verification_mode = "verbatim" if is_verbatim else "synthesized"
                verified_source_count = (
                    verbatim_source_count if is_verbatim else _count_distinct_sources(vqa_matches)
                )
                _log_verified_served(user_email, question, verification_mode, top1, top2)
                if is_verbatim:
                    stream_meta.update({
                        "sources": [
                            {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
                            for m in vqa_matches
                        ],
                        "grounded": True,
                        "confidence": "high" if top1 >= RAG_HIGH_CONFIDENCE else "medium",
                        "is_verified": True,
                        "verified_source": {
                            "validated_qa_id": str(vqa_matches[0]["id"]),
                            "validated_by": vqa_matches[0]["validated_by"],
                            "validated_at": (
                                vqa_matches[0]["validated_at"].isoformat()
                                if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                                else str(vqa_matches[0]["validated_at"])
                            ),
                            "similarity": top1,
                        },
                        "verification_mode": "verbatim",
                        "verified_source_count": verbatim_source_count,
                        "provider_key": "verbatim",
                        "display_name": "Verbatim (no generation)",
                        "fallback_used": False,
                    })
                    if breakdown is not None:
                        breakdown["generator_ms"] = 0
                    yield verbatim_answer_text
                    return
                context_parts = [_build_validated_qa_context(vqa_matches)]
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{''.join(context_parts)}\n\n"
                    f"QUESTION: {question}\n\nANSWER:"
                )
                _vqa_confidence = (
                    "high" if max_score >= RAG_HIGH_CONFIDENCE
                    else "medium" if max_score >= RAG_CONFIDENCE_THRESHOLD
                    else "low"
                )
                stream_meta.update({
                    "sources": [
                        {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
                        for m in vqa_matches
                    ],
                    "grounded": True,
                    "confidence": _vqa_confidence,
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": (
                            vqa_matches[0]["validated_at"].isoformat()
                            if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                            else str(vqa_matches[0]["validated_at"])
                        ),
                        "similarity": max_score,
                    },
                    "verification_mode": "synthesized",
                    "verified_source_count": verified_source_count,
                })
                async for token in provider_generate_stream(
                    prompt, [], user_email,
                    latency_breakdown=breakdown, stream_meta=stream_meta,
                ):
                    yield token
                return
    except Exception as e:
        logger.warning("Pre-rewrite validated_qa check failed: %s", e)

    # ── Parallel rewrite + HyDE (spec 077) ──
    _needs_rewrite = bool(history)
    _needs_hyde = not _is_direct_lookup(question)
    _hyde_already_ran = False
    _parallel_hyde_text = None

    if _needs_rewrite and _needs_hyde:
        _hyde_already_ran = True

        async def _timed_rewrite():
            with _StageTimer(breakdown, "rewrite_ms"):
                return await _rewrite_query(question, history, diagnostic=diagnostic)

        async def _timed_hyde():
            with _StageTimer(breakdown, "hyde_ms"):
                return await _generate_hypothetical_answer(question, diagnostic=diagnostic)

        rewrite_result, hyde_result = await asyncio.gather(
            _timed_rewrite(), _timed_hyde(), return_exceptions=True,
        )
        if not isinstance(rewrite_result, Exception):
            search_query = rewrite_result
        if not isinstance(hyde_result, Exception):
            _parallel_hyde_text = hyde_result
    elif _needs_rewrite:
        with _StageTimer(breakdown, "rewrite_ms"):
            search_query = await _rewrite_query(question, history, diagnostic=diagnostic)
        breakdown["hyde_ms"] = 0
    elif _needs_hyde:
        breakdown["rewrite_ms"] = 0
    else:
        breakdown["hyde_ms"] = 0
        breakdown["rewrite_ms"] = 0

    stream_meta["search_query"] = search_query

    # Follow-up system detection on rewritten query
    if detected_system is None and search_query != question:
        followup_system = detect_system(search_query)
        if followup_system:
            detected_system = followup_system
            stream_meta["retrieval_info"]["detected_system"] = followup_system

    # ── Post-rewrite validated-QA check (spec 048, 069) ──
    try:
        match_result = await _validated_match_for_verbatim(
            search_query, detected_system
        )
        vqa_matches = match_result.get("matches", [])
        if vqa_matches:
            top1 = vqa_matches[0]["similarity"]
            top2 = vqa_matches[1]["similarity"] if len(vqa_matches) > 1 else 0.0
            if top1 >= _effective_rag_threshold(question):
                max_score = top1
                verbatim_strategy, verbatim_answer_text, verbatim_source_count = (
                    _resolve_verbatim_strategy(question, vqa_matches)
                )
                is_verbatim = verbatim_strategy is not None
                verification_mode = "verbatim" if is_verbatim else "synthesized"
                verified_source_count = (
                    verbatim_source_count if is_verbatim else _count_distinct_sources(vqa_matches)
                )
                _log_verified_served(user_email, search_query, verification_mode, top1, top2)
                if is_verbatim:
                    stream_meta.update({
                        "sources": [
                            {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
                            for m in vqa_matches
                        ],
                        "grounded": True,
                        "confidence": "high" if top1 >= RAG_HIGH_CONFIDENCE else "medium",
                        "is_verified": True,
                        "verified_source": {
                            "validated_qa_id": str(vqa_matches[0]["id"]),
                            "validated_by": vqa_matches[0]["validated_by"],
                            "validated_at": (
                                vqa_matches[0]["validated_at"].isoformat()
                                if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                                else str(vqa_matches[0]["validated_at"])
                            ),
                            "similarity": top1,
                        },
                        "verification_mode": "verbatim",
                        "verified_source_count": verbatim_source_count,
                        "provider_key": "verbatim",
                        "display_name": "Verbatim (no generation)",
                        "fallback_used": False,
                    })
                    if breakdown is not None:
                        breakdown["generator_ms"] = 0
                    yield verbatim_answer_text
                    return
                context_parts = [_build_validated_qa_context(vqa_matches)]
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{''.join(context_parts)}\n\n"
                    f"QUESTION: {search_query}\n\nANSWER:"
                )
                _vqa_confidence = (
                    "high" if max_score >= RAG_HIGH_CONFIDENCE
                    else "medium" if max_score >= RAG_CONFIDENCE_THRESHOLD
                    else "low"
                )
                stream_meta.update({
                    "sources": [
                        {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
                        for m in vqa_matches
                    ],
                    "grounded": True,
                    "confidence": _vqa_confidence,
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": (
                            vqa_matches[0]["validated_at"].isoformat()
                            if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                            else str(vqa_matches[0]["validated_at"])
                        ),
                        "similarity": max_score,
                    },
                    "verification_mode": "synthesized",
                    "verified_source_count": verified_source_count,
                })
                async for token in provider_generate_stream(
                    prompt, [], user_email,
                    latency_breakdown=breakdown, stream_meta=stream_meta,
                ):
                    yield token
                return
    except Exception as e:
        logger.warning("Validated QA check failed: %s", e)

    # ── Layer 2: Document chunk search (spec 072, 074) ──
    try:
        # HyDE
        if _hyde_already_ran:
            _layer2_hyde_text = _parallel_hyde_text
        elif _needs_hyde:
            with _StageTimer(breakdown, "hyde_ms"):
                _layer2_hyde_text = await _generate_hypothetical_answer(search_query, diagnostic=diagnostic)
        else:
            _layer2_hyde_text = None
            if breakdown.get("hyde_ms") is None:
                breakdown["hyde_ms"] = 0

        embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
        with _StageTimer(breakdown, "embed_ms"):
            _layer2_embedding = await embed_single(embed_input)
        embedding_str = "[" + ",".join(str(x) for x in _layer2_embedding) + "]"

        chunks_by_doc = await retrieve_chunks_per_document(embedding_str)

        # Spec 088: Record retrieval candidates in diagnostic dict
        if diagnostic is not None:
            retrieval_candidates = []
            total_chunks = 0
            for doc_id, doc_chunks in chunks_by_doc.items():
                for c in doc_chunks:
                    total_chunks += 1
                    retrieval_candidates.append({
                        "chunk_id": c.get("id", ""),
                        "manual_title": c.get("section_title", ""),
                        "document_name": c.get("document_id", ""),
                        "score_vector": c.get("similarity", 0),
                        "score_hybrid": c.get("similarity", 0),
                        "preview": (c.get("content", "") or "")[:120],
                    })
            _record_stage(diagnostic, "retrieval", {
                "candidates": retrieval_candidates[:10],
                "k": total_chunks,
            })

        if chunks_by_doc:
            prompt, sources, docs_consulted = build_direct_generation_prompt(
                chunks_by_doc, search_query, DOCUMENT_QA_SYSTEM_PROMPT
            )

            # Pre-populate metadata (grounded will be confirmed after streaming)
            max_score = max(
                (c.get("similarity", 0) for doc_chunks in chunks_by_doc.values() for c in doc_chunks),
                default=0,
            )
            _confidence = (
                "high" if max_score >= RAG_HIGH_CONFIDENCE
                else "medium" if max_score >= RAG_CONFIDENCE_THRESHOLD
                else "low"
            )
            response_sources = [
                {
                    "type": "document",
                    "document_id": s["document_id"],
                    "display_name": s["display_name"],
                    "section_title": s.get("section_title", ""),
                    "page_number": s.get("page_number"),
                    "score": s.get("similarity", 0),
                }
                for s in sources
            ]
            stream_meta.update({
                "sources": response_sources,
                "grounded": True,
                "confidence": _confidence,
                "manuals_consulted": docs_consulted,
            })

            # Spec 088: Record rerank and grounding diagnostic stages for streaming path
            if diagnostic is not None:
                all_chunks_flat = [
                    c for doc_chunks in chunks_by_doc.values() for c in doc_chunks
                ]
                scored = sorted(all_chunks_flat, key=lambda c: c.get("similarity", 0), reverse=True)
                top_score = scored[0].get("similarity", 0) if scored else 0
                _record_stage(diagnostic, "rerank", {
                    "scored": [{"chunk_id": c.get("id", ""), "rerank_score": c.get("similarity", 0)} for c in scored[:10]],
                    "top_score": top_score,
                    "threshold_applied": MAX_CHUNK_DISTANCE,
                })
                _record_stage(diagnostic, "grounding", {
                    "verbatim_match": False,
                    "verbatim_top_similarity": top_score,
                    "sentinel_phrase_detected": False,
                    "sentinel_match": None,
                })
                _record_stage(diagnostic, "generator", {
                    "produced_answer": True,
                    "answer_length_chars": 0,
                    "refused_by_sentinel": False,
                })

            async for token in provider_generate_stream(
                prompt, [], user_email,
                latency_breakdown=breakdown, stream_meta=stream_meta,
            ):
                yield token
            return
    except Exception as e:
        logger.warning("Document chunk search failed: %s", e)

    # ── No grounded answer — clarification fallback ──
    yield _NOT_FOUND_MANUALS


async def ask(
    question: str,
    manual_id_filter: Optional[UUID] = None,
    model: Optional[str] = None,
    history: list[dict] | None = None,
    session_summary: str | None = None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
    diagnostic: dict | None = None,
) -> dict:
    from services.ollama_embedder import embed_single, EmbedderTimeoutError
    from services.ollama_generator import generate, GeneratorTimeoutError

    # Use passed-in breakdown or create new one
    if latency_breakdown is None:
        latency_breakdown = _empty_latency_breakdown()
    breakdown = latency_breakdown
    _total_start = time.perf_counter()

    detected_system = detect_system(question)
    retrieval_info: dict = {
        "detected_system": detected_system,
        "filtered_manual_ids": [],
        "filter_applied": False,
        "fallback_reason": None,
    }
    system_manual_ids: list[str] = []
    no_manuals_directive: str | None = None
    validated_context: str | None = None
    search_query: str = question  # rewritten query; default to raw question

    # Pre-rewrite validated-QA fast-path lookup (spec 067, spec 069).
    # Check for cached answer using the raw question BEFORE rewriting, so that
    # identical repeated questions hit the cache regardless of conversation history.
    import time as _time

    _vqa_pre_start = _time.monotonic()
    try:
        pre_rewrite_match = await _validated_match_for_verbatim(
            question, detected_system
        )
        vqa_matches = pre_rewrite_match.get("matches", [])

        if vqa_matches:
            top1 = vqa_matches[0]["similarity"]
            top2 = vqa_matches[1]["similarity"] if len(vqa_matches) > 1 else 0.0
            logger.info(
                "[validated-qa] pre-rewrite check: max_similarity=%.2f threshold=%.2f",
                top1,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if top1 >= _effective_rag_threshold(question):
                max_score = top1
                verbatim_strategy, verbatim_answer_text, verbatim_source_count = (
                    _resolve_verbatim_strategy(question, vqa_matches)
                )
                is_verbatim = verbatim_strategy is not None
                verification_mode = "verbatim" if is_verbatim else "synthesized"
                verified_source_count = (
                    verbatim_source_count if is_verbatim else _count_distinct_sources(vqa_matches)
                )
                _log_verified_served(user_email, question, verification_mode, top1, top2)
                if is_verbatim:
                    return _build_verbatim_payload(
                        vqa_matches,
                        search_query=search_query,
                        retrieval_info=retrieval_info,
                        latency_breakdown=breakdown,
                        answer_text=verbatim_answer_text,
                        source_count=verbatim_source_count,
                    )
                # Build combined context from top 3 matches
                combined_context = _build_validated_qa_context(vqa_matches)

                # Build the strict prompt
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {question}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.monotonic()
                (
                    answer,
                    vqa_provider_used,
                    vqa_provider_display_name,
                    vqa_fallback_used,
                    vqa_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.monotonic() - gen_start

                vqa_provider_display_name = (
                    vqa_provider_display_name or "Local (Ollama)"
                )

                # Build enriched response
                if max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                sources = [
                    {
                        "id": m["id"],
                        "question_text": m["question_text"],
                        "score": m["similarity"],
                    }
                    for m in vqa_matches
                ]

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": max_score,
                    "model": vqa_provider_display_name,
                    "provider_display_name": vqa_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": vqa_matches[0]["validated_at"].isoformat()
                        if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                        else str(vqa_matches[0]["validated_at"]),
                        "similarity": max_score,
                    },
                    "verification_mode": "synthesized",
                    "verified_source_count": verified_source_count,
                    "retrieval_info": retrieval_info,
                    "provider_used": vqa_provider_used,
                    "fallback_used": vqa_fallback_used,
                    "session_summary": None,
                    "search_query": search_query,
                    "latency_breakdown": breakdown,
                    "source_type": "validated_qa",
                }
            else:
                # Below threshold - continue to post-rewrite check
                logger.info(
                    "[validated-qa] pre-rewrite below threshold (%.2f < %.2f), trying post-rewrite",
                    top1,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[validated-qa] pre-rewrite: no matches")
    except Exception as e:
        logger.warning(
            "Pre-rewrite validated_qa check failed, falling back to normal pipeline: %s",
            e,
        )

    # Spec 077: Parallel rewrite + HyDE when both are needed
    _needs_rewrite = bool(history)
    _needs_hyde = not _is_direct_lookup(question)  # Use original question for detection
    _parallel_executed = False

    if _needs_rewrite and _needs_hyde:
        # Run both in parallel
        _parallel_executed = True

        async def _timed_rewrite():
            with _StageTimer(breakdown, "rewrite_ms"):
                return await _rewrite_query(question, history, diagnostic=diagnostic)

        async def _timed_hyde():
            with _StageTimer(breakdown, "hyde_ms"):
                return await _generate_hypothetical_answer(question, diagnostic=diagnostic)

        rewrite_result, hyde_result = await asyncio.gather(
            _timed_rewrite(), _timed_hyde(), return_exceptions=True
        )

        # Handle rewrite result
        if isinstance(rewrite_result, Exception):
            logger.warning("[spec-077] Parallel rewrite failed: %s", rewrite_result)
            search_query = question
        else:
            search_query = rewrite_result

        # Handle HyDE result
        if isinstance(hyde_result, Exception):
            logger.warning("[spec-077] Parallel HyDE failed: %s", hyde_result)
            _parallel_hyde_text = None
        else:
            _parallel_hyde_text = hyde_result
    elif _needs_rewrite:
        # Rewrite only (direct lookup — skip HyDE)
        with _StageTimer(breakdown, "rewrite_ms"):
            search_query = await _rewrite_query(question, history, diagnostic=diagnostic)
        _parallel_hyde_text = None
        breakdown["hyde_ms"] = 0
        logger.info("[spec-077] Skipping HyDE for direct lookup query")
    elif _needs_hyde:
        # No history — skip rewrite, run HyDE only (will run in Layer 2)
        search_query = question
        breakdown["rewrite_ms"] = 0
        _parallel_hyde_text = None
    else:
        # No history + direct lookup — skip both
        search_query = question
        breakdown["hyde_ms"] = 0
        breakdown["rewrite_ms"] = 0
        logger.info("[spec-077] Skipping both rewrite and HyDE")
        _parallel_hyde_text = None

    # Sentinel: _parallel_executed distinguishes "parallel ran, HyDE returned None"
    # from "parallel didn't run, HyDE still needed in Layer 2"
    _hyde_already_ran = _parallel_executed

    # Follow-up detection: if the original question had no system keyword but the
    # history-aware rewrite surfaced one (e.g. turn-1 "how to restart CADAS-ATS"
    # → turn-2 "any other steps?" → rewritten to "any other steps for CADAS-ATS?"),
    # re-run detection on the rewrite so multi-turn conversations stay scoped.
    if detected_system is None and search_query and search_query != question:
        followup_system = detect_system(search_query)
        if followup_system:
            detected_system = followup_system
            retrieval_info["detected_system"] = followup_system
            logger.info(
                "[hybrid-retrieval] detected_system=%s via-rewrite (original question had no keyword)",
                followup_system,
            )

    # Check for validated QA match using the context-resolved query (spec 048, spec 069).
    # Pass detected_system so cross-topic matches (e.g. "in english" retrieving a
    # CADAS-ATS answer in an unrelated session) are rejected at the filter layer.

    _vqa_start = _time.monotonic()
    try:
        match_result = await _validated_match_for_verbatim(
            search_query, detected_system
        )
        vqa_matches = match_result.get("matches", [])

        if vqa_matches:
            top1 = vqa_matches[0]["similarity"]
            top2 = vqa_matches[1]["similarity"] if len(vqa_matches) > 1 else 0.0
            logger.info(
                "[validated-qa] post-rewrite check: max_similarity=%.2f threshold=%.2f",
                top1,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if top1 >= _effective_rag_threshold(question):
                max_score = top1
                verbatim_strategy, verbatim_answer_text, verbatim_source_count = (
                    _resolve_verbatim_strategy(question, vqa_matches)
                )
                is_verbatim = verbatim_strategy is not None
                verification_mode = "verbatim" if is_verbatim else "synthesized"
                verified_source_count = (
                    verbatim_source_count if is_verbatim else _count_distinct_sources(vqa_matches)
                )
                _log_verified_served(user_email, search_query, verification_mode, top1, top2)
                if is_verbatim:
                    return _build_verbatim_payload(
                        vqa_matches,
                        search_query=search_query,
                        retrieval_info=retrieval_info,
                        latency_breakdown=breakdown,
                        answer_text=verbatim_answer_text,
                        source_count=verbatim_source_count,
                    )
                # Build combined context from top 3 matches
                combined_context = _build_validated_qa_context(vqa_matches)

                # Build the strict prompt
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {search_query}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.monotonic()
                (
                    answer,
                    vqa_provider_used,
                    vqa_provider_display_name,
                    vqa_fallback_used,
                    vqa_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.monotonic() - gen_start

                vqa_provider_display_name = (
                    vqa_provider_display_name or "Local (Ollama)"
                )

                # Build enriched response
                if max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                sources = [
                    {
                        "id": m["id"],
                        "question_text": m["question_text"],
                        "score": m["similarity"],
                    }
                    for m in vqa_matches
                ]

                logger.info(
                    "validated_qa hit (post-rewrite)",
                    extra={
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "detected_system": detected_system,
                        "max_similarity": max_score,
                    },
                )

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": max_score,
                    "model": vqa_provider_display_name,
                    "provider_display_name": vqa_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": vqa_matches[0]["validated_at"].isoformat()
                        if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                        else str(vqa_matches[0]["validated_at"]),
                        "similarity": max_score,
                    },
                    "verification_mode": "synthesized",
                    "verified_source_count": verified_source_count,
                    "retrieval_info": retrieval_info,
                    "provider_used": vqa_provider_used,
                    "fallback_used": vqa_fallback_used,
                    "session_summary": None,
                    "search_query": search_query,
                    "latency_breakdown": breakdown,
                    "source_type": "validated_qa",
                }
            else:
                # Below threshold - let flow continue to manual-chunks pipeline
                logger.info(
                    "[validated-qa] post-rewrite below threshold (%.2f < %.2f), falling through to manual-chunks",
                    top1,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[validated-qa] post-rewrite: no matches")
    except Exception as e:
        logger.warning(
            "Validated QA check failed, falling back to normal pipeline: %s", e
        )

    # --- Layer 2: Document chunk search (spec 072, spec 074) ---
    # Enhanced search with HyDE + per-document retrieval + direct generation.
    # Replaces sub-answer + synthesis with single generation call (spec 074).
    # HyDE + embedding are computed ONCE here and reused by Layer 3 if Layer 2 falls through.
    from services.document_search_service import (
        retrieve_chunks_per_document,
        build_direct_generation_prompt,
    )
    from services.ai_providers.resolver import generate as provider_generate

    _layer2_hyde_text = None
    _layer2_embedding = None
    provider_used = "local"
    fallback_used = False
    provider_display_name = "Local (Ollama)"

    try:
        # Use pre-computed HyDE from parallel execution if available (spec 077)
        if _hyde_already_ran:
            _layer2_hyde_text = (
                _parallel_hyde_text  # Could be None — means HyDE produced nothing
            )
            # hyde_ms already set by parallel execution
        elif _needs_hyde:
            # No history case — HyDE wasn't run in parallel, run it now
            with _StageTimer(breakdown, "hyde_ms"):
                _layer2_hyde_text = await _generate_hypothetical_answer(search_query, diagnostic=diagnostic)
        else:
            # Direct lookup — skip HyDE
            _layer2_hyde_text = None
            if breakdown.get("hyde_ms") is None:
                breakdown["hyde_ms"] = 0

        embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
        with _StageTimer(breakdown, "embed_ms"):
            _layer2_embedding = await embed_single(embed_input)
        embedding_str = "[" + ",".join(str(x) for x in _layer2_embedding) + "]"

        # Per-document retrieval
        chunks_by_doc = await retrieve_chunks_per_document(embedding_str)
        logger.info(
            "[document-search] found %d documents with chunks",
            len(chunks_by_doc) if chunks_by_doc else 0,
        )

        # Spec 088: Record retrieval candidates in diagnostic dict
        if diagnostic is not None:
            retrieval_candidates = []
            total_chunks = 0
            for doc_id, doc_chunks in (chunks_by_doc.items() if chunks_by_doc else []):
                for c in doc_chunks:
                    total_chunks += 1
                    retrieval_candidates.append({
                        "chunk_id": c.get("id", ""),
                        "manual_title": c.get("section_title", ""),
                        "document_name": c.get("document_id", ""),
                        "score_vector": c.get("similarity", 0),
                        "score_hybrid": c.get("similarity", 0),
                        "preview": (c.get("content", "") or "")[:120],
                    })
            _record_stage(diagnostic, "retrieval", {
                "candidates": retrieval_candidates[:10],
                "k": total_chunks,
            })

        if not chunks_by_doc:
            logger.info(
                "[document-search] no chunks found, falling through to manual-chunks"
            )
        else:
            # Direct generation: build combined prompt from all document chunks (spec 074)
            prompt, sources, docs_consulted = build_direct_generation_prompt(
                chunks_by_doc, search_query, DOCUMENT_QA_SYSTEM_PROMPT
            )

            # Single generation call (replaces up to 9 LLM calls)
            with _StageTimer(breakdown, "generator_ms"):
                (
                    answer,
                    provider_used,
                    provider_display_name,
                    fallback_used,
                    _fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )

            # Check if answer is grounded
            grounded = answer and not any(
                phrase in answer.lower() for phrase in _SENTINEL_PHRASES
            )

            # Spec 088: Record rerank and grounding diagnostic stages
            if diagnostic is not None:
                all_chunks_flat = [
                    c for doc_chunks in chunks_by_doc.values() for c in doc_chunks
                ]
                scored = sorted(all_chunks_flat, key=lambda c: c.get("similarity", 0), reverse=True)
                top_score = scored[0].get("similarity", 0) if scored else 0
                _record_stage(diagnostic, "rerank", {
                    "scored": [{"chunk_id": c.get("id", ""), "rerank_score": c.get("similarity", 0)} for c in scored[:10]],
                    "top_score": top_score,
                    "threshold_applied": MAX_CHUNK_DISTANCE,
                })
                _record_stage(diagnostic, "grounding", {
                    "verbatim_match": False,
                    "verbatim_top_similarity": top_score,
                    "sentinel_phrase_detected": not grounded,
                    "sentinel_match": None,
                })
                _record_stage(diagnostic, "generator", {
                    "produced_answer": bool(answer),
                    "answer_length_chars": len(answer) if answer else 0,
                    "refused_by_sentinel": not grounded,
                })

            if grounded:
                max_score = max(
                    (
                        c.get("similarity", 0)
                        for doc_chunks in chunks_by_doc.values()
                        for c in doc_chunks
                    ),
                    default=0,
                )
                confidence = (
                    "high"
                    if max_score >= RAG_HIGH_CONFIDENCE
                    else "medium"
                    if max_score >= RAG_CONFIDENCE_THRESHOLD
                    else "low"
                )

                # Format sources for response
                response_sources = []
                for s in sources:
                    response_sources.append(
                        {
                            "type": "document",
                            "document_id": s["document_id"],
                            "display_name": s["display_name"],
                            "section_title": s.get("section_title", ""),
                            "page_number": s.get("page_number"),
                            "score": s.get("similarity", 0),
                        }
                    )

                # Check for conflicts
                has_conflicts = "⚠ CONFLICT:" in answer or "⚠ تعارض:" in answer

                logger.info(
                    "direct_generation",
                    extra={
                        "documents": len(chunks_by_doc),
                        "max_score": max_score,
                    },
                )

                _total_elapsed = time.perf_counter() - _total_start
                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": response_sources,
                    "confidence": confidence,
                    "score": max_score,
                    "source_type": "document",
                    "model": provider_display_name,
                    "provider_display_name": provider_display_name,
                    "duration_seconds": round(_total_elapsed, 1),
                    "is_verified": False,
                    "verified_source": None,
                    "manuals_consulted": docs_consulted,
                    "has_conflicts": has_conflicts,
                    "retrieval_info": retrieval_info,
                    "provider_used": provider_used,
                    "fallback_used": fallback_used,
                    "session_summary": None,
                    "search_query": search_query,
                    "latency_breakdown": breakdown,
                }
            else:
                logger.info(
                    "[document-search] not grounded (answer=%s), falling through to manual-chunks",
                    answer[:100] if answer else "",
                )
    except Exception as e:
        logger.warning(
            "Document chunk search failed, falling through to manual-chunks: %s", e
        )

    # --- End Layer 2 ---

    # Spec 077: Log latency breakdown for debugging
    logged_breakdown = {k: v for k, v in breakdown.items() if v is not None}
    logger.info("[spec-077] latency_breakdown=%s", logged_breakdown)

    # No grounded answer from validated_qa or documents.
    # Layer 3 (old manual-chunks pipeline) has been retired (spec 072 Phase 7).
    # If the question seems like it could be about a specific system, ask for clarification
    # instead of the generic "not in manuals" fallback.
    fallback_answer = _NOT_FOUND_MANUALS
    try:
        from services.ai_providers.resolver import generate as provider_generate

        clarify_prompt = (
            "You are a technical assistant for a civil aviation maintenance department.\n"
            "The department uses these systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS.\n\n"
            "The user asked a question but the search returned no matching documentation.\n"
            "This might be because:\n"
            "1. The question is too vague and doesn't specify which system.\n"
            "2. The information genuinely doesn't exist in the uploaded documents.\n\n"
        )
        if history:
            history_block = "\n".join(
                f"User: {turn['question']}\nAssistant: {turn['answer']}"
                for turn in history[-3:]
            )
            clarify_prompt += f"CONVERSATION HISTORY:\n{history_block}\n\n"
        clarify_prompt += (
            f"USER QUESTION: {question}\n\n"
            "If the question could apply to multiple systems and the conversation history "
            "doesn't clarify which one, politely ask the user to specify the system.\n"
            "If the conversation history already establishes the system, say you don't have "
            "that specific information in the documentation for that system.\n"
            "Keep your response to 1-2 sentences. Reply in the same language as the question."
        )
        clarify_result, _, _ = await provider_generate(clarify_prompt)
        if clarify_result and clarify_result.strip():
            fallback_answer = clarify_result.strip()
    except Exception as e:
        logger.warning("Clarification generation failed: %s", e)

    breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
    return {
        "answer": fallback_answer,
        "grounded": False,
        "sources": [],
        "session_summary": None,
        "search_query": search_query,
        "retrieval_info": retrieval_info,
        "latency_breakdown": breakdown,
    }


