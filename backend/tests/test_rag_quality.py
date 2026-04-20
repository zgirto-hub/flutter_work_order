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
import sys
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
    must_refuse: bool = False


TESTS: list[TestQuestion] = [
    # ── Category 1: Direct Retrieval (Easy) ────────────────────────────────
    # Questions rewritten in realistic technician voice: short, terse, abbreviations,
    # informal tone, occasional missing punctuation — how a shift engineer actually types.
    # Source: CADAS-ATS Admin — "CADAS-ATS Administrator Password Lost"
    TestQuestion(
        question="lost ats admin pw, how to reset",
        expect="grounded",
        keywords=["password", "admin"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Log Files" / "Log File Access"
    TestQuestion(
        question="where are ats log files",
        expect="grounded",
        keywords=["log"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS Manual — "Restart CADAS-IMS"
    TestQuestion(
        question="start/stop ims services",
        expect="grounded",
        keywords=["stop", "start"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Database Backup & Restoration"
    TestQuestion(
        question="backup ats database",
        expect="grounded",
        keywords=["backup", "database"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-ATS Admin — "Linux Commands to Restart"
    TestQuestion(
        question="linux cmd to restart ats servers",
        expect="grounded",
        keywords=["restart", "linux"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CADAS-IMS Manual — "Database Backup and Restoration"
    TestQuestion(
        question="ims db backup and restore",
        expect="grounded",
        keywords=["backup", "restore"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CNMS_Knowledge_Base — "Introduction to CNMS"
    TestQuestion(
        question="what is cnms, what does it monitor",
        expect="grounded",
        keywords=["CNMS", "monitor", "Nagios"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: CNMS_Knowledge_Base — "Host States"
    TestQuestion(
        question="cnms host states?",
        expect="grounded",
        keywords=["UP", "DOWN", "UNREACHABLE"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: frequentis_system_diagnosis — "Log File Paths"
    TestQuestion(
        question="ccms log paths",
        expect="grounded",
        keywords=["log", "/var"],
        category=1,
        category_name="Direct Retrieval",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Usage Health Check"
    TestQuestion(
        question="check disk usage on aida server",
        expect="grounded",
        keywords=["df", "/var"],
        category=1,
        category_name="Direct Retrieval",
    ),

    # ── Category 2: Procedural / Multi-Step (Medium) ───────────────────────
    # Source: CADAS-ATS Admin — "Cannot Start Terminal Server – Configuration File Changed"
    TestQuestion(
        question="ats terminal server wont start after config change, recovery steps",
        expect="grounded",
        keywords=["config", "terminal"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-IMS Manual — "Import and Export Static Data (AIXM 4.5)"
    TestQuestion(
        question="import aixm data into ims and verify it worked",
        expect="grounded",
        keywords=["AIXM", "import"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "AMHS Mailbox Configuration" / "AMHS Security"
    TestQuestion(
        question="configure amhs mailbox security in ats",
        expect="grounded",
        keywords=["AMHS", "security", "certificate"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "Split-brain in Dual Node Cluster"
    TestQuestion(
        question="ats split-brain, full recovery steps",
        expect="grounded",
        keywords=["victim", "database", "synchroni"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: CADAS-ATS Admin — "Web Page Tailoring"
    TestQuestion(
        question="customize ats web page",
        expect="grounded",
        keywords=["web", "tailor"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: frequentis_system_diagnosis — "SNL Card Replacement"
    TestQuestion(
        question="replace defective snl card on frequentis",
        expect="grounded",
        keywords=["SNL", "hot-swap"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: frequentis_system_diagnosis — "Hard Drive Replacement"
    TestQuestion(
        question="replace failed hdd on hp server, procedure",
        expect="grounded",
        keywords=["hard drive", "hot-swap"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Relief – Delete AutoArchives"
    TestQuestion(
        question="aida disk full, how to free space",
        expect="grounded",
        keywords=["AutoArchives", "du"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # NEW — feature procedure: user management (likely in CADAS-ATS Admin / Keycloak)
    TestQuestion(
        question="how to add new user in aida",
        expect="grounded",
        keywords=["user"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # NEW — feature procedure: AMHS mailbox creation (CADAS-ATS Admin)
    TestQuestion(
        question="how to add new mailbox in cadas ats",
        expect="grounded",
        keywords=["mailbox"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),
    # NEW — feature procedure: host config in CNMS / Nagios
    TestQuestion(
        question="how to add new host in cnms",
        expect="grounded",
        keywords=["host"],
        category=2,
        category_name="Procedural / Multi-Step",
    ),

    # ── Category 3: Cross-Manual Synthesis (Hard) ──────────────────────────
    # Needs: CADAS-ATS Admin + CADAS-IMS Manual
    TestQuestion(
        question="ats vs ims admin, what's the difference",
        expect="grounded",
        keywords=["CADAS-ATS", "CADAS-IMS"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CADAS-ATS Admin + CADAS-IMS Manual — both use Keycloak
    TestQuestion(
        question="keycloak on ats vs ims, how does it differ",
        expect="grounded",
        keywords=["Keycloak"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: CNMS_Knowledge_Base + CADAS-ATS Admin — CNMS monitors CADAS-ATS
    TestQuestion(
        question="how does cnms monitor ats, and what states",
        expect="grounded",
        keywords=["CNMS", "CADAS-ATS", "MsgHandler"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: Kcmc-mtb-servers-ip + Addresses_of_Workstations — network overview
    TestQuestion(
        question="aida ip addresses, cmc vs mtb",
        expect="grounded",
        keywords=["172.31", "CMC", "MTB"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),
    # Needs: frequentis_system_diagnosis + CNMS_Knowledge_Base — AIDA-NG monitoring
    TestQuestion(
        question="aida subsystem failure, diagnose using cnms + frequentis docs",
        expect="grounded",
        keywords=["AIDA-NG", "CNMS"],
        category=3,
        category_name="Cross-Manual Synthesis",
    ),

    # ── Category 4: Reasoning / Inference (Hard) ───────────────────────────
    # Source: CADAS-ATS Admin — "Split-brain in Dual Node Cluster"
    TestQuestion(
        question="ats cluster went split-brain, first step",
        expect="grounded",
        keywords=["split-brain", "victim", "database"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-IMS Manual — "Import and Export Static Data"
    TestQuestion(
        question="ims aixm import log shows ERROR, what to check",
        expect="grounded",
        keywords=["ERROR", "import"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CADAS-ATS Admin — "Cannot Start Terminal Server – Conflict with Port"
    TestQuestion(
        question="users cant get into ats terminal server, whats wrong",
        expect="grounded",
        keywords=["terminal", "port"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: CNMS_Knowledge_Base — "CSS Status in CNMS"
    TestQuestion(
        question="aida css in warning on cnms, what does it mean",
        expect="grounded",
        keywords=["CSS", "Warning", "operational"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: frequentis_system_diagnosis — "Frozen Display Recovery"
    TestQuestion(
        question="operator display frozen, troubleshooting steps",
        expect="grounded",
        keywords=["freeze", "display"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # Source: AIDA-NG_Disk_Procedure — "Disk Usage Thresholds"
    TestQuestion(
        question="aida /var at 85%, what now",
        expect="grounded",
        keywords=["70%", "AutoArchives"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # NEW — "X not responding" type
    TestQuestion(
        question="ats terminal server not responding",
        expect="grounded",
        keywords=["terminal", "port"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # NEW — "X not responding" type
    TestQuestion(
        question="aida-ng not responding, what to check",
        expect="grounded",
        keywords=["aida", "log"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # NEW — "X not responding" type
    TestQuestion(
        question="amhs router not reachable",
        expect="grounded",
        keywords=["telnet", "10.48.161.1"],
        category=4,
        category_name="Reasoning / Inference",
    ),
    # NEW — "X not responding" type
    TestQuestion(
        question="cnms host showing DOWN, what now",
        expect="grounded",
        keywords=["host", "DOWN"],
        category=4,
        category_name="Reasoning / Inference",
    ),

    # ── Category 5: CADAS-ATS Advanced Features ───────────────────────────
    # Source: CADAS-ATS Admin — "Configure Keycloak Connection"
    TestQuestion(
        question="ats + keycloak auth, how does it work",
        expect="grounded",
        keywords=["Keycloak"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "Parameter > Scheduled RPLs"
    TestQuestion(
        question="scheduled rpls in ats, how to configure",
        expect="grounded",
        keywords=["RPL", "schedule"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "AMHS Capabilities in CADAS-ATS"
    TestQuestion(
        question="amhs capabilities in ats",
        expect="grounded",
        keywords=["AMHS"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),
    # Source: CADAS-ATS Admin — "Diagnosis > Application Status"
    TestQuestion(
        question="check app status in ats diagnostics",
        expect="grounded",
        keywords=["diagnosis", "application", "status"],
        category=5,
        category_name="CADAS-ATS Advanced",
    ),

    # ── Category 6: Hallucination Resistance (Trick Questions) ─────────────
    TestQuestion(
        question="configure ats for sita network",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    TestQuestion(
        question="max users ats supports",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    TestQuestion(
        question="setup cnms email alerts",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    TestQuestion(
        question="cnms rest api endpoint for host status",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    TestQuestion(
        question="frequentis firmware update steps",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    # NEW — credential request (manuals don't store live passwords)
    TestQuestion(
        question="what is username password of cadas-ats admin",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    # NEW — credential request
    TestQuestion(
        question="default login for cnms",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    # NEW — credential request
    TestQuestion(
        question="aida ng root password",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),
    # NEW — credential request
    TestQuestion(
        question="amhs router login credentials",
        expect="ungrounded",
        keywords=[],
        category=6,
        category_name="Hallucination Resistance",
        must_refuse=True,
    ),

    # ── Category 7: CNMS & Frequentis & Network ───────────────────────────
    # Source: CNMS_Knowledge_Base — "Graphical Views / Maps"
    TestQuestion(
        question="how do cnms graphical maps work",
        expect="grounded",
        keywords=["map", "Top Level"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Event Console / SNMP Traps"
    TestQuestion(
        question="what snmp traps does cnms handle",
        expect="grounded",
        keywords=["trap", "SNMP", "Link"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Acknowledge Problem"
    TestQuestion(
        question="ack a problem in cnms",
        expect="grounded",
        keywords=["acknowledge"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: CNMS_Knowledge_Base — "Scheduled Downtime"
    TestQuestion(
        question="schedule downtime in cnms to mute alerts",
        expect="grounded",
        keywords=["downtime", "notification"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "HP DL380p Gen8 LED Indicators"
    TestQuestion(
        question="hp dl380p gen8 led meanings",
        expect="grounded",
        keywords=["LED", "HP"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "AIDA-NG Start/Stop Commands"
    TestQuestion(
        question="start/stop aida subsystems from cli",
        expect="grounded",
        keywords=["/home/oper/aida-ng", "start"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: Kcmc-mtb-servers-ip — "CMC Server IPs"
    TestQuestion(
        question="aida server ip and hostname at cmc",
        expect="grounded",
        keywords=["172.31.11", "as1-ops"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: Addresses_of_Workstations — "AFTN/AMHS Terminals"
    TestQuestion(
        question="aftn/amhs terminal hostnames and ips",
        expect="grounded",
        keywords=["owp", "172.31.21"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: How to Remotely Access the AMHS Router — "Telnet to Router"
    TestQuestion(
        question="remote access amhs router",
        expect="grounded",
        keywords=["telnet", "10.48.161.1"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),
    # Source: frequentis_system_diagnosis — "CMC-MBM LED States"
    TestQuestion(
        question="cmc-mbm led meanings",
        expect="grounded",
        keywords=["LED", "CMC-MBM"],
        category=7,
        category_name="CNMS & Frequentis & Network",
    ),

    # ── Category 9: CADAS-ATS Knowledge Base ────────────────────────────────
    # Source: CADAS-ATS_Knowledge_Base — "Terminal Application Types"
    TestQuestion(
        question="ats terminal app types",
        expect="grounded",
        keywords=["Administration", "Center"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Client/Server Architecture"
    TestQuestion(
        question="ats client/server architecture",
        expect="grounded",
        keywords=["Terminal Server", "Message Handler", "cluster"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Mailboxes"
    TestQuestion(
        question="how do mailboxes work in ats",
        expect="grounded",
        keywords=["mailbox", "incoming"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Alarm Configuration"
    TestQuestion(
        question="configure alarm notifications in ats",
        expect="grounded",
        keywords=["alarm", "User Preferences"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "AMHS User Agent"
    TestQuestion(
        question="ats amhs user agent capabilities",
        expect="grounded",
        keywords=["AMHS", "AFTN"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),
    # Source: CADAS-ATS_Knowledge_Base — "Perspectives"
    TestQuestion(
        question="what are ats perspectives and how to switch",
        expect="grounded",
        keywords=["perspective", "Ctrl"],
        category=9,
        category_name="CADAS-ATS Knowledge Base",
    ),

    # ── Category 10: KW-DGCA System & Installation ────────────────────────
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "System Overview"
    TestQuestion(
        question="kw-dgca aim-amhs components",
        expect="grounded",
        keywords=["AIDA-NG", "CADAS-ATS", "CNMS"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "Message Flow"
    TestQuestion(
        question="kw-dgca message flow",
        expect="grounded",
        keywords=["AIDA-NG", "CADAS-ATS"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "Redundancy"
    TestQuestion(
        question="redundancy modes per component in kw-dgca",
        expect="grounded",
        keywords=["redundancy", "AIDA-NG"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_DGCA_AIM_AMHS_CustomerSystemIntroduction — "OPS vs CONT Systems"
    TestQuestion(
        question="ops at kcmc vs cont at natc, difference",
        expect="grounded",
        keywords=["OPS", "CONT"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_INDRA_AIM_AMHS_Installation — "Kickstart DVD Installation"
    TestQuestion(
        question="install ccms via kickstart dvd",
        expect="grounded",
        keywords=["Kickstart", "DVD"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),
    # Source: KW_INDRA_AIM_AMHS_Installation — "Scientific Linux Installation"
    TestQuestion(
        question="scientific linux install from kickstart, what happens",
        expect="grounded",
        keywords=["Scientific Linux", "GRUB"],
        category=10,
        category_name="KW-DGCA System & Installation",
    ),

    # ── Category 11: MHS System Diagnosis ──────────────────────────────────
    # Source: MHS_SystemDiagnosis — "Troubleshooting Approach"
    TestQuestion(
        question="first step before mhs troubleshooting",
        expect="grounded",
        keywords=["diagnosis", "subsystem"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Log File Locations"
    TestQuestion(
        question="ccms + cluster log file paths",
        expect="grounded",
        keywords=["/var/log/ccms", "cluster"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "AIDA-NG Log Investigation"
    TestQuestion(
        question="investigate aida subsystem failures via logs",
        expect="grounded",
        keywords=["aida-ng", "log"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Server Replacement"
    TestQuestion(
        question="replace defective server with spare, procedure",
        expect="grounded",
        keywords=["disconnect", "spare"],
        category=11,
        category_name="MHS System Diagnosis",
    ),
    # Source: MHS_SystemDiagnosis — "Software Reinstallation"
    TestQuestion(
        question="clean software reinstall on standby server",
        expect="grounded",
        keywords=["reinstall", "network cable"],
        category=11,
        category_name="MHS System Diagnosis",
    ),

    # ── Category 12: Paraphrased Questions ───────────────────────────────
    # Same topics as earlier categories but worded as a frustrated tech mid-shift
    # Tests query rewrite (spec 042) and HyDE (spec 043) resilience

    # Original: "How do I reset the CADAS-ATS administrator password?"
    TestQuestion(
        question="forgot ats admin pw, locked out",
        expect="grounded",
        keywords=["password"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I backup the CADAS-ATS database?"
    TestQuestion(
        question="need to copy ats db before maint, how",
        expect="grounded",
        keywords=["backup", "database"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I check disk usage on an AIDA-NG server?"
    TestQuestion(
        question="aida slow, is the disk full?",
        expect="grounded",
        keywords=["df", "/var"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I replace a defective SNL card in the Frequentis system?"
    TestQuestion(
        question="serial network board broken, swap it",
        expect="grounded",
        keywords=["SNL"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "What are the possible host states in CNMS?"
    TestQuestion(
        question="host statuses on the monitoring tool?",
        expect="grounded",
        keywords=["host", "CNMS"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "How do I remotely access the AMHS router?"
    TestQuestion(
        question="get into the messaging router from my desk",
        expect="grounded",
        keywords=["telnet"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "What is the IP address and hostname of the AIDA-NG server at the CMC site?"
    TestQuestion(
        question="address of aida box at ops center",
        expect="grounded",
        keywords=["172.31"],
        category=12,
        category_name="Paraphrased Questions",
    ),
    # Original: "Walk me through the full procedure to resolve a CADAS-ATS split-brain situation."
    TestQuestion(
        question="both ats nodes think they're primary, now what",
        expect="grounded",
        keywords=["split-brain"],
        category=12,
        category_name="Paraphrased Questions",
    ),

    # ── Category 8: Ambiguous / Vague ──────────────────────────────────────
    TestQuestion(
        question="how do i fix the system",
        expect="either",
        keywords=[],
        category=8,
        category_name="Ambiguous / Vague",
    ),
    TestQuestion(
        question="whats the pw",
        expect="either",
        keywords=[],
        category=8,
        category_name="Ambiguous / Vague",
    ),
    TestQuestion(
        question="how to restart the server",
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
        "source": "test_suite",
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
    """Detect which LLM model and provider the backend is actually using.

    Order of preference:
      1. Ask the backend directly via GET /api/manuals/active-provider — this is
         authoritative because it reads app_settings.ai_provider through the
         same resolver the RAG pipeline uses. Supports every provider
         (local, groq, gemini, mistral, and any future one).
      2. Fall back to Ollama /api/ps (currently-loaded model in VRAM) —
         meaningful only when the backend is routing to local Ollama.
      3. Fall back to Ollama /api/tags (all downloaded models, picks first) —
         clearly labelled as "not loaded" so the ambiguity is visible.

    The old implementation was Ollama-only, so when the backend routed to Groq
    or any cloud provider, the header reported the wrong thing.
    """
    info = {"provider": "unknown", "model": "unknown", "embed_model": "unknown"}

    # Step 1: ask the backend for the real active provider.
    try:
        async with httpx.AsyncClient(verify=False, timeout=5.0) as client:
            resp = await client.get(f"{base_url}/api/manuals/active-provider")
            if resp.status_code == 200:
                data = resp.json()
                provider_key = data.get("provider_key")
                display_name = data.get("display_name") or provider_key or "unknown"
                embed_model = data.get("embed_model") or "unknown"
                info["provider"] = display_name
                info["embed_model"] = embed_model
                # For cloud providers the display_name already contains the model
                # (e.g. "Groq (Llama 3.3 70B)", "Gemini 2.5 Flash").
                info["model"] = display_name
                # If the active provider is local Ollama, try to refine with
                # the actually-loaded VRAM model — more specific than the
                # generic "Local (Ollama)" display name.
                if provider_key != "local":
                    return info
    except Exception:
        pass  # Fall through to Ollama probing below.

    # Ollama is reached at :11434 on the same host as the backend.
    # base_url like "https://host" or "https://host:port" -> strip existing port,
    # substitute :11434. For HTTPS URLs we also downgrade scheme to HTTP because
    # Ollama binds plain HTTP on localhost.
    ollama_candidates = []
    try:
        from urllib.parse import urlparse
        parsed = urlparse(base_url)
        if parsed.hostname:
            ollama_candidates.append(f"http://{parsed.hostname}:11434")
    except Exception:
        pass
    # Always also try localhost — covers the "running the test on the same
    # box as the backend" case.
    ollama_candidates.append("http://localhost:11434")

    async def _fetch_json(client, url):
        try:
            resp = await client.get(url, timeout=5.0)
            if resp.status_code == 200:
                return resp.json()
        except Exception:
            return None
        return None

    async with httpx.AsyncClient(verify=False, timeout=5.0) as client:
        ps_data = None
        tags_data = None
        for base in ollama_candidates:
            if ps_data is None:
                ps_data = await _fetch_json(client, f"{base}/api/ps")
            if tags_data is None:
                tags_data = await _fetch_json(client, f"{base}/api/tags")
            if ps_data is not None and tags_data is not None:
                break

    # Prefer /api/ps — the model actually running right now.
    if ps_data and ps_data.get("models"):
        running = ps_data["models"]
        running_gen = [m["name"] for m in running if "embed" not in m["name"].lower()]
        running_embed = [m["name"] for m in running if "embed" in m["name"].lower()]
        if running_gen:
            info["model"] = running_gen[0]
            info["provider"] = "Ollama (local)"
        if running_embed:
            info["embed_model"] = running_embed[0]

    # Fill in gaps from /api/tags if /api/ps was empty or missed something.
    if tags_data and tags_data.get("models"):
        all_models = tags_data["models"]
        if info["model"] == "unknown":
            gen_models = [m["name"] for m in all_models if "embed" not in m["name"].lower()]
            if gen_models:
                info["model"] = gen_models[0] + "  (not loaded — first in /api/tags)"
                info["provider"] = "Ollama (local)"
        if info["embed_model"] == "unknown":
            embed_models = [m["name"] for m in all_models if "embed" in m["name"].lower()]
            if embed_models:
                info["embed_model"] = embed_models[0]

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
    regression_count = 0
    suite_start = time.perf_counter()

    for i, test in enumerate(tests, 1):
        print(f"[{i}/{len(tests)}] Cat {test.category}: {test.question[:60]}...")
        result = await run_test(test, base_url, verify=verify)
        results.append(result)

        # SC-005 regression check: must_refuse entry returned grounded
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

    # SC-005 regression gate — announce NOW, exit AFTER JSON save below so
    # we keep the evidence file even on regression.
    if regression_count > 0:
        print(f"\n  SC-005 REGRESSION DETECTED — MERGE BLOCKED")
        print(f"  {regression_count} must-refuse question(s) returned grounded answers.")

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

    # SC-005 regression gate — exit AFTER JSON save so CI/humans always have
    # the evidence file. Non-zero exit still signals MERGE BLOCKED to any
    # caller reading $?.
    if regression_count > 0:
        sys.exit(2)


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
