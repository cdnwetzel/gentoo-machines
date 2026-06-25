#!/usr/bin/env python3
"""Build a meaningful-volume calibration corpus for verify-panel by sending
varied legal-domain prompts to psrouter and capturing each real output as a
fixture. Each (context, query) pair is constructed to look like what iChris's
psrouter calls actually look like — a paralegal-style system prompt, a matter
context bundle, and a specific question.

The matters and questions are synthetic but realistic in shape (specific
docket numbers, parties, dates, dollar amounts, judges, etc.) — enough
varied concrete entities for the panel to stress-test against.

Usage:
    tools/build-calibration-corpus.py
        --out tools/verify-panel-fixtures/real-psrouter/
        [--model "Legal Generalist" | "PS-Legal-72B"]
        [--limit N]

Each output fixture is named NN-matter-question.json where matter and
question encode the variation. Numbering starts at 10 to leave room for the
existing fixtures 05/06.
"""
import argparse
import json
import os
import sys
import time
import urllib.request

PSROUTER = "http://192.168.111.162:8888/v1/chat/completions"

SYSTEM_PROMPT = """You are a paralegal assistant. Use ONLY the matter facts and KB passages below to answer the user's question. Do not introduce case law, statutes, or facts that aren't in the materials provided. Cite the source of any fact you state."""


# ------------------------------------------------------------------
# Matter contexts — designed with rich varied concrete entities to
# stress-test the panel's grounding checks. Each context has:
#   - parties (specific names)
#   - dates (multiple, varied formats)
#   - dollar amounts (varied magnitudes)
#   - dockets / case numbers
#   - judges / court info
#   - jurisdictional facts
# ------------------------------------------------------------------

MATTERS = {
    "employment": """\
MATTER FACTS (Docket 2026-EM-00321, Carter v. Apex Logistics, Inc., Superior Court of Mercer County, NJ, before Judge Patel):

- Plaintiff: Janet Carter, hired by Apex Logistics on June 3, 2019 as a regional dispatch coordinator at the firm's Bordentown, NJ warehouse.
- Defendant: Apex Logistics, Inc., a Delaware corporation with principal place of business at 1450 Industrial Drive, Bordentown, NJ.
- Termination: Ms. Carter was terminated on April 17, 2026. Apex's stated reason was "performance issues," but no written warning or PIP exists in her personnel file.
- Compensation at termination: $78,400 annual salary, plus health benefits and a discretionary year-end bonus of $4,200 in 2025.
- Claim: Ms. Carter alleges wrongful termination on the basis of her gender (Title VII) and retaliation for a March 2026 internal complaint about overtime calculation practices.
- Filed: Complaint filed June 10, 2026. Apex was served June 14, 2026. Apex's answer is due August 13, 2026.
- Discovery: Initial document requests served July 1, 2026. Apex has produced 1,247 documents to date.
- Lead counsel for plaintiff: Maria Chen, Portnoy Schneck LLC.
- Lead counsel for defendant: not yet entered an appearance.
""",

    "contract": """\
MATTER FACTS (Docket 2026-CV-04188, Sterling Builders LLC v. Riverside Hospitality Group, Mercer County Superior Court, before Judge Vega):

- Plaintiff: Sterling Builders LLC, a New Jersey limited liability company headquartered in Hamilton, NJ. Principal: David Hwang.
- Defendant: Riverside Hospitality Group, Inc., owner-operator of the Riverside Marriott Hotel at 200 River Road, Trenton, NJ.
- Contract: AIA A102 construction contract dated November 8, 2024 for renovation of 84 guest rooms. Total contract value $2,840,000. Substantial completion deadline May 15, 2026.
- Performance: Sterling completed renovations on 71 of 84 rooms by May 15, 2026. The remaining 13 rooms were delayed due to asbestos abatement issues discovered in walls during demolition.
- Payment: Sterling has been paid $2,156,000 to date. Riverside is withholding $684,000 (24% of contract value) citing late performance.
- Dispute: Sterling claims the asbestos was a concealed condition entitling them to an equitable adjustment under §3.7.4 of the contract. Riverside claims Sterling assumed the risk under §3.2.1.
- Filed: Complaint filed April 30, 2026 seeking $684,000 plus pre-judgment interest at 5.25% from May 15, 2026.
- Discovery: Initial conference held June 22, 2026. Discovery cutoff January 15, 2027.
- Lead counsel for plaintiff: Maria Chen, Portnoy Schneck LLC.
""",

    "ip_trade_secret": """\
MATTER FACTS (Docket 2026-CV-09422, NimbusFlow Systems Inc. v. Quentin Hayes, U.S. District Court for the District of New Jersey, before Judge Reyes):

- Plaintiff: NimbusFlow Systems Inc., a Delaware corporation, headquartered in Princeton, NJ. CEO: Dr. Anita Soriano.
- Defendant: Quentin Hayes, a former Senior Solutions Architect at NimbusFlow from January 12, 2022 through March 14, 2026.
- Defendant's new employer (not yet party): Cloudreach Partners, a competitor based in Plano, TX.
- Claims: Misappropriation of trade secrets under the federal Defend Trade Secrets Act (18 U.S.C. § 1836) and the New Jersey Trade Secrets Act (N.J.S.A. § 56:15-1).
- Trade secrets alleged: Customer pricing model (a multi-tiered model NimbusFlow spent approximately $1.4M to develop over 18 months), customer churn-prediction algorithm (proprietary, patent application 18/441,902 pending).
- Evidence of misappropriation: Forensic image of Mr. Hayes's NimbusFlow-issued laptop shows USB device "SAN-128GB-TS" connected on March 11, 2026, transferring 412 files totaling 18.2 GB to that device.
- Damages sought: $4,200,000 in compensatory damages plus injunctive relief and reasonable attorney fees.
- Filed: Complaint filed July 8, 2026. TRO motion filed same day, granted July 9 ex parte. Preliminary injunction hearing scheduled August 5, 2026.
- Lead counsel for plaintiff: Maria Chen, Portnoy Schneck LLC.
""",
}


# ------------------------------------------------------------------
# Question shapes — designed to elicit different output styles, each
# with different hallucination opportunities.
# ------------------------------------------------------------------

QUESTIONS = [
    ("strongest_theory",
     "What is the strongest theory of liability for our client based on the facts as documented, and what evidence supports it?"),
    ("summarize_for_intake",
     "Write a 4-6 sentence summary of this matter that could go on the firm's internal intake form. Keep it neutral and factual."),
    ("discovery_targets",
     "List the specific document categories or witness depositions we should pursue in discovery. Be concrete about WHY each is needed."),
    ("opposing_arguments",
     "What are the strongest counter-arguments the opposing side is likely to raise? For each, briefly explain how we would respond."),
]


def query_psrouter(model: str, system: str, user: str) -> dict:
    body = {
        "model":       model,
        "messages":    [{"role": "system", "content": system},
                        {"role": "user",   "content": user}],
        "temperature": 0.3,
        "max_tokens":  800,
        "stream":      False,
    }
    req = urllib.request.Request(
        PSROUTER,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=240) as r:
        resp = json.loads(r.read())
    ms = (time.time() - t0) * 1000
    return {
        "model":      model,
        "response":   resp["choices"][0]["message"]["content"],
        "tokens_in":  resp.get("usage", {}).get("prompt_tokens"),
        "tokens_out": resp.get("usage", {}).get("completion_tokens"),
        "ms":         ms,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="output directory for fixtures")
    ap.add_argument("--model", default="Legal Generalist", help="psrouter model id")
    ap.add_argument("--limit", type=int, default=999, help="cap on number of fixtures to generate")
    ap.add_argument("--start-num", type=int, default=10, help="starting fixture number")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    pairs = []
    for matter_name, context in MATTERS.items():
        for q_name, q_text in QUESTIONS:
            pairs.append((matter_name, q_name, q_text, context))

    pairs = pairs[: args.limit]
    print(f"Generating {len(pairs)} fixture(s) from psrouter {args.model!r}…")
    print(f"Output directory: {args.out}")
    print()

    n = args.start_num
    for matter, q_name, q_text, context in pairs:
        out_path = os.path.join(args.out, f"{n:02d}-{matter}-{q_name}.json")
        print(f"  [{n:02d}] {matter:18s} / {q_name:20s} … ", end="", flush=True)
        try:
            user_msg = context + "\n\nQUESTION: " + q_text
            r = query_psrouter(args.model, SYSTEM_PROMPT, user_msg)
            print(f"{r['ms']:>6.0f}ms  {r['tokens_in']:>4d}→{r['tokens_out']:>4d} tok")
            fixture = {
                "_comment": (
                    f"REAL psrouter output captured 2026-06-25 from {args.model!r}. "
                    f"Matter type: {matter}. Question shape: {q_name}. Generated by "
                    f"tools/build-calibration-corpus.py for v4 stress-testing."
                ),
                "context": context,
                "output":  r["response"],
                "meta": {
                    "matter":             matter,
                    "question_shape":     q_name,
                    "psrouter_model":     args.model,
                    "psrouter_ms":        r["ms"],
                    "psrouter_tokens_in": r["tokens_in"],
                    "psrouter_tokens_out": r["tokens_out"],
                    "query":              q_text,
                },
                "expected": "TBD — populated by hand after panel run",
            }
            with open(out_path, "w") as f:
                json.dump(fixture, f, indent=2)
        except Exception as e:
            print(f"ERROR: {type(e).__name__}: {e}")
        n += 1

    print()
    print(f"Done. Generated {len(pairs)} fixtures under {args.out}")


if __name__ == "__main__":
    main()
