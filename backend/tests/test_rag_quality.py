"""
RAG Quality Test Suite
======================
Sends test questions to /manuals/ask and scores the AI assistant's responses.

Usage:
    python backend/tests/test_rag_quality.py [--base-url URL] [--category N] [--verify]

Examples:
    python backend/tests/test_rag_quality.py                          # all categories
    python backend/tests/test_rag_quality.py --category 1             # direct retrieval only
    python backend/tests/test_rag_quality.py --category 6             # hallucination only
    python backend/tests/test_rag_quality.py --verify                 # + LLM faithfulness check
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
OLLAMA_URL = "http://localhost:11434"
VERIFY_MODEL = "gemma4:e2b"  # model used for faithfulness verification


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
    # Source: CADAS-ATS Admin — "CADAS-ATS Administrator Password Lost"
    TestQuestion(
        question="How do I reset the CADAS-ATS administrator password?",
        expect="grounded",
        keywords=["password", "admin"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Log Files" / "Log File Access"
    TestQuestion(
        question="Where are the CADAS-ATS log files located?",
        expect="grounded",
        keywords=["log"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS Manual — "Restart CADAS-IMS"
    TestQuestion(
        question="How do I start and stop CADAS-IMS services?",
        expect="grounded",
        keywords=["stop", "start"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Database Backup & Restoration"
    TestQuestion(
        question="How do I backup the CADAS-ATS database?",
        expect="grounded",
        keywords=["backup", "database"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Linux Commands to Restart"
    TestQuestion(
        question="What are the Linux commands to restart CADAS-ATS servers?",
        expect="grounded",
        keywords=["restart", "linux"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS Manual — "Database Backup and Restoration"
    TestQuestion(
        question="How do I backup and restore the CADAS-IMS database?",
        expect="grounded",
        keywords=["backup", "restore"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CNMS_Knowledge_Base — "Introduction to CNMS"
    TestQuestion(
        question="What is CNMS and what does it monitor?",
        expect="grounded",
        keywords=["CNMS", "monitor", "Nagios"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CNMS_Knowledge_Base — "Host States"
    TestQuestion(
        question="What are the possible host states in CNMS?",
        expect="grounded",
        keywords=["UP", "DOWN", "UNREACHABLE"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: frequentis_system_diagnosis — "Log File Paths"
    TestQuestion(
        question="What are the primary log file paths for CCMS?",
        expect="grounded",
        keywords=["log", "/var"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Usage Health Check"
    TestQuestion(
        question="How do I check disk usage on an AIDA-NG server?",
        expect="grounded",
        keywords=["df", "/var"],
        category=1,
        category_name="Direct Retrieval",
    ),

    # ── Category 2: Procedural / Multi-Step (Medium) ───────────────────────
    # Source: CADAS-ATS Admin — "Cannot Start Terminal Server – Configuration File Changed"
    TestQuestion(
        question="What are the steps to recover when the CADAS-ATS terminal server cannot start due to a configuration file change?",
        expect="grounded",
        keywords=["config", "terminal"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-IMS Manual — "Import and Export Static Data (AIXM 4.5)"
    TestQuestion(
        question="How do I import AIXM static data into CADAS-IMS and verify the import was successful?",
        expect="grounded",
        keywords=["AIXM", "import"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "AMHS Mailbox Configuration" / "AMHS Security"
    TestQuestion(
        question="How do I configure AMHS mailbox security settings in CADAS-ATS?",
        expect="grounded",
        keywords=["AMHS", "security", "certificate"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "Split-brain in Dual Node Cluster"
    TestQuestion(
        question="Walk me through the full procedure to resolve a CADAS-ATS split-brain situation.",
        expect="grounded",
        keywords=["victim", "database", "synchroni"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "Web Page Tailoring"
    TestQuestion(
        question="How do I customize the CADAS-ATS web page?",
        expect="grounded",
        keywords=["web", "tailor"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: frequentis_system_diagnosis — "SNL Card Replacement"
    TestQuestion(
        question="How do I replace a defective SNL card in the Frequentis system?",
        expect="grounded",
        keywords=["SNL", "hot-swap"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: frequentis_system_diagnosis — "Hard Drive Replacement"
    TestQuestion(
        question="What is the procedure to replace a failed hard drive on the HP server?",
        expect="grounded",
        keywords=["hard drive", "hot-swap"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Relief – Delete AutoArchives"
    TestQuestion(
        question="What is the full procedure to relieve disk space on an AIDA-NG server?",
        expect="grounded",
        keywords=["AutoArchives", "du"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),

    # ── Category 3: Cross-Manual Synthesis (Hard) ──────────────────────────
    # Needs: CADAS-ATS Admin + CADAS-IMS Manual
    TestQuestion(
        question="What is the difference between CADAS-ATS and CADAS-IMS in terms of administration?",
        expect="grounded",
        keywords=["CADAS-ATS", "CADAS-IMS"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CADAS-ATS Admin + CADAS-IMS Manual — both use Keycloak
    TestQuestion(
        question="How does Keycloak integration differ between CADAS-ATS and CADAS-IMS?",
        expect="grounded",
        keywords=["Keycloak"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CNMS_Knowledge_Base + CADAS-ATS Admin — CNMS monitors CADAS-ATS
    TestQuestion(
        question="How does CNMS monitor the CADAS-ATS system, and what states does it track?",
        expect="grounded",
        keywords=["CNMS", "CADAS-ATS", "MsgHandler"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: Kcmc-mtb-servers-ip + Addresses_of_Workstations — network overview
    TestQuestion(
        question="What are the IP addresses for AIDA-NG servers at the CMC site versus the MTB site?",
        expect="grounded",
        keywords=["172.31", "CMC", "MTB"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: frequentis_system_diagnosis + CNMS_Knowledge_Base — AIDA-NG monitoring
    TestQuestion(
        question="How do you diagnose an AIDA-NG subsystem failure using both CNMS monitoring and the Frequentis troubleshooting procedures?",
        expect="grounded",
        keywords=["AIDA-NG", "CNMS"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),

    # ── Category 4: Reasoning / Inference (Hard) ───────────────────────────
    # Source: CADAS-ATS Admin — "Split-brain in Dual Node Cluster"
    TestQuestion(
        question="A CADAS-ATS dual-node cluster has entered a split-brain situation. What should I do first?",
        expect="grounded",
        keywords=["split-brain", "victim", "database"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-IMS Manual — "Import and Export Static Data"
    TestQuestion(
        question="If I see ERROR severity in the CADAS-IMS AIXM import log, what should I check?",
        expect="grounded",
        keywords=["ERROR", "import"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-ATS Admin — "Cannot Start Terminal Server – Conflict with Port"
    TestQuestion(
        question="Users cannot access the CADAS-ATS terminal server. What could be wrong?",
        expect="grounded",
        keywords=["terminal", "port"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CNMS_Knowledge_Base — "CSS Status in CNMS"
    TestQuestion(
        question="The AIDA-NG CSS is showing Warning status in CNMS. What does this mean?",
        expect="grounded",
        keywords=["CSS", "Warning", "operational"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: frequentis_system_diagnosis — "Frozen Display Recovery"
    TestQuestion(
        question="An operator workstation display has frozen. What troubleshooting steps should I follow?",
        expect="grounded",
        keywords=["freeze", "display"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Usage Thresholds"
    TestQuestion(
        question="The AIDA-NG server /var partition is at 85% usage. What action should I take?",
        expect="grounded",
        keywords=["70%", "AutoArchives"],
        category=4,
        category_name="Reasoning / Inference",
    ),

    # ── Category 5: CADAS-ATS Advanced Features ───────────────────────────
    # Source: CADAS-ATS Admin — "Configure Keycloak Connection"
    TestQuestion(
        question="How does CADAS-ATS integrate with Keycloak for user authentication?",
        expect="grounded",
        keywords=["Keycloak"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "Parameter > Scheduled RPLs"
    TestQuestion(
        question="What are scheduled RPLs in CADAS-ATS and how do I configure them?",
        expect="grounded",
        keywords=["RPL", "schedule"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "AMHS Capabilities in CADAS-ATS"
    TestQuestion(
        question="What are the AMHS capabilities in CADAS-ATS?",
        expect="grounded",
        keywords=["AMHS"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "Diagnosis > Application Status"
    TestQuestion(
        question="How do I check the application status in CADAS-ATS diagnostics?",
        expect="grounded",
        keywords=["diagnosis", "application", "status"],
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
        question="What is the maximum number of users CADAS-ATS supports?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="How do I configure CNMS to send email notifications?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="What is the CNMS REST API endpoint for querying host status programmatically?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),
    TestQuestion(
        question="How do I update the Frequentis system firmware?",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
    ),

    # ── Category 7: CNMS & Frequentis & Network ───────────────────────────
    # Source: CNMS_Knowledge_Base — "Graphical Views / Maps"
    TestQuestion(
        question="How do the graphical maps work in CNMS?",
        expect="grounded",
        keywords=["map", "Top Level"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Event Console / SNMP Traps"
    TestQuestion(
        question="What types of SNMP traps does CNMS handle?",
        expect="grounded",
        keywords=["trap", "SNMP", "Link"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Acknowledge Problem"
    TestQuestion(
        question="How do I acknowledge a problem in CNMS?",
        expect="grounded",
        keywords=["acknowledge"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Scheduled Downtime"
    TestQuestion(
        question="How do I schedule a downtime in CNMS to suppress notifications?",
        expect="grounded",
        keywords=["downtime", "notification"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "HP DL380p Gen8 LED Indicators"
    TestQuestion(
        question="What do the LED indicators on the HP DL380p Gen8 server mean?",
        expect="grounded",
        keywords=["LED", "HP"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "AIDA-NG Start/Stop Commands"
    TestQuestion(
        question="How do I start and stop AIDA-NG subsystems from the command line?",
        expect="grounded",
        keywords=["/home/oper/aida-ng", "start"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: Kcmc-mtb-servers-ip — "CMC Server IPs"
    TestQuestion(
        question="What is the IP address and hostname of the AIDA-NG server at the CMC site?",
        expect="grounded",
        keywords=["172.31.11", "as1-ops"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: Addresses_of_Workstations — "AFTN/AMHS Terminals"
    TestQuestion(
        question="What are the hostnames and IP addresses of the AFTN/AMHS terminals?",
        expect="grounded",
        keywords=["owp", "172.31.21"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: How to Remotely Access the AMHS Router — "Telnet to Router"
    TestQuestion(
        question="How do I remotely access the AMHS router?",
        expect="grounded",
        keywords=["telnet", "10.48.161.1"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "CMC-MBM LED States"
    TestQuestion(
        question="What do the CMC-MBM LED indicators mean?",
        expect="grounded",
        keywords=["LED", "CMC-MBM"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),

    # ── Category 9: CADAS-ATS Knowledge Base ────────────────────────────────
    # Source: CADAS-ATS_Knowledge_Base — "Terminal Application Types"
    TestQuestion(
        question="What terminal application types does CADAS-ATS provide?",
        expect="grounded",
        keywords=["Administration", "Center"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Client/Server Architecture"
    TestQuestion(
        question="What is the CADAS-ATS client/server architecture?",
        expect="grounded",
        keywords=["Terminal Server", "Message Handler", "cluster"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Mailboxes"
    TestQuestion(
        question="How do mailboxes work in CADAS-ATS?",
        expect="grounded",
        keywords=["mailbox", "incoming"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Alarm Configuration"
    TestQuestion(
        question="How do I configure alarm notifications in CADAS-ATS?",
        expect="grounded",
        keywords=["alarm", "User Preferences"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "AMHS User Agent"
    TestQuestion(
        question="What AMHS capabilities does CADAS-ATS provide as a User Agent?",
        expect="grounded",
        keywords=["AMHS", "AFTN"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Perspectives"
    TestQuestion(
        question="What are perspectives in CADAS-ATS and how do I switch between them?",
        expect="grounded",
        keywords=["perspective", "Ctrl"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),

    # ── Category 10: KW-DGCA System & Installation ────────────────────────
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "System Overview"
    TestQuestion(
        question="What components make up the KW-DGCA AIM-AMHS system?",
        expect="grounded",
        keywords=["AIDA-NG", "CADAS-ATS", "CNMS"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "Message Flow"
    TestQuestion(
        question="How does the message flow work in the KW-DGCA AIM-AMHS system?",
        expect="grounded",
        keywords=["AIDA-NG", "CADAS-ATS"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "Redundancy"
    TestQuestion(
        question="What are the redundancy modes for each component in the KW-DGCA system?",
        expect="grounded",
        keywords=["redundancy", "AIDA-NG"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "OPS vs CONT Systems"
    TestQuestion(
        question="What is the difference between the OPS system at KCMC and the CONT system at nATC?",
        expect="grounded",
        keywords=["OPS", "CONT"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_INDRA_AIM_AMHS_Installation — "Kickstart DVD Installation"
    TestQuestion(
        question="How do I install the CCMS platform using the Kickstart DVD?",
        expect="grounded",
        keywords=["Kickstart", "DVD"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_INDRA_AIM_AMHS_Installation — "Scientific Linux Installation"
    TestQuestion(
        question="What happens during the Scientific Linux installation from the Kickstart media?",
        expect="grounded",
        keywords=["Scientific Linux", "GRUB"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),

    # ── Category 11: MHS System Diagnosis ──────────────────────────────────
    # Source: MHS_SystemDiagnosis — "Troubleshooting Approach"
    TestQuestion(
        question="What is the first step before starting any MHS troubleshooting?",
        expect="grounded",
        keywords=["diagnosis", "subsystem"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Log File Locations"
    TestQuestion(
        question="Where are the CCMS and cluster log files located on the filesystem?",
        expect="grounded",
        keywords=["/var/log/ccms", "cluster"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "AIDA-NG Log Investigation"
    TestQuestion(
        question="How do I investigate AIDA-NG subsystem failures using log files?",
        expect="grounded",
        keywords=["aida-ng", "log"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Server Replacement"
    TestQuestion(
        question="What is the procedure to replace a defective server with a spare unit?",
        expect="grounded",
        keywords=["disconnect", "spare"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Software Reinstallation"
    TestQuestion(
        question="How do I perform a clean software reinstallation on a standby server?",
        expect="grounded",
        keywords=["reinstall", "network cable"],
        category=11,
        category_name="MHS System Diagnosis",
    ),

    # ── Category 12: Paraphrased Questions ───────────────────────────────
    # Same topics as earlier categories but worded differently by a user
    # Tests query rewrite (spec 042) and HyDE (spec 043) resilience

    # Original: "How do I reset the CADAS-ATS administrator password?"
    TestQuestion(
        question="I forgot the admin password for ATS, how can I get back in?",
        expect="grounded",
        keywords=["password"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I backup the CADAS-ATS database?"
    TestQuestion(
        question="What's the procedure to take a copy of the ATS database before maintenance?",
        expect="grounded",
        keywords=["backup", "database"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I check disk usage on an AIDA-NG server?"
    TestQuestion(
        question="The AIDA server is running slow, how do I check if the disk is full?",
        expect="grounded",
        keywords=["df", "/var"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I replace a defective SNL card in the Frequentis system?"
    TestQuestion(
        question="One of the serial network boards is broken, how do I swap it out?",
        expect="grounded",
        keywords=["SNL"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "What are the possible host states in CNMS?"
    TestQuestion(
        question="In the network monitoring system, what status can a host show?",
        expect="grounded",
        keywords=["host", "CNMS"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I remotely access the AMHS router?"
    TestQuestion(
        question="I need to get into the messaging router from my desk, how?",
        expect="grounded",
        keywords=["telnet"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "What is the IP address and hostname of the AIDA-NG server at the CMC site?"
    TestQuestion(
        question="What's the address of the AIDA machine at the operations center?",
        expect="grounded",
        keywords=["172.31"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "Walk me through the full procedure to resolve a CADAS-ATS split-brain situation."
    TestQuestion(
        question="Both ATS cluster nodes think they're the primary, what do I do?",
        expect="grounded",
        keywords=["split-brain"],
        category=12,
        category_name="Paraphrased Questions",
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
    faithfulness: str | None = None  # "faithful" / "hallucinated" / "uncertain" / None


FAITHFULNESS_PROMPT = """\
You are a fact-checker for a technical aviation maintenance AI assistant.

You will receive a QUESTION, SOURCE CHUNKS from technical manuals, and an AI-GENERATED ANSWER.

Your job: check whether the ANSWER is **consistent with** the SOURCES.

Rules:
- FAITHFUL means the answer's core claims can be traced to the sources. Minor paraphrasing, summarizing, reordering steps, or adding standard technical context (like "contact your administrator") is OK.
- HALLUCINATED means the answer contains **specific fabricated facts**: invented commands, fake file paths, wrong IP addresses, procedures that contradict the sources, or made-up numbers/thresholds.
- UNCERTAIN means the sources are too vague or incomplete to judge.

Important: Do NOT flag an answer as HALLUCINATED just because it rephrases the source or omits details. Only flag it if it **invents concrete technical details** not supported by the sources.

Respond with EXACTLY one word: FAITHFUL or HALLUCINATED or UNCERTAIN
"""


async def verify_faithfulness(
    question: str, answer: str, sources: list,
) -> str:
    """Ask the LLM to judge whether the answer faithfully matches the sources."""
    sources_text = "\n\n".join(
        f"[Source {i+1}] {s.get('content', s.get('manual_title', str(s)))}"
        for i, s in enumerate(sources[:5])
    )
    if not sources_text.strip():
        sources_text = "(no source chunks returned)"

    user_msg = (
        f"QUESTION: {question}\n\n"
        f"SOURCE CHUNKS:\n{sources_text}\n\n"
        f"AI-GENERATED ANSWER:\n{answer}"
    )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": VERIFY_MODEL,
                    "prompt": f"{FAITHFULNESS_PROMPT}\n\n{user_msg}",
                    "stream": False,
                },
            )
        if resp.status_code == 200:
            verdict = resp.json().get("response", "").strip().upper()
            if "HALLUCINATED" in verdict:
                return "hallucinated"
            if "FAITHFUL" in verdict:
                return "faithful"
            return "uncertain"
    except Exception:
        pass
    return "uncertain"


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


async def run_test(test: TestQuestion, base_url: str, verify: bool = False) -> TestResult:
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

        # Faithfulness verification for grounded answers (advisory — does not override pass/fail)
        faithfulness = None
        if verify and grounded and answer:
            faithfulness = await verify_faithfulness(test.question, answer, sources)

        return TestResult(
            test=test, answer=answer, grounded=grounded, sources=sources,
            latency_sec=latency, error=None, passed=passed, reason=reason,
            faithfulness=faithfulness,
        )

    except BaseException as e:
        latency = time.perf_counter() - start
        return TestResult(
            test=test, answer="", grounded=False, sources=[],
            latency_sec=latency, error=type(e).__name__ + ": " + str(e),
            passed=False, reason=f"Connection error: {type(e).__name__}",
        )


async def detect_model(base_url: str) -> dict:
    """Detect which LLM model and provider the backend is using."""
    info = {"provider": "unknown", "model": "unknown", "embed_model": "unknown"}

    # Try Ollama /api/tags to get loaded models
    ollama_url = base_url.rsplit(":", 1)[0] + ":11434"  # same host, Ollama port
    try:
        async with httpx.AsyncClient(verify=False, timeout=5.0) as client:
            resp = await client.get(f"{ollama_url}/api/tags")
            if resp.status_code == 200:
                models = resp.json().get("models", [])
                gen_models = [m["name"] for m in models if "embed" not in m["name"].lower()]
                embed_models = [m["name"] for m in models if "embed" in m["name"].lower()]
                if gen_models:
                    info["model"] = gen_models[0]
                    info["provider"] = "Ollama (local)"
                if embed_models:
                    info["embed_model"] = embed_models[0]
    except Exception:
        # Ollama not reachable on default port — try localhost
        try:
            async with httpx.AsyncClient(verify=False, timeout=5.0) as client:
                resp = await client.get("http://localhost:11434/api/tags")
                if resp.status_code == 200:
                    models = resp.json().get("models", [])
                    gen_models = [m["name"] for m in models if "embed" not in m["name"].lower()]
                    embed_models = [m["name"] for m in models if "embed" in m["name"].lower()]
                    if gen_models:
                        info["model"] = gen_models[0]
                        info["provider"] = "Ollama (local)"
                    if embed_models:
                        info["embed_model"] = embed_models[0]
        except Exception:
            pass

    return info


async def run_all(base_url: str, category_filter: int | None = None, verify: bool = False):
    """Run all tests sequentially (to avoid overloading Ollama)."""
    tests = TESTS
    if category_filter is not None:
        tests = [t for t in TESTS if t.category == category_filter]

    if not tests:
        print(f"No tests found for category {category_filter}")
        return

    model_info = await detect_model(base_url)

    print(f"\n{'='*70}")
    print(f"  RAG Quality Test Suite — {len(tests)} questions")
    print(f"  Target: {base_url}{ASK_ENDPOINT}")
    print(f"  Provider:    {model_info['provider']}")
    print(f"  Gen model:   {model_info['model']}")
    print(f"  Embed model: {model_info['embed_model']}")
    if verify:
        print(f"  Verify mode: ON (LLM faithfulness check for grounded answers)")
    print(f"{'='*70}\n")

    results: list[TestResult] = []
    suite_start = time.perf_counter()

    for i, test in enumerate(tests, 1):
        print(f"[{i}/{len(tests)}] Cat {test.category}: {test.question[:60]}...")
        result = await run_test(test, base_url, verify=verify)
        results.append(result)

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
    print("  RESULTS SUMMARY")
    print(f"  Model: {model_info['model']}  |  Provider: {model_info['provider']}")
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

    total_failed = total_tests - total_passed
    total_elapsed = time.perf_counter() - suite_start
    avg_latency = sum(r.latency_sec for r in results) / len(results) if results else 0

    # Hallucination count: grounded answer for a question expected to be ungrounded
    hallucinations = [
        r for r in results
        if r.test.expect == "ungrounded" and r.grounded
    ]
    # Subtle hallucinations: LLM judge flagged answer as unfaithful to sources
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

    # ── Hallucinations detail ─────────────────────────────────────────────
    if hallucinations:
        print(f"\n{'='*70}")
        print("  HALLUCINATIONS (answered confidently with info NOT in manuals)")
        print(f"{'='*70}\n")
        for r in hallucinations:
            print(f"  Q: {r.test.question}")
            print(f"  Answer: {r.answer[:200]}...")
            print()

    # ── Subtle hallucinations detail ──────────────────────────────────────
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
    parser = argparse.ArgumentParser(description="RAG Quality Test Suite")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="Backend base URL")
    parser.add_argument("--category", type=int, default=None, help="Run only this category (1-12)")
    parser.add_argument("--verify", action="store_true",
                        help="Enable LLM faithfulness check — detects subtle hallucinations "
                             "where the answer doesn't match the source chunks")
    args = parser.parse_args()

    asyncio.run(run_all(args.base_url, args.category, verify=args.verify))
