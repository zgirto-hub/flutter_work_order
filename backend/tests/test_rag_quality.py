"""
RAG Quality Test Suite
======================
Sends test questions to /manuals/ask and scores the AI assistant's responses.

Usage:
    python backend/tests/test_rag_quality.py [--base-url URL] [--category N]

Examples:
    python backend/tests/test_rag_quality.py                          # all categories
    python backend/tests/test_rag_quality.py --category 1             # direct retrieval only
    python backend/tests/test_rag_quality.py --category 6             # hallucination only
    python backend/tests/test_rag_quality.py --base-url http://localhost:8000
"""

import argparse
import asyncio
import json
import time
from dataclasses import dataclass

import httpx

# ── Configuration ──────────────────────────────────────────────────────────────

DEFAULT_BASE_URL = "https://zorin.taila92fe8.ts.net"
ASK_ENDPOINT = "/api/manuals/ask"
USER_EMAIL = "test@quality-check.local"
TIMEOUT_SECONDS = 120  # RAG pipeline can be slow


# ── Test definitions ───────────────────────────────────────────────────────────

@dataclass
class TestQuestion:
    question: str
    expect: str  # "grounded", "ungrounded", "either"
    keywords: list[str]  # expected keywords in answer (for grounded questions)
    category: int
    category_name: str


TESTS: list[TestQuestion] = [
    # ── Category 1: Direct Retrieval (Easy) ────────────────────────────────
    # Source: CADAS-ATS_Administration_V2.0 page 75
    TestQuestion(
        question="How do I reset the CADAS-ATS administrator password?",
        expect="grounded",
        keywords=["cadas_maint", "createadmin", "CSADMIN", "1q1q1q1q"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 71
    TestQuestion(
        question="Where are the CADAS-ATS log files located?",
        expect="grounded",
        keywords=["/var/log/cadas-ats", "log"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 page 37
    TestQuestion(
        question="How do I start and stop CADAS-IMS services?",
        expect="grounded",
        keywords=["cadas_ims_start", "cadas_ims_stop"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: SysEmgcyProc page 17 (drive status LEDs)
    TestQuestion(
        question="What does a flashing yellow LED mean on the RAID drive?",
        expect="grounded",
        keywords=["fail", "drive"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 69
    TestQuestion(
        question="How do I backup the CADAS-ATS database?",
        expect="grounded",
        keywords=["cadas_backup"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 65
    TestQuestion(
        question="What are the Linux commands to restart the CADAS-ATS terminal server?",
        expect="grounded",
        keywords=["cadas_service_tomcat"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 page 38
    TestQuestion(
        question="Where are CADAS-IMS database backups stored?",
        expect="grounded",
        keywords=["/var/cadas_ims/backups"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 72
    TestQuestion(
        question="What does the cadas_status command do?",
        expect="grounded",
        keywords=["status", "Terminal Server", "Message Handler"],
        category=1,
        category_name="Direct Retrieval",
    ),

    # ── Category 2: Procedural / Multi-Step (Medium) ───────────────────────
    # Source: CADAS-ATS_Administration_V2.0 page 76
    TestQuestion(
        question="What are all the steps to recover a corrupted config.txt file?",
        expect="grounded",
        keywords=["config.txt", "/etc/cadas"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 page 21
    TestQuestion(
        question="How do I import AIXM static data into CADAS-IMS and verify the import was successful?",
        expect="grounded",
        keywords=["AIXM", "import"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 68
    TestQuestion(
        question="Explain the process to customize the CADAS-ATS homepage.",
        expect="grounded",
        keywords=["cadas_web_download", "cadas_web_upload"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS_Administration_V2.0 pages 31-34
    TestQuestion(
        question="How do I configure AMHS mailbox security settings?",
        expect="grounded",
        keywords=["AMHS", "security", "certificate"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: SysEmgcyProc pages 36-37
    TestQuestion(
        question="What are the steps to reinstall a Frequentis server from a Kickstart CD?",
        expect="grounded",
        keywords=["Kickstart", "network", "install"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS_Administration_V2.0 pages 78-81
    TestQuestion(
        question="Walk me through the full procedure to resolve a CADAS-ATS split-brain situation.",
        expect="grounded",
        keywords=["victim", "database", "synchroni"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS_MessageRetrieval_V1.0 pages 3-6
    TestQuestion(
        question="How do I create a message retrieval filter in CADAS-ATS with multiple conditions?",
        expect="grounded",
        keywords=["filter", "wildcard"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),

    # ── Category 3: Cross-Manual Synthesis (Hard) ──────────────────────────
    # Needs: CADAS-ATS Admin + CADAS-IMS Admin
    TestQuestion(
        question="What is the difference between CADAS-ATS and CADAS-IMS in terms of administration and troubleshooting?",
        expect="grounded",
        keywords=["CADAS-ATS", "CADAS-IMS"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CADAS-IMS Admin + SysEmgcyProc
    TestQuestion(
        question="If the CADAS-IMS message queue is stuck, what diagnostic steps from the System Diagnosis manual should I use, and what CADAS-IMS specific steps apply?",
        expect="grounded",
        keywords=["queue", "restart"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CADAS-ATS Admin (page 71) + SysEmgcyProc (pages 8-12)
    TestQuestion(
        question="Compare how log file analysis works in CADAS-ATS vs the System Diagnosis manual — are there overlapping tools?",
        expect="grounded",
        keywords=["log"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CADAS-ATS Admin (page 30) + CADAS-ATS Admin (pages 28-35)
    TestQuestion(
        question="How does the MTS Client configuration relate to AMHS mailbox setup in CADAS-ATS?",
        expect="grounded",
        keywords=["MTS", "AMHS", "mailbox"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: SysEmgcyProc (pages 33-34) + CADAS-ATS Admin (page 65)
    TestQuestion(
        question="What are all the ways to restart CADAS-ATS services across both the admin manual and the troubleshooting guide?",
        expect="grounded",
        keywords=["cadas_service", "start", "stop"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),

    # ── Category 4: Reasoning / Inference (Hard) ───────────────────────────
    # Source: CADAS-ATS_Administration_V2.0 pages 78-81
    TestQuestion(
        question="A CADAS-ATS dual-node cluster has entered a split-brain situation. What should I do first?",
        expect="grounded",
        keywords=["split-brain", "victim", "database"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: SysEmgcyProc pages 25, 31, 33-34
    TestQuestion(
        question="The message handler service is not responding. Based on the troubleshooting guides, what are the possible causes and how should I diagnose them?",
        expect="grounded",
        keywords=["restart", "log"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 page 21
    TestQuestion(
        question="If I see ERROR severity in the CADAS-IMS AIXM import log, what should I check?",
        expect="grounded",
        keywords=["ERROR", "FATAL"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: SysEmgcyProc pages 17, 28
    TestQuestion(
        question="A hard drive failure LED is lit on the server. What does that mean and what action should I take?",
        expect="grounded",
        keywords=["replace", "drive"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 77
    TestQuestion(
        question="Users cannot access the CADAS-ATS homepage or login. What could be wrong?",
        expect="grounded",
        keywords=["terminal", "port"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: SysEmgcyProc page 39
    TestQuestion(
        question="I suspect a network failure is affecting the system. What steps should I take to diagnose it?",
        expect="grounded",
        keywords=["ping", "cabling"],
        category=4,
        category_name="Reasoning / Inference",
    ),

    # ── Category 5: CADAS-ATS Advanced Features ───────────────────────────
    # Source: CADAS-ATS_Administration_V2.0 page 63
    TestQuestion(
        question="How does CADAS-ATS integrate with Keycloak for user authentication?",
        expect="grounded",
        keywords=["Keycloak", "user"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 22
    TestQuestion(
        question="How do restricted areas work in CADAS-ATS?",
        expect="grounded",
        keywords=["restricted", "area", "polygon"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS_Administration_V2.0 page 20
    TestQuestion(
        question="What are scheduled RPLs in CADAS-ATS and how do I configure them?",
        expect="grounded",
        keywords=["RPL", "flight plan", "schedule"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS_MessageRetrieval_V1.0 pages 9-13
    TestQuestion(
        question="What is the difference between a New Retrieval and a New Expert Retrieval in CADAS-ATS?",
        expect="grounded",
        keywords=["retrieval", "filter"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),

    # ── Category 6: Hallucination Resistance (Trick Questions) ─────────────
    TestQuestion(
        question="How do I configure CADAS-ATS for SITA network connectivity?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="What is the default oper password for CADAS-IMS?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="What is the maximum number of users CADAS-ATS supports?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="How do I configure CADAS-ATS to send emails?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="What is the CADAS-IMS API endpoint for creating NOTAMs programmatically?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),

    # ── Category 7: CADAS-IMS Specific ─────────────────────────────────────
    # Source: CADAS-IMS_AdminTraining_V1.2 pages 3-4
    TestQuestion(
        question="What are the main functions of CADAS-IMS?",
        expect="grounded",
        keywords=["NOTAM", "MET", "Briefing"],
        category=7,
        category_name="CADAS-IMS Specific",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 pages 12-13
    TestQuestion(
        question="How does CADAS-IMS use Keycloak for user and role management?",
        expect="grounded",
        keywords=["Keycloak", "role"],
        category=7,
        category_name="CADAS-IMS Specific",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 pages 17-18
    TestQuestion(
        question="How do I configure alarms in CADAS-IMS?",
        expect="grounded",
        keywords=["alarm", "event"],
        category=7,
        category_name="CADAS-IMS Specific",
    ),
    # Source: CADAS-IMS_AdminTraining_V1.2 page 29
    TestQuestion(
        question="How do message filters work in CADAS-IMS?",
        expect="grounded",
        keywords=["filter", "message"],
        category=7,
        category_name="CADAS-IMS Specific",
    ),

    # ── Category 8: Ambiguous / Vague ──────────────────────────────────────
    TestQuestion(
        question="How do I fix the system?",
        expect="either",
        keywords=[],
        category=8,
        category_name="Ambiguous / Vague",
    ),
    TestQuestion(
        question="What's the password?",
        expect="either",
        keywords=[],
        category=8,
        category_name="Ambiguous / Vague",
    ),
    TestQuestion(
        question="How do I restart the server?",
        expect="either",
        keywords=[],
        category=8,
        category_name="Ambiguous / Vague",
    ),
]


# ── Runner ─────────────────────────────────────────────────────────────────────

@dataclass
class TestResult:
    test: TestQuestion
    answer: str
    grounded: bool
    sources: list
    latency_sec: float
    error: str | None
    passed: bool
    reason: str


def evaluate(test: TestQuestion, answer: str, grounded: bool) -> tuple[bool, str]:
    """Evaluate whether the response meets expectations."""
    answer_lower = answer.lower()

    if test.expect == "grounded":
        if not grounded:
            return False, "Expected grounded answer, got ungrounded"
        # Check for keywords
        found = [kw for kw in test.keywords if kw.lower() in answer_lower]
        missing = [kw for kw in test.keywords if kw.lower() not in answer_lower]
        if not found and test.keywords:
            return False, f"No keywords found. Missing: {missing}"
        if missing:
            return True, f"Partial — missing keywords: {missing}"
        return True, "All keywords found"

    elif test.expect == "ungrounded":
        if grounded:
            # Check if it hallucinated — this is the worst outcome
            return False, "HALLUCINATED — gave grounded answer for info not in manuals"
        return True, "Correctly refused (not in manuals)"

    else:  # "either"
        return True, f"Ambiguous — grounded={grounded}"


async def run_test(test: TestQuestion, base_url: str) -> TestResult:
    """Run a single test question with its own client (avoids connection reuse issues)."""
    payload = {
        "question": test.question,
        "user_email": USER_EMAIL,
        "history": [],
    }

    start = time.perf_counter()
    try:
        timeout = httpx.Timeout(TIMEOUT_SECONDS, connect=30.0)
        async with httpx.AsyncClient(verify=False, timeout=timeout) as client:
            resp = await client.post(
                f"{base_url}{ASK_ENDPOINT}",
                json=payload,
            )
        latency = time.perf_counter() - start

        if resp.status_code != 200:
            return TestResult(
                test=test, answer="", grounded=False, sources=[],
                latency_sec=latency, error=f"HTTP {resp.status_code}: {resp.text[:200]}",
                passed=False, reason=f"HTTP error {resp.status_code}",
            )

        data = resp.json()
        answer = data.get("answer", "")
        grounded = data.get("grounded", False)
        sources = data.get("sources", [])

        passed, reason = evaluate(test, answer, grounded)

        return TestResult(
            test=test, answer=answer, grounded=grounded, sources=sources,
            latency_sec=latency, error=None, passed=passed, reason=reason,
        )

    except BaseException as e:
        latency = time.perf_counter() - start
        return TestResult(
            test=test, answer="", grounded=False, sources=[],
            latency_sec=latency, error=type(e).__name__ + ": " + str(e),
            passed=False, reason=f"Connection error: {type(e).__name__}",
        )


async def run_all(base_url: str, category_filter: int | None = None):
    """Run all tests sequentially (to avoid overloading Ollama)."""
    tests = TESTS
    if category_filter is not None:
        tests = [t for t in TESTS if t.category == category_filter]

    if not tests:
        print(f"No tests found for category {category_filter}")
        return

    print(f"\n{'='*70}")
    print(f"  RAG Quality Test Suite — {len(tests)} questions")
    print(f"  Target: {base_url}{ASK_ENDPOINT}")
    print(f"{'='*70}\n")

    results: list[TestResult] = []

    for i, test in enumerate(tests, 1):
        print(f"[{i}/{len(tests)}] Cat {test.category}: {test.question[:60]}...")
        result = await run_test(test, base_url)
        results.append(result)

        status = "PASS" if result.passed else "FAIL"
        icon = "+" if result.passed else "x"
        latency_str = f"{result.latency_sec:.1f}s"

        if result.error:
            print(f"  [{icon}] {status} — ERROR: {result.error} ({latency_str})")
        else:
            print(f"  [{icon}] {status} — {result.reason} ({latency_str})")
        print()

    # ── Summary ────────────────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("  RESULTS SUMMARY")
    print(f"{'='*70}\n")

    # Group by category
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
        print(f"  {cat_num}. {cat_name:<30} {passed}/{total}  [{bar}]  {pct:.0f}%")

    print(f"\n  {'OVERALL':<33} {total_passed}/{total_tests}  {total_passed/total_tests*100:.0f}%")

    avg_latency = sum(r.latency_sec for r in results) / len(results) if results else 0
    print(f"  Average latency: {avg_latency:.1f}s")

    # ── Failures detail ────────────────────────────────────────────────────
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

    # ── Save full results to JSON ──────────────────────────────────────────
    report_path = "backend/tests/rag_quality_results.json"
    report = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "base_url": base_url,
        "total_passed": total_passed,
        "total_tests": total_tests,
        "score_pct": round(total_passed / total_tests * 100, 1) if total_tests else 0,
        "avg_latency_sec": round(avg_latency, 1),
        "results": [
            {
                "category": r.test.category,
                "category_name": r.test.category_name,
                "question": r.test.question,
                "expected": r.test.expect,
                "answer": r.answer,
                "grounded": r.grounded,
                "sources": r.sources,
                "passed": r.passed,
                "reason": r.reason,
                "latency_sec": round(r.latency_sec, 1),
                "error": r.error,
            }
            for r in results
        ],
    }
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n  Full results saved to: {report_path}")


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RAG Quality Test Suite")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="Backend base URL")
    parser.add_argument("--category", type=int, default=None, help="Run only this category (1-8)")
    args = parser.parse_args()

    asyncio.run(run_all(args.base_url, args.category))
