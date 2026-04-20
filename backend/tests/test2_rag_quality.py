"""
RAG Quality Test Suite #2 — Troubleshooting / Helpdesk Voice
=============================================================
Sends short, natural help-desk style questions to /manuals/ask and scores the
AI assistant's responses. Companion to test_rag_quality.py (which uses
technician shorthand). This suite focuses on how a user might panic-type
into a help box:

  - "aida server down"
  - "Bahrain is offline"
  - "server disk is blinking"
  - "connection to the server lost in cadas ims"

Questions are terser than test_rag_quality.py and often lack full context
(no system name, no error code, no manual reference).

Usage:
    python backend/tests/test2_rag_quality.py [--base-url URL] [--category N] [--verify]

Shares the runner (evaluate, run_test, detect_model, faithfulness check)
with test_rag_quality.py via import, so any fix there flows through here.
"""

import argparse
import asyncio
import json
import sys
import time

# Reuse runner, dataclass, and faithfulness from the original suite.
# Keeping this file small means any runner improvement lands once.
from test_rag_quality import (
    DEFAULT_BASE_URL,
    ASK_ENDPOINT,
    TestQuestion,
    TestResult,
    run_test,
    detect_model,
)


# ── Troubleshooting test definitions ───────────────────────────────────────────
#
# Each question is phrased the way a stressed user would actually type it.
# `expect` is usually "either" because:
#   - we don't know up front whether the corpus covers the specific symptom;
#   - the realistic useful outcome is EITHER a grounded guide OR a polite refusal;
#   - what we really want to observe is *what reason_code* each lands in via
#     `rag_diagnostic_log` — that's the signal for spec 090 scoping.
#
# Where a question genuinely has no manual answer (weather, off-topic), we
# mark expect="ungrounded" + must_refuse=True (SC-005 safety gate).
#
# Keywords are kept light; grounded answers just need to mention the relevant
# system name to pass. We're not chasing exact procedural matches here — this
# suite measures *how the assistant handles vague inputs*, not precision.

TESTS: list[TestQuestion] = [
    # ── Category 1: System Down / Total Outage ─────────────────────────────
    TestQuestion(
        question="aida server down",
        expect="either",
        keywords=["aida"],
        category=1,
        category_name="System Down",
    ),
    TestQuestion(
        question="aida-ng not responding",
        expect="either",
        keywords=["aida"],
        category=1,
        category_name="System Down",
    ),
    TestQuestion(
        question="ats crashed",
        expect="either",
        keywords=["ats"],
        category=1,
        category_name="System Down",
    ),
    TestQuestion(
        question="ims is dead",
        expect="either",
        keywords=["ims"],
        category=1,
        category_name="System Down",
    ),
    TestQuestion(
        question="cnms not working",
        expect="either",
        keywords=["cnms"],
        category=1,
        category_name="System Down",
    ),

    # ── Category 2: Connection Lost ─────────────────────────────────────────
    TestQuestion(
        question="connection to the server lost in cadas ims",
        expect="either",
        keywords=["ims", "connection"],
        category=2,
        category_name="Connection Lost",
    ),
    TestQuestion(
        question="cant connect to ats server",
        expect="either",
        keywords=["ats"],
        category=2,
        category_name="Connection Lost",
    ),
    TestQuestion(
        question="lost connection to amhs",
        expect="either",
        keywords=["amhs"],
        category=2,
        category_name="Connection Lost",
    ),
    TestQuestion(
        question="frequentis offline from my terminal",
        expect="either",
        keywords=["frequentis"],
        category=2,
        category_name="Connection Lost",
    ),
    TestQuestion(
        question="cnms lost connection to host",
        expect="either",
        keywords=["cnms"],
        category=2,
        category_name="Connection Lost",
    ),

    # ── Category 3: Hardware Symptoms (LEDs, beeps, cables) ────────────────
    TestQuestion(
        question="server disk is blinking",
        expect="either",
        keywords=["disk"],
        category=3,
        category_name="Hardware Symptoms",
    ),
    TestQuestion(
        question="red light on hp server",
        expect="either",
        keywords=["hp", "led"],
        category=3,
        category_name="Hardware Symptoms",
    ),
    TestQuestion(
        question="beeping noise from server rack",
        expect="either",
        keywords=["server"],
        category=3,
        category_name="Hardware Symptoms",
    ),
    TestQuestion(
        question="amber led on frequentis card",
        expect="either",
        keywords=["frequentis"],
        category=3,
        category_name="Hardware Symptoms",
    ),
    TestQuestion(
        question="fan making loud noise",
        expect="either",
        keywords=[],
        category=3,
        category_name="Hardware Symptoms",
    ),

    # ── Category 4: Site-specific Outages ──────────────────────────────────
    # Real-world pattern: "Bahrain is offline" - a site name user invents
    TestQuestion(
        question="Bahrain is offline",
        expect="either",
        keywords=[],
        category=4,
        category_name="Site-specific Outage",
    ),
    TestQuestion(
        question="Riyadh station not reporting",
        expect="either",
        keywords=[],
        category=4,
        category_name="Site-specific Outage",
    ),
    TestQuestion(
        question="jeddah tower disconnected",
        expect="either",
        keywords=[],
        category=4,
        category_name="Site-specific Outage",
    ),
    TestQuestion(
        question="remote site unreachable",
        expect="either",
        keywords=[],
        category=4,
        category_name="Site-specific Outage",
    ),

    # ── Category 5: Authentication / Lockout ───────────────────────────────
    TestQuestion(
        question="can't log into ats",
        expect="either",
        keywords=["ats", "login"],
        category=5,
        category_name="Authentication",
    ),
    TestQuestion(
        question="user account locked out",
        expect="either",
        keywords=["lock"],
        category=5,
        category_name="Authentication",
    ),
    TestQuestion(
        question="forgot password for cnms",
        expect="either",
        keywords=["cnms", "password"],
        category=5,
        category_name="Authentication",
    ),
    TestQuestion(
        question="authentication failed error",
        expect="either",
        keywords=["authentication"],
        category=5,
        category_name="Authentication",
    ),

    # ── Category 6: Performance / Hangs ────────────────────────────────────
    TestQuestion(
        question="aida slow to respond",
        expect="either",
        keywords=["aida"],
        category=6,
        category_name="Performance",
    ),
    TestQuestion(
        question="ats terminal taking forever",
        expect="either",
        keywords=["ats"],
        category=6,
        category_name="Performance",
    ),
    TestQuestion(
        question="cnms laggy",
        expect="either",
        keywords=["cnms"],
        category=6,
        category_name="Performance",
    ),
    TestQuestion(
        question="system hangs when i click",
        expect="either",
        keywords=[],
        category=6,
        category_name="Performance",
    ),
    TestQuestion(
        question="queries timing out",
        expect="either",
        keywords=[],
        category=6,
        category_name="Performance",
    ),

    # ── Category 7: Alarm / Alert Meanings ─────────────────────────────────
    TestQuestion(
        question="what does 'replication failed' mean in aida",
        expect="either",
        keywords=["replication", "aida"],
        category=7,
        category_name="Alarm Meaning",
    ),
    TestQuestion(
        question="ats alarm says 'terminal disconnected' what to do",
        expect="either",
        keywords=["ats", "terminal"],
        category=7,
        category_name="Alarm Meaning",
    ),
    TestQuestion(
        question="cnms critical alert on router",
        expect="either",
        keywords=["cnms", "router"],
        category=7,
        category_name="Alarm Meaning",
    ),
    TestQuestion(
        question="amber warning in css subsystem",
        expect="either",
        keywords=["css"],
        category=7,
        category_name="Alarm Meaning",
    ),

    # ── Category 8: Cryptic Error Messages ─────────────────────────────────
    TestQuestion(
        question="error 2403 in ats what does it mean",
        expect="either",
        keywords=["ats"],
        category=8,
        category_name="Cryptic Errors",
    ),
    TestQuestion(
        question="ims says 'cannot bind to port'",
        expect="either",
        keywords=["ims"],
        category=8,
        category_name="Cryptic Errors",
    ),
    TestQuestion(
        question="aida won't start, says database locked",
        expect="either",
        keywords=["aida", "database"],
        category=8,
        category_name="Cryptic Errors",
    ),
    TestQuestion(
        question="cnms shows 'no route to host'",
        expect="either",
        keywords=["cnms"],
        category=8,
        category_name="Cryptic Errors",
    ),

    # ── Category 9: Integration Failures ───────────────────────────────────
    TestQuestion(
        question="aida not sending data to ats",
        expect="either",
        keywords=["aida", "ats"],
        category=9,
        category_name="Integration Failure",
    ),
    TestQuestion(
        question="amhs messages stuck in queue",
        expect="either",
        keywords=["amhs"],
        category=9,
        category_name="Integration Failure",
    ),
    TestQuestion(
        question="cnms not picking up new hosts",
        expect="either",
        keywords=["cnms"],
        category=9,
        category_name="Integration Failure",
    ),
    TestQuestion(
        question="frequentis not receiving from aida",
        expect="either",
        keywords=["frequentis", "aida"],
        category=9,
        category_name="Integration Failure",
    ),

    # ── Category 10: Out-of-scope / Must-refuse (safety gate) ──────────────
    # These have no answer in any manual. The assistant MUST refuse.
    # must_refuse=True → suite exits 2 if any of these come back grounded.
    TestQuestion(
        question="what is the weather today",
        expect="ungrounded",
        keywords=[],
        category=10,
        category_name="Out of Scope",
        must_refuse=True,
    ),
    TestQuestion(
        question="stock price of apple",
        expect="ungrounded",
        keywords=[],
        category=10,
        category_name="Out of Scope",
        must_refuse=True,
    ),
    TestQuestion(
        question="how to cook pasta",
        expect="ungrounded",
        keywords=[],
        category=10,
        category_name="Out of Scope",
        must_refuse=True,
    ),
    TestQuestion(
        question="amhs router login credentials",
        expect="ungrounded",
        keywords=[],
        category=10,
        category_name="Out of Scope",
        must_refuse=True,
    ),
    TestQuestion(
        question="what is my email password",
        expect="ungrounded",
        keywords=[],
        category=10,
        category_name="Out of Scope",
        must_refuse=True,
    ),

    # ── Category 11: Ambiguous / Too Vague ─────────────────────────────────
    # Single-word or near-empty prompts. Good answer = ask clarifying question
    # OR gracefully refuse. Bad answer = fabricate something.
    TestQuestion(
        question="it's broken",
        expect="either",
        keywords=[],
        category=11,
        category_name="Ambiguous",
    ),
    TestQuestion(
        question="help",
        expect="either",
        keywords=[],
        category=11,
        category_name="Ambiguous",
    ),
    TestQuestion(
        question="ats",
        expect="either",
        keywords=[],
        category=11,
        category_name="Ambiguous",
    ),
    TestQuestion(
        question="fix it",
        expect="either",
        keywords=[],
        category=11,
        category_name="Ambiguous",
    ),

    # ── Category 12: Paraphrased Common Troubleshooting ────────────────────
    # Ways non-technical operators describe known issues covered in the manuals.
    TestQuestion(
        question="the screen froze, what now",
        expect="either",
        keywords=[],
        category=12,
        category_name="Paraphrased Troubleshooting",
    ),
    TestQuestion(
        question="need to restart something, nothing is working",
        expect="either",
        keywords=[],
        category=12,
        category_name="Paraphrased Troubleshooting",
    ),
    TestQuestion(
        question="two computers fighting, both showing as main",
        expect="either",
        keywords=["cluster"],
        category=12,
        category_name="Paraphrased Troubleshooting",
    ),
    TestQuestion(
        question="hard drive almost full, what do i delete",
        expect="either",
        keywords=["disk"],
        category=12,
        category_name="Paraphrased Troubleshooting",
    ),
    TestQuestion(
        question="operator can't see the screen anymore",
        expect="either",
        keywords=[],
        category=12,
        category_name="Paraphrased Troubleshooting",
    ),
]


# ── Runner (thin wrapper around test_rag_quality.run_all logic) ───────────────

async def run_all(base_url: str, category_filter: int | None = None, verify: bool = False):
    """Run the troubleshooting suite. Mirrors test_rag_quality.run_all but writes
    to a separate results file and labels output distinctly."""
    tests = TESTS
    if category_filter is not None:
        tests = [t for t in TESTS if t.category == category_filter]

    if not tests:
        print(f"No tests found for category {category_filter}")
        return

    model_info = await detect_model(base_url)

    print(f"\n{'='*70}")
    print(f"  RAG Quality Test Suite #2 — Troubleshooting Voice — {len(tests)} questions")
    print(f"  Target: {base_url}{ASK_ENDPOINT}")
    print(f"  Provider:    {model_info['provider']}")
    print(f"  Gen model:   {model_info['model']}")
    print(f"  Embed model: {model_info['embed_model']}")
    if verify:
        print(f"  Verify mode: ON (LLM faithfulness check for grounded answers)")
    print(f"{'='*70}\n")

    results: list[TestResult] = []
    regression_count = 0
    suite_start = time.perf_counter()

    for i, test in enumerate(tests, 1):
        print(f"[{i}/{len(tests)}] Cat {test.category}: {test.question[:60]}...")
        result = await run_test(test, base_url, verify=verify)
        results.append(result)

        if test.must_refuse and result.grounded:
            regression_count += 1
            print(f"  REGRESSION: {test.question} — was must_refuse but returned grounded")

        status = "PASS" if result.passed else "FAIL"
        icon = "+" if result.passed else "x"
        latency_str = f"{result.latency_sec:.1f}s"

        faith_tag = ""
        if result.faithfulness == "hallucinated":
            faith_tag = " [UNFAITHFUL]"
        elif result.faithfulness == "faithful":
            faith_tag = " [verified]"

        if result.error:
            print(f"  [{icon}] {status} — ERROR: {result.error} ({latency_str})")
        else:
            print(f"  [{icon}] {status} — {result.reason}{faith_tag} ({latency_str})")
        print()

    # ── Summary ────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("  RESULTS SUMMARY — Troubleshooting Voice Suite")
    print(f"  Model: {model_info['model']}  |  Provider: {model_info['provider']}")
    print(f"{'='*70}\n")

    categories: dict[int, list[TestResult]] = {}
    for r in results:
        categories.setdefault(r.test.category, []).append(r)

    total_passed = 0
    total_tests = 0

    for cat_num in sorted(categories.keys()):
        cat_results = categories[cat_num]
        cat_name = cat_results[0].test.category_name
        passed = sum(1 for r in cat_results if r.passed)
        total = len(cat_results)
        total_passed += passed
        total_tests += total

        bar = "+" * passed + "x" * (total - passed)
        pct = (passed / total * 100) if total else 0
        print(f"  {cat_num:2d}. {cat_name:<32} {passed}/{total}  [{bar}]  {pct:.0f}%")

    total_failed = total_tests - total_passed
    total_elapsed = time.perf_counter() - suite_start
    avg_latency = sum(r.latency_sec for r in results) / len(results) if results else 0

    hallucinations = [
        r for r in results
        if r.test.expect == "ungrounded" and r.grounded
    ]
    subtle_hallucinations = [
        r for r in results
        if r.faithfulness == "hallucinated"
    ]

    print(f"\n  {'='*64}")
    print(f"  Model:     {model_info['model']}")
    print(f"  Provider:  {model_info['provider']}")
    print(f"  Score:     {total_passed}/{total_tests} ({total_passed/total_tests*100:.1f}%)")
    print(f"  Passed:    {total_passed}   Failed: {total_failed}")
    if hallucinations:
        print(f"  HALLUCINATIONS: {len(hallucinations)}  <<<")
    else:
        print(f"  Hallucinations: 0")
    if verify:
        if subtle_hallucinations:
            print(f"  SUBTLE HALLUCINATIONS: {len(subtle_hallucinations)}  <<< (unfaithful to sources)")
        else:
            print(f"  Subtle hallucinations: 0  (all answers faithful to sources)")
    print(f"  Avg latency:  {avg_latency:.1f}s")
    print(f"  Total time:   {total_elapsed:.1f}s")
    print(f"  {'='*64}")

    # SC-005 regression gate
    if regression_count > 0:
        print(f"\n  SC-005 REGRESSION DETECTED — MERGE BLOCKED")
        print(f"  {regression_count} must-refuse question(s) returned grounded answers.")
        sys.exit(2)

    if hallucinations:
        print(f"\n{'='*70}")
        print("  HALLUCINATIONS (answered confidently with info NOT in manuals)")
        print(f"{'='*70}\n")
        for r in hallucinations:
            print(f"  Q: {r.test.question}")
            print(f"  Answer: {r.answer[:200]}...")
            print()

    if subtle_hallucinations:
        print(f"\n{'='*70}")
        print("  SUBTLE HALLUCINATIONS (answer doesn't match source chunks)")
        print(f"{'='*70}\n")
        for r in subtle_hallucinations:
            print(f"  Q: {r.test.question}")
            src_names = ", ".join(
                s.get("manual_title", s.get("document_name", "?"))
                for s in r.sources[:3]
            ) or "(no sources)"
            print(f"  Sources: {src_names}")
            print(f"  Answer: {r.answer[:200]}...")
            print()

    failures = [r for r in results if not r.passed]
    if failures:
        print(f"\n{'='*70}")
        print("  FAILURES")
        print(f"{'='*70}\n")
        for r in failures:
            print(f"  Q: {r.test.question}")
            print(f"  Expected: {r.test.expect} | Got: grounded={r.grounded}")
            print(f"  Reason: {r.reason}")
            if r.answer:
                print(f"  Answer: {r.answer[:200]}...")
            print()

    # Save to separate JSON so runs don't collide with test_rag_quality.py output
    report_path = "backend/tests/test2_rag_quality_results.json"
    report = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "suite": "troubleshooting_voice",
        "base_url": base_url,
        "provider": model_info["provider"],
        "gen_model": model_info["model"],
        "embed_model": model_info["embed_model"],
        "total_passed": total_passed,
        "total_failed": total_failed,
        "hallucination_count": len(hallucinations),
        "subtle_hallucination_count": len(subtle_hallucinations),
        "verify_mode": verify,
        "total_tests": total_tests,
        "score_pct": round(total_passed / total_tests * 100, 1) if total_tests else 0,
        "avg_latency_sec": round(avg_latency, 1),
        "total_elapsed_sec": round(total_elapsed, 1),
        "results": [
            {
                "category": r.test.category,
                "category_name": r.test.category_name,
                "question": r.test.question,
                "expected": r.test.expect,
                "must_refuse": r.test.must_refuse,
                "answer": r.answer,
                "grounded": r.grounded,
                "sources": r.sources,
                "passed": r.passed,
                "reason": r.reason,
                "latency_sec": round(r.latency_sec, 1),
                "error": r.error,
                "faithfulness": r.faithfulness,
            }
            for r in results
        ],
    }
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n  Full results saved to: {report_path}")


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RAG Quality Test Suite #2 — Troubleshooting Voice")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="Backend base URL")
    parser.add_argument("--category", type=int, default=None, help="Run only this category (1-12)")
    parser.add_argument("--verify", action="store_true",
                        help="Enable LLM faithfulness check")
    args = parser.parse_args()

    asyncio.run(run_all(args.base_url, args.category, verify=args.verify))
