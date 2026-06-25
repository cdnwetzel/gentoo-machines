#!/usr/bin/env python3
"""verify-panel — fan a single (context, output) pair across a panel of narrow
verification checks running on the local qwen2.5:3b verifier (XPS 9510 Ollama).

The single-monolithic "is this output good?" call is at qwen2.5:3b's edge of
competence and produces unreliable verdicts. Decompose into a panel of narrow
checks instead — each in the small model's wheelhouse, each with a clear
pass/fail criterion, aggregate at the end.

Where reliability matters most (PII leaks, hallucinated legal citations), this
tool uses a HYBRID pattern: regex finds structural candidates first, then the
LLM triages each candidate. The 3B model on its own missed the SSN in our
initial calibration; regex makes that miss impossible.

Default panel:

  entity_fidelity   — every named entity, number, date, currency amount in
                      the OUTPUT must appear in or be consistent with the
                      CONTEXT. Catches hallucinated client names, wrong
                      dollar amounts, wrong case numbers, fabricated dates.
                      (Pure LLM. Imperfect recall — see calibration notes
                      in tools/verify-panel-fixtures/.)

  pii_leak          — REGEX prefilter for SSN, EIN, phone, email, unfilled
                      template placeholders, debug markers. LLM triages each
                      candidate: true leak vs benign (firm signature etc).
                      No regex hits → pass immediately, zero LLM calls.

  citation_format   — REGEX scan for federal-reporter and SCOTUS citations
                      in the OUTPUT. Compare against citations found by the
                      same regex on the CONTEXT. Any OUTPUT citation not in
                      the CONTEXT set is flagged as a hallucinated authority.
                      Pure regex+set-membership. No LLM calls.

  claim_grounding   — decomposed into TWO calls: (a) extract every substantive
                      claim in the OUTPUT, then (b) judge each claim
                      independently against the CONTEXT (grounded|ungrounded
                      |partial). Two-call pattern avoids the bundling +
                      missed-claim failure modes observed when asking 3B to
                      do both at once.

Usage:
    tools/verify-panel.py --context ctx.txt --output out.txt
    tools/verify-panel.py --case tools/verify-panel-fixtures/all-grounded.json
    tools/verify-panel.py --case <fixture> --checks entity_fidelity,pii_leak

Environment:
    OLLAMA_HOST   default http://127.0.0.1:11434
    VERIFY_MODEL  default qwen2.5:3b-instruct-q4_K_M
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

OLLAMA_HOST  = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
# Default model is 7B per the v1.5 calibration (see verify-panel-fixtures/CALIBRATION.md).
# 7B closes the v1 semantic-recall gaps (docket digit swap, hallucinated case citations)
# at ~7x latency vs 3B. Override to "qwen2.5:3b-instruct-q4_K_M" if speed matters more
# than recall, or if the 7B model isn't pulled on the box.
VERIFY_MODEL = os.environ.get("VERIFY_MODEL", "qwen2.5:7b-instruct-q4_K_M")
TIMEOUT_SECS = float(os.environ.get("VERIFY_TIMEOUT", "120"))

# v4 item #5: backend selection. Default is local Ollama on the XPS. For the
# experimental "psrouter as judge" path we route via OpenAI-compatible API to
# 192.168.111.162:8888 (firm's legal-tuned 32B/72B). Use a different judge by
# setting these three together:
#   JUDGE_BACKEND=openai-compat
#   JUDGE_BASE_URL=http://192.168.111.162:8888
#   JUDGE_MODEL="Legal Generalist"   (or "PS-Legal-72B")
JUDGE_BACKEND  = os.environ.get("JUDGE_BACKEND", "ollama").lower()
JUDGE_BASE_URL = os.environ.get("JUDGE_BASE_URL", OLLAMA_HOST).rstrip("/")
JUDGE_MODEL    = os.environ.get("JUDGE_MODEL", VERIFY_MODEL)

# v4 item #1: multi-sample voting. When >1, the LLM-driven checks (entity_fidelity,
# claim_grounding) run their LLM call N times and aggregate findings. Costs Nx
# latency but materially improves reliability under the observed non-determinism
# (v3 fixture 05/06: two runs gave very different verdicts). Default 1 preserves
# v3 behavior; set VERIFY_VOTES=3 for the reliability mode.
VERIFY_VOTES = max(1, int(os.environ.get("VERIFY_VOTES", "1")))


# ----------------------------------------------------------------------
# Judge LLM call — dispatches to ollama or openai-compat (psrouter) backend
# ----------------------------------------------------------------------
def _ollama_chat(system: str, user: str, *, force_json: bool = True) -> tuple[str, float]:
    body = {
        "model":   JUDGE_MODEL,
        "stream":  False,
        "options": {"temperature": 0.0, "num_ctx": 8192},
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",   "content": user},
        ],
    }
    if force_json:
        body["format"] = "json"
    req = urllib.request.Request(
        f"{JUDGE_BASE_URL}/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECS) as r:
        resp = json.loads(r.read())
    ms = (time.time() - t0) * 1000
    return resp["message"]["content"], ms


def _openai_chat(system: str, user: str, *, force_json: bool = True) -> tuple[str, float]:
    """OpenAI-compatible /v1/chat/completions — used for psrouter and any
    other backend that speaks the OpenAI shape."""
    body = {
        "model":    JUDGE_MODEL,
        "stream":   False,
        "temperature": 0.0,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",   "content": user},
        ],
    }
    if force_json:
        # vLLM / OpenAI-style JSON mode
        body["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        f"{JUDGE_BASE_URL}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECS) as r:
        resp = json.loads(r.read())
    ms = (time.time() - t0) * 1000
    return resp["choices"][0]["message"]["content"], ms


def ollama_chat(system: str, user: str, *, force_json: bool = True) -> tuple[str, float]:
    """Single judge LLM call — dispatches based on JUDGE_BACKEND.
    Kept named `ollama_chat` for backward-compat with the rest of this file."""
    if JUDGE_BACKEND in ("openai-compat", "openai", "psrouter"):
        return _openai_chat(system, user, force_json=force_json)
    return _ollama_chat(system, user, force_json=force_json)


def parse_json_or_raw(text: str) -> dict | list | str:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


# ----------------------------------------------------------------------
# Check 1 — entity / number / date fidelity
# ----------------------------------------------------------------------
ENTITY_SYSTEM = """You are an entity-fidelity verifier. Identify every NAMED ENTITY (person, organization, place), NUMBER, DATE, CURRENCY AMOUNT, CASE/STATUTE CITATION, and OTHER CONCRETE FACT in the OUTPUT. For each, judge whether it is present in or consistent with the CONTEXT.

Rules:
- GROUNDED: the entity appears verbatim in the CONTEXT, or is an obvious paraphrase (e.g. "John" vs "Mr. Smith" when the same person is named in CONTEXT).
- UNGROUNDED: the entity introduces a new name, number, date, or fact NOT present in the CONTEXT.
- PARTIAL: the referent is in CONTEXT but a detail is wrong (e.g. CONTEXT says "$5,000", OUTPUT says "$5,500").

Generic English words, articles, pronouns, common adjectives — IGNORE. Only flag concrete facts.

Reply JSON only:
{
  "entities": [
    {"text": "<entity exactly as it appears in OUTPUT>",
     "type": "person|org|place|number|date|currency|case|statute|other",
     "status": "grounded|ungrounded|partial",
     "evidence": "<quote from CONTEXT, or 'not in context', or 'CONTEXT says X'>"}
  ],
  "verdict": "pass" | "fail",
  "reasoning": "<one sentence>"
}

Verdict is "pass" only if EVERY entity is grounded. Any ungrounded or partial → "fail"."""


def _extract_entities_one_run(context: str, output: str) -> tuple[list[dict], float, str]:
    """Single LLM call to extract+judge entities. Returns (entities, ms, raw)."""
    raw, ms = ollama_chat(ENTITY_SYSTEM, f"CONTEXT:\n{context}\n\nOUTPUT:\n{output}")
    parsed = parse_json_or_raw(raw)
    if not isinstance(parsed, dict) or not isinstance(parsed.get("entities"), list):
        return [], ms, raw
    return parsed["entities"], ms, raw


def _vote_on_entities(runs: list[list[dict]], min_consensus: int) -> list[dict]:
    """Combine entities across N runs. For each entity (by normalized text),
    take the majority status across runs that mentioned it. Findings appearing
    in fewer than min_consensus runs are dropped as noise."""
    from collections import Counter
    by_text: dict[str, list[dict]] = {}
    for run in runs:
        for e in run:
            if not isinstance(e, dict):
                continue
            key = _normalize_for_grep(e.get("text", ""))
            if not key:
                continue
            by_text.setdefault(key, []).append(e)
    voted: list[dict] = []
    for _key, occurrences in by_text.items():
        if len(occurrences) < min_consensus:
            continue  # not enough consensus to trust
        statuses = [str(e.get("status", "error")).lower() for e in occurrences]
        status, count = Counter(statuses).most_common(1)[0]
        # Pick the most informative evidence string
        evidence = max((e.get("evidence", "") for e in occurrences), key=len, default="")
        # Use the first observed text + type
        first = occurrences[0]
        voted.append({
            "text":     first.get("text", ""),
            "type":     first.get("type", ""),
            "status":   status,
            "evidence": evidence,
            "votes":    f"{count}/{len(occurrences)} agree on '{status}' across {len(runs)} runs",
        })
    return voted


def check_entity_fidelity(context: str, output: str) -> dict:
    # v4 item #1: multi-sample voting. With VERIFY_VOTES=N, run extraction N
    # times and aggregate. N=1 preserves prior behavior.
    runs: list[list[dict]] = []
    raws: list[str] = []
    total_ms = 0.0
    for _ in range(VERIFY_VOTES):
        entities, ms, raw = _extract_entities_one_run(context, output)
        runs.append(entities)
        raws.append(raw)
        total_ms += ms

    if VERIFY_VOTES > 1:
        # min_consensus = ceil(N/2) — entity must appear in majority of runs
        min_consensus = (VERIFY_VOTES + 1) // 2
        entities = _vote_on_entities(runs, min_consensus)
    else:
        entities = runs[0]

    result = {"check": "entity_fidelity", "ms": total_ms, "raw": raws[0] if raws else "", "votes": VERIFY_VOTES}

    if not entities:
        # Either parse failure on all runs, or no entities found
        if VERIFY_VOTES == 1 and not isinstance(parse_json_or_raw(raws[0]) if raws else None, dict):
            result["verdict"] = "error"
            result["error"]   = "model did not return well-formed JSON (no entities list)"
            return result
        # Genuine empty — nothing to check, treat as pass
        result["verdict"] = "pass"
        result["entities"] = []
        result["reasoning"] = "no entities extracted"
        return result

    def _status(e: dict | object) -> str:
        return e.get("status", "error").lower() if isinstance(e, dict) else "error"

    # v4 item #4 post-process: override LLM ungrounded/partial when the entity
    # literally appears in CONTEXT. The LLM is the high-recall extractor; this
    # string-match is the precision filter that catches LLM mistakes on entities
    # that ARE in CONTEXT but the model lost track of.
    n_overrides = 0
    for e in entities:
        if not isinstance(e, dict):
            continue
        s = _status(e)
        if s in ("ungrounded", "partial"):
            text = e.get("text", "")
            if _appears_verbatim(text, context):
                e["status_original"]   = s
                e["override_reason"]   = "verbatim_string_match"
                e["status"]            = "grounded"
                n_overrides += 1

    result["entities"] = entities

    bad = [e for e in entities if _status(e) not in ("grounded", "pass", "ok", "")]
    n_g = sum(1 for e in entities if _status(e) == "grounded")
    n_p = sum(1 for e in entities if _status(e) == "partial")
    n_u = sum(1 for e in entities if _status(e) == "ungrounded")
    result["verdict"]   = "fail" if bad else "pass"
    result["overrides"] = n_overrides

    # Computed reasoning ALWAYS — the model's reasoning becomes stale after we
    # apply the verbatim override and/or majority vote.
    reasoning_bits = [f"{n_g} grounded", f"{n_p} partial", f"{n_u} ungrounded"]
    if n_overrides:
        reasoning_bits.append(f"{n_overrides} LLM false-positive(s) overridden by verbatim match")
    if VERIFY_VOTES > 1:
        reasoning_bits.append(f"across {VERIFY_VOTES} sample runs")
    result["reasoning"] = "; ".join(reasoning_bits) + " (computed)"
    return result


# ----------------------------------------------------------------------
# Check 3 — PII / placeholder leak (hybrid: regex prefilter + LLM triage)
# ----------------------------------------------------------------------
# Regex finds candidates with near-perfect recall; LLM triages each to
# decide "real leak" vs "benign" (e.g., firm's main phone in signature).
# If regex finds zero candidates, the LLM is never called.

PII_PATTERNS = [
    # Placeholders — nearly always a leak if they appear unfilled
    ("placeholder",  re.compile(r'\{[a-zA-Z_][a-zA-Z0-9_]*\}')),                     # {client_name}
    ("placeholder",  re.compile(r'\[[A-Z_][A-Z0-9_]{2,}\]')),                         # [ATTORNEY_NAME] [DATE]
    ("placeholder",  re.compile(r'<[A-Z_][A-Z0-9_]{2,}>')),                           # <REDACTED>
    ("placeholder",  re.compile(r'X{3,}-X{2,}-X{4,}', re.IGNORECASE)),                # XXX-XX-XXXX
    ("placeholder",  re.compile(r'\b(?:TODO|FIXME|XXX|TBD|DEBUG)\b')),
    ("placeholder",  re.compile(r'lorem ipsum', re.IGNORECASE)),
    # PII-shaped
    ("pii_ssn",      re.compile(r'\b\d{3}-\d{2}-\d{4}\b')),                            # 123-45-6789
    ("pii_ein",      re.compile(r'\b\d{2}-\d{7}\b')),                                   # 12-3456789
    ("pii_phone",    re.compile(r'\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}\b')),
    ("pii_email",    re.compile(r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b')),
    # Credit-card-shaped (Luhn not validated — pattern only)
    ("pii_cc",       re.compile(r'\b(?:\d{4}[-\s]?){3}\d{4}\b')),
]


def _surrounding(text: str, span: tuple[int, int], width: int = 50) -> str:
    """Return the text around a span, with the span quoted, for LLM triage context."""
    lo = max(0, span[0] - width)
    hi = min(len(text), span[1] + width)
    snippet = text[lo:hi].replace("\n", " ")
    return ("…" if lo > 0 else "") + snippet + ("…" if hi < len(text) else "")


# ----------------------------------------------------------------------
# Verbatim string-match helpers (v4 — addresses real-prose false positives)
# ----------------------------------------------------------------------
# v3 real-psrouter calibration showed the LLM verifier flags entities as
# ungrounded even when they appear verbatim in CONTEXT (April 17 2026,
# $78,400, $4,200, June 3 2019). It loses track of which CONTEXT span
# supports a given entity when the surrounding prose is rephrased. Cheap
# post-process: after the LLM judges an entity ungrounded/partial, check
# whether the entity literally appears in CONTEXT. If it does, the LLM
# was wrong; promote to grounded.

def _normalize_for_grep(s: str) -> str:
    """Light normalization so 'April 17, 2026' matches 'April 17,2026' or
    'April 17 2026'. Conservative — we don't want to make UNGROUNDED items
    look grounded by over-normalizing."""
    if not isinstance(s, str):
        return ""
    s = s.strip(" \t\n.,;:!?()\"'`")
    s = re.sub(r"\s+", " ", s)
    return s.lower()


def _appears_verbatim(needle: str, haystack: str) -> bool:
    """True iff needle (lightly normalized) appears as a substring of haystack
    (lightly normalized). Returns False for very short needles to avoid
    coincidental matches like ' the ' inside arbitrary prose."""
    n = _normalize_for_grep(needle)
    h = _normalize_for_grep(haystack)
    if len(n) < 3:
        return False
    return n in h


def find_pii_candidates(output: str) -> list[dict]:
    """Regex-find every potential PII / placeholder in OUTPUT. High recall by design."""
    found = []
    seen = set()  # de-dupe same text+kind+span
    for kind, pat in PII_PATTERNS:
        for m in pat.finditer(output):
            key = (kind, m.start(), m.end())
            if key in seen: continue
            seen.add(key)
            found.append({
                "text":  m.group(0),
                "kind":  kind,
                "span":  [m.start(), m.end()],
                "where": _surrounding(output, m.span()),
            })
    return found


PII_TRIAGE_SYSTEM = """You triage candidate PII / placeholder leaks. A regex prefilter found a candidate in an OUTPUT meant for client-facing content. Decide whether it is a REAL leak that should be flagged, or a BENIGN occurrence that is fine.

META-RULE — read first, applies to every decision below:
  WHEN UNCERTAIN, FLAG. False positives are recoverable in human review; missed leaks are not. If you cannot prove a candidate is benign with explicit evidence in the surrounding text, the answer is "is_leak": true.

ALWAYS-FLAG categories (no exceptions, regardless of surrounding context):

  1. SSN-shaped strings — any string matching the pattern NNN-NN-NNNN is ALWAYS a leak unless the surrounding text *explicitly* marks it as test/demo/example data using words like "example SSN", "sample SSN", "for illustration", "test data", "training data", or shown in deliberately-masked form (e.g. XXX-XX-1234 with at least three real X's). "Your SSN on file is …" or "verify your SSN (…)" is a real leak even though it doesn't unambiguously identify whose SSN — those framings are exactly how production templates leak client SSNs.

  2. Unfilled template placeholders — any literal `{name}`, `{client_name}`, `[ATTORNEY_NAME]`, `[ALLCAPS_NAME]`, `<ALLCAPS_NAME>`, `XXX-XX-XXXX` is ALWAYS an unfilled placeholder leak in client-facing content. There is no legitimate reason for a recipient to see a template variable that wasn't substituted.

  3. Debug / internal markers — `TODO`, `FIXME`, `XXX` (as a word, not as part of XXX-XX-XXXX), `TBD`, `DEBUG`, "lorem ipsum" — ALWAYS flag.

  4. Credit-card-shaped strings (groups of 4-4-4-4 digits) — ALWAYS flag.

CONTEXT-SENSITIVE categories (require explicit benign evidence to NOT flag):

  5. Phone numbers — flag UNLESS the surrounding text clearly identifies the number as the firm's own (e.g. appears in a signature block with the firm's name, or labeled "Firm: 555-…", "Office: 555-…"). A bare phone number with no firm-identifying context is a leak.

  6. Email addresses — flag UNLESS the surrounding text clearly identifies the email as the firm's own (e.g. firm-domain like info@firm.com, attorney@firmname.com inside a signature block). A client's personal email being echoed back is a leak.

  7. EIN-shaped strings (NN-NNNNNNN) — flag UNLESS the surrounding text labels it as the firm's own EIN (e.g. "Our EIN: 12-3456789" in a billing context). A bare EIN-shaped number is a leak.

Reply JSON ONLY:
{"is_leak": true | false, "reason": "<one short sentence — cite which rule applied>"}"""


def triage_pii(candidate: dict) -> dict:
    user = (
        f"CANDIDATE: {candidate['text']!r}\n"
        f"KIND:      {candidate['kind']}\n"
        f"WHERE:     {candidate['where']}\n"
    )
    raw, ms = ollama_chat(PII_TRIAGE_SYSTEM, user)
    parsed = parse_json_or_raw(raw)
    if not isinstance(parsed, dict):
        # If triage fails, default to flagging (safer for PII)
        return {**candidate, "is_leak": True, "reason": "triage failed; defaulting to flag", "triage_ms": ms}
    is_leak = bool(parsed.get("is_leak", True))
    reason  = str(parsed.get("reason", ""))
    return {**candidate, "is_leak": is_leak, "reason": reason, "triage_ms": ms}


def check_pii_leak(context: str, output: str) -> dict:
    candidates = find_pii_candidates(output)
    if not candidates:
        return {
            "check":     "pii_leak",
            "ms":        0.0,
            "verdict":   "pass",
            "leaks":     [],
            "candidates_examined": 0,
            "reasoning": "regex prefilter found no PII / placeholder candidates",
        }
    triaged = [triage_pii(c) for c in candidates]
    flagged = [t for t in triaged if t["is_leak"]]
    total_ms = sum(t.get("triage_ms", 0) for t in triaged)
    return {
        "check":     "pii_leak",
        "ms":        total_ms,
        "verdict":   "fail" if flagged else "pass",
        "leaks":     flagged,
        "benign":    [t for t in triaged if not t["is_leak"]],
        "candidates_examined": len(candidates),
        "reasoning": (
            f"{len(flagged)}/{len(candidates)} candidates flagged as real leaks"
            if flagged else f"all {len(candidates)} candidates triaged as benign"
        ),
    }


# ----------------------------------------------------------------------
# Check 4 — Citation format (regex + verbatim-against-context)
# ----------------------------------------------------------------------
# Find legal citations in the OUTPUT via regex; if any aren't verbatim
# in the CONTEXT (after light normalization), they're hallucinated
# authorities — the most catastrophic failure mode for legal-domain
# RAG. No LLM needed: legal citations are mechanical strings; legitimate
# paraphrase is essentially nonexistent.

CITATION_PATTERNS = [
    # US Supreme Court: "550 U.S. 544 (2007)" — allow variant punctuation/spacing
    re.compile(r'\b\d{1,4}\s+U\.?\s?S\.?\s+\d+(?:,\s*\d+)?\s+\(\s*\d{4}\s*\)'),
    # Federal Reporter (F., F.2d, F.3d, F.4th): "891 F.3d 412 (3d Cir. 2018)"
    re.compile(r'\b\d{1,4}\s+F\.\s*(?:2d|3d|4th)\s+\d+(?:,\s*\d+)?\s+\([^)]*\d{4}\s*\)'),
    # Federal Supplement variants: "320 F.Supp.2d 1010 (S.D.N.Y. 2004)"
    re.compile(r'\b\d{1,4}\s+F\.\s?Supp\.?(?:\s?\d?d?)?\s+\d+(?:,\s*\d+)?\s+\([^)]*\d{4}\s*\)'),
    # Lawyers' Edition: "163 L.Ed.2d 1 (2005)"
    re.compile(r'\b\d{1,4}\s+L\.?\s?Ed\.?\s*(?:2d|3d)?\s+\d+(?:,\s*\d+)?\s+\(\s*\d{4}\s*\)'),
    # Supreme Court Reporter: "127 S.Ct. 2162 (2007)"
    re.compile(r'\b\d{1,4}\s+S\.?\s?Ct\.?\s+\d+(?:,\s*\d+)?\s+\(\s*\d{4}\s*\)'),
]


def _normalize_citation(s: str) -> str:
    """Collapse whitespace + remove punctuation variance so different formattings of
    the same citation compare equal: '891 F.3d 412 (3d Cir. 2018)' == '891 F. 3d 412 (3d Cir.2018)'."""
    return re.sub(r'\s+', ' ', re.sub(r'[.\s]', ' ', s.lower())).strip()


def find_citations(text: str) -> list[str]:
    """Return the verbatim citation strings (as they appear) found in text."""
    found = []
    seen = set()
    for pat in CITATION_PATTERNS:
        for m in pat.finditer(text):
            cit = m.group(0)
            norm = _normalize_citation(cit)
            if norm in seen: continue
            seen.add(norm)
            found.append(cit)
    return found


def check_citation_format(context: str, output: str) -> dict:
    out_cites = find_citations(output)
    if not out_cites:
        return {
            "check":     "citation_format",
            "ms":        0.0,
            "verdict":   "pass",
            "citations_in_output":  [],
            "ungrounded_citations": [],
            "reasoning": "no legal citations detected in OUTPUT",
        }
    ctx_cites_normalized = {_normalize_citation(c) for c in find_citations(context)}
    ungrounded = [c for c in out_cites if _normalize_citation(c) not in ctx_cites_normalized]
    return {
        "check":     "citation_format",
        "ms":        0.0,  # pure-regex check; no LLM time to charge
        "verdict":   "fail" if ungrounded else "pass",
        "citations_in_output":  out_cites,
        "ungrounded_citations": ungrounded,
        "reasoning": (
            f"{len(ungrounded)}/{len(out_cites)} citations not in CONTEXT (likely hallucinated)"
            if ungrounded else
            f"all {len(out_cites)} citations also appear in CONTEXT"
        ),
    }


# ----------------------------------------------------------------------
# Check — numeric fidelity (v4 — applies the regex+verbatim pattern that
# worked for citations to numbers/dollars/dates/dockets)
# ----------------------------------------------------------------------
# v3 real-prose calibration: the 7B LLM repeatedly flagged numbers that ARE
# verbatim in CONTEXT ($78,400; $4,200; April 17, 2026; June 3, 2019). It
# extracts numbers correctly but matches them against the wrong section of
# CONTEXT. Same hybrid pattern that worked for pii_leak (regex extract,
# compare deterministically) removes this entire class of false positive
# AND catches real numeric drift (docket digit swap, dollar drift)
# deterministically — never up to model judgment.

# Concrete-number patterns we care about for legal-RAG outputs. Each pattern
# captures the FULL span we want to compare verbatim (not just the digits).
NUMBER_PATTERNS = [
    # Currency: $4,200 / $78,400.00 / $5,000.50
    re.compile(r'\$[\d,]+(?:\.\d+)?'),
    # Long-form dates: "April 17, 2026" / "April 17 2026"
    re.compile(r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b', re.IGNORECASE),
    # ISO dates: 2026-04-17
    re.compile(r'\b\d{4}-\d{2}-\d{2}\b'),
    # Slash dates: 4/17/2026 or 04/17/26
    re.compile(r'\b\d{1,2}/\d{1,2}/\d{2,4}\b'),
    # Dockets (YYYY-XX-NNNNN or YYYY-XX-NNN style): 2026-CV-00847 / 2026-EM-00321
    re.compile(r'\b\d{4}-[A-Z]{1,5}-\d{3,}\b'),
    # Comma-grouped large numbers: 1,247
    re.compile(r'\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b'),
    # Bare 4-digit years (catch-all, run last so longer patterns win first)
    re.compile(r'\b(?:19|20)\d{2}\b'),
]


def find_numbers(text: str) -> list[str]:
    """Return the verbatim numeric strings (as they appear) found in text.
    De-duplicates by normalized form so 'April 17, 2026' and 'april 17 2026'
    are treated as the same finding."""
    found = []
    seen = set()
    # Run patterns in declared order; longer/more-specific patterns first
    # so we don't double-extract (e.g. "April 17, 2026" already covers 2026)
    spans_taken: list[tuple[int, int]] = []
    for pat in NUMBER_PATTERNS:
        for m in pat.finditer(text):
            # Skip if this span overlaps with a longer match already taken
            if any(s <= m.start() and m.end() <= e for s, e in spans_taken):
                continue
            spans_taken.append((m.start(), m.end()))
            norm = _normalize_for_grep(m.group(0))
            if norm in seen: continue
            seen.add(norm)
            found.append(m.group(0))
    return found


def check_numeric_fidelity(context: str, output: str) -> dict:
    """Extract every number / date / docket / currency from OUTPUT, compare
    each verbatim against the same regex run on CONTEXT. Anything in OUTPUT
    not in CONTEXT is flagged as a possible hallucination. Pure regex + set
    membership; no LLM."""
    out_nums = find_numbers(output)
    if not out_nums:
        return {
            "check":     "numeric_fidelity",
            "ms":        0.0,
            "verdict":   "pass",
            "numbers_in_output":  [],
            "ungrounded_numbers": [],
            "reasoning": "no numeric strings detected in OUTPUT",
        }
    ctx_nums_normalized = {_normalize_for_grep(n) for n in find_numbers(context)}
    ungrounded = [n for n in out_nums if _normalize_for_grep(n) not in ctx_nums_normalized]
    return {
        "check":     "numeric_fidelity",
        "ms":        0.0,
        "verdict":   "fail" if ungrounded else "pass",
        "numbers_in_output":  out_nums,
        "ungrounded_numbers": ungrounded,
        "reasoning": (
            f"{len(ungrounded)}/{len(out_nums)} numbers not in CONTEXT — likely hallucinated or drifted"
            if ungrounded else
            f"all {len(out_nums)} numbers also appear in CONTEXT"
        ),
    }


# ----------------------------------------------------------------------
# Check 5 — Per-claim grounding (2-call decomposition)
# ----------------------------------------------------------------------
EXTRACT_CLAIMS_SYSTEM = """You are a claim extractor. Identify every SUBSTANTIVE factual or substantive claim made in the OUTPUT. A claim is a statement that asserts something concrete about the world — facts about people, organizations, events, numbers, relationships, dates, capabilities.

Do NOT extract:
- Greetings, sign-offs, transitional language ("Hello", "Best regards")
- Filler/connector phrases ("As I mentioned earlier")
- Generic prose with no concrete claim ("It is important to note that...")

DO extract:
- Every claim about specific people, places, things, numbers, dates
- Every claim about events that happened or will happen
- Every claim about capabilities, relationships, attributes

Be exhaustive — better to over-extract than miss one. Each extracted claim should be a SHORT self-contained sentence; if a paragraph has 3 claims, return 3 entries.

Reply JSON only:
{
  "claims": ["<claim 1>", "<claim 2>", ...]
}"""

JUDGE_CLAIM_SYSTEM = """You are a grounding judge. Given a CONTEXT and a CLAIM, judge whether the CLAIM is supported by the CONTEXT.

META-RULE — read first:
  When the CLAIM adds detail not in the CONTEXT (a fuller name, an extra qualifier, a doctrine framework, a year, an expansion), the answer is NOT "grounded" — even if the added detail is true in the real world. Default to UNGROUNDED or PARTIAL for any addition. False positives in grounding are recoverable in review; missed expansions are how hallucinations ship.

Rules:
  - GROUNDED: the claim's content is directly stated in CONTEXT or is a trivial-rewording paraphrase (different word order, added "the/a/an", etc.) preserving the same facts.
  - UNGROUNDED: the claim introduces facts (names, statutes, citations, dates, quantities, doctrines) not present in CONTEXT.
  - PARTIAL: the claim has the right referent but distorts a detail (different number, different date, different name spelling).

EXAMPLES of subtle ungrounded expansions (study these — they are FAILURE patterns the LLM-as-judge has historically missed):

  Example 1 — EXPANSION ungrounded:
    CONTEXT: "Plaintiff filed under Title VII."
    CLAIM:   "Plaintiff filed under Title VII of the Civil Rights Act of 1964."
    STATUS:  ungrounded
    EVIDENCE: "CONTEXT mentions 'Title VII' but not the expansion to 'Civil Rights Act of 1964'. Even though the expansion is correct in the real world, the year and full statute name are not in CONTEXT."

  Example 2 — TRIVIAL paraphrase grounded:
    CONTEXT: "Terminated April 17, 2026."
    CLAIM:   "She was terminated on April 17, 2026."
    STATUS:  grounded
    EVIDENCE: "Same date, trivial wording difference."

  Example 3 — DOCTRINE addition ungrounded:
    CONTEXT: "Terminated shortly after she made an internal complaint."
    CLAIM:   "The close temporal proximity between the protected activity and the adverse action supports a retaliation claim under McDonnell Douglas burden-shifting."
    STATUS:  ungrounded
    EVIDENCE: "CONTEXT mentions termination after a complaint, but introduces 'temporal proximity', 'protected activity', and 'McDonnell Douglas' as doctrine framework that is not in CONTEXT."

  Example 4 — DETAIL drift partial:
    CONTEXT: "Annual salary $78,400."
    CLAIM:   "Annual salary $78,500."
    STATUS:  partial
    EVIDENCE: "Salary amount drifted by $100."

  Example 5 — NEW citation ungrounded:
    CONTEXT: "The motion is based on Rule 12(b)(6)."
    CLAIM:   "The motion relies on the Third Circuit's holding in Westfield v. Carter, 891 F.3d 412 (3d Cir. 2018)."
    STATUS:  ungrounded
    EVIDENCE: "CONTEXT mentions Rule 12(b)(6); the Westfield v. Carter citation and the Third Circuit holding are new authorities not in CONTEXT."

Reply JSON only:
{
  "status": "grounded" | "ungrounded" | "partial",
  "evidence": "<quote from CONTEXT supporting the judgment, or what's missing>"
}"""


def _judge_one_claim(context: str, claim: str) -> dict:
    """Single LLM judgment for one claim. With VERIFY_VOTES>1, takes majority
    across N runs and notes the agreement count."""
    from collections import Counter
    statuses: list[str] = []
    evidences: list[str] = []
    total_ms = 0.0
    for _ in range(VERIFY_VOTES):
        raw, ms = ollama_chat(JUDGE_CLAIM_SYSTEM,
                              f"CONTEXT:\n{context}\n\nCLAIM:\n{claim}")
        total_ms += ms
        parsed = parse_json_or_raw(raw)
        if isinstance(parsed, dict):
            statuses.append(str(parsed.get("status", "error")).lower())
            evidences.append(str(parsed.get("evidence", "")))
        else:
            statuses.append("error")
            evidences.append(raw[:200])
    status, count = Counter(statuses).most_common(1)[0]
    evidence = max(evidences, key=len, default="")
    out = {"claim": claim, "status": status, "evidence": evidence, "ms": total_ms}
    if VERIFY_VOTES > 1:
        out["votes"] = f"{count}/{VERIFY_VOTES} agree on '{status}'"
    return out


def check_claim_grounding(context: str, output: str) -> dict:
    total_ms = 0.0
    # 5a: extract claims (single call — multi-sample voting at the claim list
    # level is harder because different runs may extract different claims;
    # the voting at the judgment level below covers the consequential drift).
    raw_a, ms_a = ollama_chat(EXTRACT_CLAIMS_SYSTEM, f"OUTPUT:\n{output}")
    total_ms += ms_a
    parsed_a = parse_json_or_raw(raw_a)
    if not isinstance(parsed_a, dict) or not isinstance(parsed_a.get("claims"), list):
        return {"check": "claim_grounding", "ms": total_ms, "verdict": "error",
                "error": f"extraction did not return well-formed JSON: {raw_a[:200]}"}
    claims = parsed_a["claims"]

    # 5b: judge each claim — with VERIFY_VOTES>1, multi-sample per judgment.
    judgments = []
    any_bad = False
    for claim in claims:
        j = _judge_one_claim(context, claim)
        total_ms += j["ms"]  # already accumulated inside _judge_one_claim; ok
        if j["status"] != "grounded":
            any_bad = True
        judgments.append(j)

    return {
        "check":   "claim_grounding",
        "ms":      total_ms,
        "verdict": "fail" if any_bad else "pass",
        "claims_extracted": len(claims),
        "judgments": judgments,
        "votes": VERIFY_VOTES,
        "reasoning": (
            f"{sum(1 for j in judgments if j['status'] == 'grounded')} grounded, "
            f"{sum(1 for j in judgments if j['status'] == 'partial')} partial, "
            f"{sum(1 for j in judgments if j['status'] == 'ungrounded')} ungrounded"
            + (f" (each judgment voted across {VERIFY_VOTES} samples)" if VERIFY_VOTES > 1 else "")
        ),
    }


# ----------------------------------------------------------------------
# Panel
# ----------------------------------------------------------------------
CHECKS = {
    "entity_fidelity":  check_entity_fidelity,
    "pii_leak":         check_pii_leak,
    "citation_format":  check_citation_format,
    "numeric_fidelity": check_numeric_fidelity,
    "claim_grounding":  check_claim_grounding,
}


def run_panel(context: str, output: str, enabled: list[str]) -> dict:
    results = []
    for name in enabled:
        fn = CHECKS.get(name)
        if fn is None:
            results.append({"check": name, "verdict": "error", "error": "unknown check"})
            continue
        try:
            results.append(fn(context, output))
        except urllib.error.URLError as e:
            results.append({"check": name, "verdict": "error", "error": f"ollama unreachable: {e}"})
        except Exception as e:
            results.append({"check": name, "verdict": "error", "error": f"{type(e).__name__}: {e}"})

    overall = "pass" if all(r.get("verdict") == "pass" for r in results) else "fail"
    return {"verdict": overall, "checks": results, "total_ms": sum(r.get("ms", 0) for r in results)}


def render_text(panel: dict) -> str:
    lines = []
    overall = panel["verdict"]
    icon = "PASS" if overall == "pass" else "FAIL"
    lines.append(f"=== PANEL VERDICT: {icon} ({panel['total_ms']:.0f} ms total) ===")
    for r in panel["checks"]:
        v = r.get("verdict", "error")
        mark = "  ✓" if v == "pass" else ("  ✗" if v == "fail" else "  !")
        lines.append(f"{mark} {r['check']:20s} {v:5s}  {r.get('ms', 0):.0f} ms")
        if r.get("error"):
            lines.append(f"    error: {r['error']}")
        if r.get("entities"):
            for e in r["entities"]:
                if e.get("status") != "grounded":
                    lines.append(f"    [{e.get('status','?')}] {e.get('text','')!r}  ({e.get('type','?')})")
                    if e.get("evidence"):
                        lines.append(f"        evidence: {e['evidence']}")
        if r.get("leaks"):
            for l in r["leaks"]:
                lines.append(f"    [{l.get('kind','?')}] {l.get('text','')!r}")
                if l.get("where"):
                    lines.append(f"        in: {l['where']}")
                if l.get("reason"):
                    lines.append(f"        triage: {l['reason']}")
        if r.get("ungrounded_citations"):
            for c in r["ungrounded_citations"]:
                lines.append(f"    [hallucinated_cite] {c!r}")
        if r.get("ungrounded_numbers"):
            for n in r["ungrounded_numbers"]:
                lines.append(f"    [hallucinated_number] {n!r}")
        if r.get("judgments"):
            for j in r["judgments"]:
                if j.get("status") != "grounded":
                    lines.append(f"    [{j.get('status','?')}] {j.get('claim','')!r}")
                    if j.get("evidence"):
                        lines.append(f"        evidence: {j['evidence']}")
        if r.get("reasoning"):
            lines.append(f"    summary: {r['reasoning']}")
    return "\n".join(lines)


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--context", help="path to file containing the CONTEXT")
    ap.add_argument("--output",  help="path to file containing the OUTPUT to verify")
    ap.add_argument("--case",    help="path to fixture JSON with {context, output[, expected]}")
    ap.add_argument("--checks",  default=",".join(CHECKS.keys()),
                    help=f"comma-separated check names (default: all). available: {','.join(CHECKS)}")
    ap.add_argument("--json",    action="store_true", help="emit raw JSON, no text rendering")
    args = ap.parse_args()

    if args.case:
        with open(args.case) as f:
            case = json.load(f)
        context, output = case["context"], case["output"]
        expected = case.get("expected", {})
    elif args.context and args.output:
        with open(args.context) as f: context = f.read()
        with open(args.output)  as f: output  = f.read()
        expected = {}
    else:
        ap.error("supply either --case <fixture> or both --context and --output")

    enabled = [c.strip() for c in args.checks.split(",") if c.strip()]
    panel = run_panel(context, output, enabled)

    if args.json:
        print(json.dumps(panel, indent=2))
    else:
        print(render_text(panel))
        if expected:
            print()
            print("=== Expected (from fixture) ===")
            if isinstance(expected, dict):
                for k, v in expected.items():
                    print(f"  {k}: {v}")
            else:
                # Real psrouter-derived fixtures may use a plain string here
                # ("TBD — populated after panel run") rather than a structured dict.
                print(f"  {expected}")

    sys.exit(0 if panel["verdict"] == "pass" else 1)


if __name__ == "__main__":
    main()
