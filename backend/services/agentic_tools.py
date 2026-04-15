import json
import logging
import re
import time

from db import supabase
from services.ollama_generator import generate, get_default_model
from services.manual_rag_service import ask as manual_rag_ask, _StageTimer

logger = logging.getLogger(__name__)

TOOL_MANIFEST = """You have access to the following tools to help answer user questions:

1. work_orders
   Description: Query work order records from the database. Use this when the user asks about specific work orders, their status, or details.
   Parameters:
   - work_order_number (str, optional): Filter by work order job number (e.g., "WO260413-HYD01")
   - status (str, optional): Filter by work order status. Valid values: "Pending", "In Progress", "Resolved", "Closed"
   - equipment_type (str, optional): Filter by equipment type (e.g., "generator", "pump")
   - date_from (str, optional): Filter work orders created on or after this date (YYYY-MM-DD)
   - date_to (str, optional): Filter work orders created on or before this date (YYYY-MM-DD)

2. manuals
   Description: Search technical manuals for procedures, maintenance schedules, and technical specifications. Use this when the user asks about procedures, specifications, or technical documentation.
   Parameters:
   - query (str, required): The question to search the manuals for

3. compare
   Description: Compare a work order's data against a manual procedure to check for compliance or discrepancies.
   Parameters:
   - work_order_data (str, required): Summary of the work order data from the work_orders tool
   - manual_procedure (str, required): Summary of the relevant procedure from the manuals tool

Instructions:
- If the question can be answered from your knowledge or the conversation context alone, answer directly WITHOUT calling any tool. Only use tools when you need external data you don't already have.
- If the user asks whether a work order follows a procedure, you should use all three tools: work_orders, then manuals, then compare.
- When you want to call a tool, output exactly:
  TOOL_CALL: <tool_name>
  PARAMS: <json>
- For example:
  TOOL_CALL: work_orders
  PARAMS: {"work_order_number": 1042}
- If no tool is needed, just provide your answer directly.
- Do not include any other text before "TOOL_CALL:" or after the PARAMS line unless you are providing your final answer.
- If you decide a tool is needed, you MUST call it now. Do not answer the question without using a tool if one is needed.
- After receiving tool results, you may call another tool or provide your final answer. Use this format to continue:
  TOOL_CALL: <tool_name>
  PARAMS: <json>
  Or if done:
  FINAL_ANSWER: <your answer>
"""

VALID_TOOLS = {"work_orders", "manuals", "compare"}

# Keywords that signal the question may need tools (work order data)
_WO_KEYWORDS = re.compile(
    r"work\s*order|wo\d|wo-|wo\s*#|job\s*(no|number)|status\s*of\s*(wo|work)|"
    r"pending\s*work|open\s*work|closed\s*work|in\s*progress\s*work|"
    r"compare.*procedure|follow.*procedure|match.*manual|comply|compliance|discrepancy",
    re.IGNORECASE,
)


def _needs_tools(question: str) -> bool:
    """Quick keyword check — does the question likely need agentic tools?"""
    return bool(_WO_KEYWORDS.search(question))


def parse_tool_call(response_text: str) -> tuple[str | None, dict | None]:
    """
    Parse a tool call from the model's response.

    Args:
        response_text: The raw response from the model

    Returns:
        Tuple of (tool_name, params_dict) if found, or (None, None) if no tool call
    """
    tool_call_pattern = re.compile(r"^TOOL_CALL:\s*(\w+)\s*$", re.MULTILINE)
    params_pattern = re.compile(r"^PARAMS:\s*(.+)$", re.MULTILINE)

    tool_match = tool_call_pattern.search(response_text)
    if not tool_match:
        return (None, None)

    tool_name = tool_match.group(1)

    if tool_name not in VALID_TOOLS:
        logger.warning(f"Unknown tool name in response: {tool_name}")
        return (None, None)

    params_match = params_pattern.search(response_text, tool_match.start())
    if not params_match:
        logger.warning(f"Tool call found but no PARAMS line for tool: {tool_name}")
        return (None, None)

    params_json = params_match.group(1).strip()
    try:
        params = json.loads(params_json)
    except json.JSONDecodeError as e:
        logger.warning(f"Invalid JSON in PARAMS for tool {tool_name}: {e}")
        return (None, None)

    return (tool_name, params)


async def execute_work_orders_tool(params: dict) -> dict:
    """
    Execute the work_orders tool to query Supabase work_orders table.

    Args:
        params: Dict with optional filters: work_order_number, status, equipment_type,
                technician_name, date_from, date_to

    Returns:
        Dict with success flag, data, truncated flag, and count
    """
    try:
        query = supabase.table("work_orders").select(
            "job_no, status, title, description, type, location, "
            "created_at, closed_at, signature_status, tech_notes, "
            "departments(name)"
        )

        wo_num = params.get("work_order_number") or params.get("job_no")
        if wo_num:
            query = query.eq("job_no", str(wo_num))

        if "status" in params:
            # Normalize status to title case to match DB values
            # (Pending, In Progress, Resolved, Closed)
            raw_status = params["status"].strip()
            status_map = {
                "pending": "Pending",
                "in progress": "In Progress",
                "resolved": "Resolved",
                "closed": "Closed",
                "open": "In Progress",  # common alias
            }
            normalized = status_map.get(raw_status.lower(), raw_status)
            query = query.eq("status", normalized)

        if "equipment_type" in params:
            query = query.ilike("type", f"%{params['equipment_type']}%")

        if "date_from" in params:
            query = query.gte("created_at", params["date_from"])

        if "date_to" in params:
            query = query.lte("created_at", params["date_to"])

        result = query.limit(20).execute()

        if not result.data:
            return {"success": True, "data": [], "truncated": False, "count": 0}

        formatted_wo = []
        for row in result.data:
            dept = row.get("departments")
            formatted_wo.append(
                {
                    "job_no": row.get("job_no"),
                    "title": row.get("title"),
                    "status": row.get("status"),
                    "description": row.get("description"),
                    "type": row.get("type"),
                    "location": row.get("location"),
                    "department": dept.get("name") if isinstance(dept, dict) else None,
                    "created_at": row.get("created_at"),
                    "closed_at": row.get("closed_at"),
                    "signature_status": row.get("signature_status"),
                    "tech_notes": row.get("tech_notes"),
                }
            )

        truncated = len(result.data) == 20
        return {
            "success": True,
            "data": formatted_wo,
            "truncated": truncated,
            "count": len(formatted_wo),
        }

    except Exception as e:
        logger.error(f"execute_work_orders_tool error: {e}")
        return {"success": False, "data": [], "error": str(e)}


async def execute_manuals_tool(
    params: dict,
    manual_id_filter=None,
    model=None,
    history=None,
    session_summary=None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> dict:
    """
    Execute the manuals tool using the existing manual_rag_service.ask() function.

    Args:
        params: Dict with required "query" key
        manual_id_filter: Optional filter for specific manual IDs
        model: Optional model override
        history: Optional conversation history
        session_summary: Optional session summary context
        user_email: Optional user email, threaded to manual_rag_ask for audit
        latency_breakdown: Optional dict to record stage timings; passed
            through to manual_rag_service.ask() which populates per-stage
            keys via its internal _StageTimer wrappers. We do NOT wrap
            manual_rag_ask here — doing so would record the whole pipeline
            into a single key.

    Returns:
        Dict with success, answer, sources, and grounded status
    """
    try:
        query = params.get("query")
        if not query:
            return {
                "success": False,
                "data": {},
                "error": "Missing required parameter: query",
            }

        result = await manual_rag_ask(
            question=query,
            manual_id_filter=manual_id_filter,
            model=model,
            history=history,
            session_summary=session_summary,
            user_email=user_email,
            latency_breakdown=latency_breakdown,
        )

        return {
            "success": True,
            "data": {
                "answer": result.get("answer", ""),
                "sources": result.get("sources", []),
                "grounded": result.get("grounded", False),
                "manuals_consulted": result.get("manuals_consulted", []),
                "has_conflicts": result.get("has_conflicts", False),
            },
        }

    except Exception as e:
        logger.error(f"execute_manuals_tool error: {e}")
        return {"success": False, "data": {}, "error": str(e)}


async def execute_compare_tool(params: dict, model: str | None = None) -> dict:
    """
    Execute the compare tool to compare work order data against a manual procedure.

    Args:
        params: Dict with "work_order_data" and "manual_procedure" keys
        model: Optional model override

    Returns:
        Dict with success and comparison result
    """
    try:
        work_order_data = params.get("work_order_data", "")
        manual_procedure = params.get("manual_procedure", "")

        if not work_order_data or not manual_procedure:
            return {
                "success": False,
                "data": {},
                "error": "Missing required parameters",
            }

        comparison_prompt = f"""Compare the following work order data against the manual procedure and provide a structured comparison.

WORK ORDER DATA:
{work_order_data}

MANUAL PROCEDURE:
{manual_procedure}

Output format:
VERDICT: [matches/discrepancy found]

Then provide a numbered list of specific items checked:
1. [Item]: [match/mismatch] - [detail]
2. [Item]: [match/mismatch] - [detail]
etc.

Be thorough and specific in your comparison."""

        generated_text = await generate(comparison_prompt, model=model, timeout=30.0)

        return {"success": True, "data": {"comparison": generated_text}}

    except Exception as e:
        logger.error(f"execute_compare_tool error: {e}")
        return {"success": False, "data": {}, "error": str(e)}


async def execute_tool(tool_name: str, params: dict, **kwargs) -> dict:
    """
    Dispatcher function to route to the appropriate tool executor.

    Args:
        tool_name: Name of the tool to execute
        params: Parameters for the tool
        **kwargs: Additional arguments (manual_id_filter, model, history, session_summary)

    Returns:
        Dict with tool execution result
    """
    if tool_name == "work_orders":
        return await execute_work_orders_tool(params)
    elif tool_name == "manuals":
        return await execute_manuals_tool(
            params,
            manual_id_filter=kwargs.get("manual_id_filter"),
            model=kwargs.get("model"),
            history=kwargs.get("history"),
            session_summary=kwargs.get("session_summary"),
            user_email=kwargs.get("user_email"),
            latency_breakdown=kwargs.get("latency_breakdown"),
        )
    elif tool_name == "compare":
        return await execute_compare_tool(params, model=kwargs.get("model"))
    else:
        return {"success": False, "error": f"Unknown tool: {tool_name}"}


async def run_agentic_loop(
    question: str,
    manual_id_filter=None,
    model=None,
    history=None,
    session_summary=None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> dict:
    """
    Core agentic loop that decides whether to call tools and executes them.

    Args:
        question: The user's question
        manual_id_filter: Optional filter for specific manual IDs
        model: Optional model override
        history: Optional conversation history for context
        session_summary: Optional session summary
        user_email: Optional user email for audit logging
        latency_breakdown: Optional dict to record stage timings

    Returns:
        Dict with answer, tools_used, agentic flag, and other metadata
    """
    start_time = time.time()

    # Fast path: if the question doesn't reference work orders or comparisons,
    # skip the agentic loop entirely and use the existing RAG pipeline.
    if not _needs_tools(question):
        logger.info("No tool keywords detected, using direct RAG pipeline")
        result = await manual_rag_ask(
            question=question,
            manual_id_filter=manual_id_filter,
            model=model,
            history=history,
            session_summary=session_summary,
            user_email=user_email,
            latency_breakdown=latency_breakdown,
        )
        if latency_breakdown is not None:
            result["latency_breakdown"] = latency_breakdown
        result["agentic"] = False
        result["tools_used"] = []
        result["duration_seconds"] = time.time() - start_time
        return result

    tool_calls_log = []
    call_count = 0
    MAX_CALLS = 3
    TIMEOUT = 60.0

    history_context = ""
    if history:
        for turn in history:
            q = turn.get("question", "")
            a = turn.get("answer", "")
            history_context += f"User: {q}\nAssistant: {a}\n"

    session_context = (
        f"\nSession Summary: {session_summary}\n" if session_summary else ""
    )

    prompt = f"""System: {TOOL_MANIFEST}

IMPORTANT: The user's question references work orders or asks to compare data against procedures.
You MUST use the appropriate tool(s) to answer. Do NOT answer from memory — call a tool first.
If the question mentions a work order number, status, or technician, call the work_orders tool.
If the question asks about a procedure, call the manuals tool.
If the question asks to compare or check compliance, call work_orders, then manuals, then compare.

Output your tool call NOW in this exact format:
TOOL_CALL: <tool_name>
PARAMS: <json>

{history_context}{session_context}
User: {question}"""

    last_tool_result = None
    manuals_tool_result = None

    while call_count < MAX_CALLS:
        if time.time() - start_time > TIMEOUT:
            logger.warning("Agentic loop timeout reached, generating final answer")
            prompt += "\n\nTIME LIMIT REACHED. Generate your final answer now using only the information gathered from tool calls above."
            try:
                final_answer = await generate(prompt, model=model, timeout=10.0)
            except Exception as e:
                logger.error(f"Final answer generation failed: {e}")
                final_answer = (
                    "I was unable to complete the analysis due to time constraints."
                )
            break

        try:
            response = await generate(prompt, model=model, timeout=45.0)
        except Exception as e:
            logger.warning(
                f"Agentic generation failed, falling back to direct manual_rag_service: {e}"
            )
            try:
                fallback_result = await manual_rag_ask(
                    question=question,
                    manual_id_filter=manual_id_filter,
                    model=model,
                    history=history,
                    session_summary=session_summary,
                    user_email=user_email,
                    latency_breakdown=latency_breakdown,
                )
                fallback_result["agentic"] = False
                fallback_result["tools_used"] = []
                fallback_result["duration_seconds"] = time.time() - start_time
                if latency_breakdown is not None:
                    fallback_result["latency_breakdown"] = latency_breakdown
                return fallback_result
            except Exception as fallback_err:
                logger.error(f"Fallback also failed: {fallback_err}")
                return {
                    "answer": "I encountered an error processing your request. Please try again.",
                    "success": False,
                    "agentic": False,
                    "tools_used": [],
                    "grounded": False,
                    "sources": [],
                    "duration_seconds": time.time() - start_time,
                }

        tool_name, params = parse_tool_call(response)

        if tool_name is None:
            if call_count > 0:
                # Tools were already called — this response is the final answer
                logger.info(
                    f"No further tool call after {call_count} tool(s), treating response as final answer"
                )
                # Strip FINAL_ANSWER: prefix if the model used it
                final_answer = response.strip()
                if final_answer.startswith("FINAL_ANSWER:"):
                    final_answer = final_answer[len("FINAL_ANSWER:") :].strip()
                break
            else:
                # First iteration, no tools needed — fall back to existing pipeline
                logger.info(
                    "No tool call detected, falling back to direct manual_rag_service for full pipeline"
                )
                try:
                    fallback_result = await manual_rag_ask(
                        question=question,
                        manual_id_filter=manual_id_filter,
                        model=model,
                        history=history,
                        session_summary=session_summary,
                        user_email=user_email,
                        latency_breakdown=latency_breakdown,
                    )
                    fallback_result["agentic"] = False
                    fallback_result["tools_used"] = []
                    fallback_result["duration_seconds"] = time.time() - start_time
                    if latency_breakdown is not None:
                        fallback_result["latency_breakdown"] = latency_breakdown
                    return fallback_result
                except Exception as fallback_err:
                    logger.error(
                        f"Fallback to manual_rag_service failed: {fallback_err}"
                    )
                    return {
                        "answer": response.strip(),
                        "success": True,
                        "agentic": False,
                        "tools_used": [],
                        "grounded": False,
                        "sources": [],
                        "duration_seconds": time.time() - start_time,
                        "model": model or get_default_model(),
                    }

        logger.info(f"Tool call: {tool_name}, params: {params}")

        result = await execute_tool(
            tool_name,
            params,
            model=model,
            manual_id_filter=manual_id_filter,
            history=history,
            session_summary=session_summary,
            user_email=user_email,
            latency_breakdown=latency_breakdown,
        )

        tool_calls_log.append(
            {
                "tool_name": tool_name,
                "success": result.get("success", False),
                "has_data": bool(result.get("data")),
            }
        )

        if tool_name == "manuals" and result.get("success"):
            manuals_tool_result = result.get("data", {})

        call_count += 1

        result_feedback = f"\nTOOL_RESULT [{tool_name}]: {json.dumps(result)}"

        if not result.get("success"):
            result_feedback += f"\nTOOL ERROR: {tool_name} failed with: {result.get('error', 'unknown error')}. Continue with other tools or answer with available information."
        elif result.get("success") and not result.get("data"):
            result_feedback += f"\nNOTE: No results found for {tool_name}. You MUST tell the user that no matching data was found. Do NOT make up data."
        elif result.get("truncated"):
            result_feedback += f"\nNOTE: Results were limited to 20. There may be more matching items. Inform the user that results were truncated."

        result_feedback += "\nBased on the tool results above, decide your next action: call another tool or provide your final answer."

        prompt += f"\n\n{response.strip()}\n{result_feedback}"

    if call_count >= MAX_CALLS:
        prompt += "\n\nYou have used all available tool calls. Generate your final answer now using the information gathered above."
        try:
            final_answer = await generate(prompt, model=model, timeout=10.0)
        except Exception as e:
            final_answer = "I was unable to complete the analysis."

    # Clean up the final answer — strip FINAL_ANSWER: prefix and any stray TOOL_CALL blocks
    final_answer = final_answer.strip()
    if final_answer.upper().startswith("FINAL_ANSWER:"):
        final_answer = final_answer[len("FINAL_ANSWER:") :].strip()
    # Remove any accidental TOOL_CALL block at the start (model confusion)
    if "TOOL_CALL:" in final_answer and "PARAMS:" in final_answer:
        # Keep only text after the last PARAMS: line
        lines = final_answer.split("\n")
        clean_lines = []
        skip = False
        for line in lines:
            if line.strip().startswith("TOOL_CALL:"):
                skip = True
                continue
            if skip and line.strip().startswith("PARAMS:"):
                skip = False
                continue
            skip = False
            clean_lines.append(line)
        final_answer = "\n".join(clean_lines).strip()

    resolved_model = model or get_default_model()

    response_dict = {
        "answer": final_answer,
        "agentic": len(tool_calls_log) > 0,
        "tools_used": tool_calls_log,
        "duration_seconds": time.time() - start_time,
        "model": resolved_model,
        "session_summary": session_summary,
    }

    if manuals_tool_result:
        response_dict["grounded"] = manuals_tool_result.get("grounded", False)
        response_dict["sources"] = manuals_tool_result.get("sources", [])
        response_dict["manuals_consulted"] = manuals_tool_result.get(
            "manuals_consulted", []
        )
        response_dict["has_conflicts"] = manuals_tool_result.get("has_conflicts", False)
    else:
        response_dict["grounded"] = False
        response_dict["sources"] = []

    # F1.4: If latency_breakdown was passed in, transfer to response
    if latency_breakdown is not None:
        response_dict["latency_breakdown"] = latency_breakdown

    return response_dict
