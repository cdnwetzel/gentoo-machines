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


# ----------------------------------------------------------------------
# Ollama call
# ----------------------------------------------------------------------
def ollama_chat(system: str, user: str, *, force_json: bool = True) -> tuple[str, float]:
    """Call /api/chat, return (raw_content, latency_ms)."""
    body = {
        "model":   VERIFY_MODEL,
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
        f"{OLLAMA_HOST}/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECS) as r:
        resp = json.loads(r.read())
    ms = (time.time() - t0) * 1000
    return resp["message"]["content"], ms


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


def check_entity_fidelity(context: str, output: str) -> dict:
    raw, ms = ollama_chat(ENTITY_SYSTEM, f"CONTEXT:\n{context}\n\nOUTPUT:\n{output}")
    parsed = parse_json_or_raw(raw)
    result = {"check": "entity_fidelity", "ms": ms, "raw": raw}

    # Require only the entities list. Verdict is COMPUTED from entity
    # statuses below, not trusted from the model — observed in v2 calibration
    # that 7B sometimes places "verdict" inside the last entity object instead
    # of at the top level. Computing verdict from statuses is what pii_leak
    # and claim_grounding already do; this brings entity_fidelity into line.
    if not isinstance(parsed, dict) or not isinstance(parsed.get("entities"), list):
        result["verdict"] = "error"
        result["error"]   = "model did not return well-formed JSON (no entities list)"
        return result

    entities = parsed["entities"]
    result["entities"] = entities

    def _status(e: dict | object) -> str:
        return e.get("status", "error").lower() if isinstance(e, dict) else "error"

    bad = [e for e in entities if _status(e) not in ("grounded", "pass", "ok", "")]
    n = len(entities)
    n_g = sum(1 for e in entities if _status(e) == "grounded")
    n_p = sum(1 for e in entities if _status(e) == "partial")
    n_u = sum(1 for e in entities if _status(e) == "ungrounded")
    result["verdict"] = "fail" if bad else "pass"
    result["reasoning"] = parsed.get("reasoning") or (
        f"{n_g} grounded, {n_p} partial, {n_u} ungrounded (computed from entity statuses)"
    )
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

Rules:
- GROUNDED: the claim is directly stated in the CONTEXT, or is an obvious paraphrase that preserves meaning.
- UNGROUNDED: the claim introduces information not present in the CONTEXT, even if the information happens to be true in the real world.
- PARTIAL: the claim is mostly in CONTEXT but distorts a detail (different number, different name, different date).

You are NOT judging whether the claim is true in the real world. Only whether it stays within what CONTEXT provides.

Reply JSON only:
{
  "status": "grounded" | "ungrounded" | "partial",
  "evidence": "<quote from CONTEXT supporting the judgment, or what's missing>"
}"""


def check_claim_grounding(context: str, output: str) -> dict:
    total_ms = 0.0
    # 5a: extract
    raw_a, ms_a = ollama_chat(EXTRACT_CLAIMS_SYSTEM, f"OUTPUT:\n{output}")
    total_ms += ms_a
    parsed_a = parse_json_or_raw(raw_a)
    if not isinstance(parsed_a, dict) or not isinstance(parsed_a.get("claims"), list):
        return {"check": "claim_grounding", "ms": total_ms, "verdict": "error",
                "error": f"extraction did not return well-formed JSON: {raw_a[:200]}"}
    claims = parsed_a["claims"]

    # 5b: judge each (sequential — keeps the model warm cleanly)
    judgments = []
    any_bad = False
    for claim in claims:
        raw_b, ms_b = ollama_chat(JUDGE_CLAIM_SYSTEM,
                                   f"CONTEXT:\n{context}\n\nCLAIM:\n{claim}")
        total_ms += ms_b
        parsed_b = parse_json_or_raw(raw_b)
        if not isinstance(parsed_b, dict):
            judgments.append({"claim": claim, "status": "error", "evidence": raw_b[:200], "ms": ms_b})
            any_bad = True
            continue
        status = parsed_b.get("status", "error")
        if status != "grounded":
            any_bad = True
        judgments.append({
            "claim": claim,
            "status": status,
            "evidence": parsed_b.get("evidence", ""),
            "ms": ms_b,
        })

    return {
        "check":   "claim_grounding",
        "ms":      total_ms,
        "verdict": "fail" if any_bad else "pass",
        "claims_extracted": len(claims),
        "judgments": judgments,
        "reasoning": (
            f"{sum(1 for j in judgments if j['status'] == 'grounded')} grounded, "
            f"{sum(1 for j in judgments if j['status'] == 'partial')} partial, "
            f"{sum(1 for j in judgments if j['status'] == 'ungrounded')} ungrounded"
        ),
    }


# ----------------------------------------------------------------------
# Panel
# ----------------------------------------------------------------------
CHECKS = {
    "entity_fidelity": check_entity_fidelity,
    "pii_leak":        check_pii_leak,
    "citation_format": check_citation_format,
    "claim_grounding": check_claim_grounding,
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
