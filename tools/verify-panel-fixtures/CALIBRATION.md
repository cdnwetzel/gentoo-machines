# verify-panel calibration baseline

Captured 2026-06-24, model `qwen2.5:3b-instruct-q4_K_M`, Ollama on XPS 9510.

The fixtures here are deliberately constructed to exercise specific failure
modes; calibrating against them tells us where each check is reliable, where
it's noisy, and what the recall ceiling looks like on the current verifier.

## v0 — LLM-only panel (entity_fidelity, pii_leak, claim_grounding)

All four fixtures got the correct top-line verdict (PASS/FAIL). But specific-
item recall inside each failure case was imperfect:

| Fixture | What v0 caught | What v0 MISSED |
|---|---|---|
| 01 baseline | n/a (all-pass) | — |
| 02 entity drift | wrong county, wrong rule | **docket digit swap (00847→00874)** |
| 03 PII leak | `{client_name}` placeholder | **`123-45-6789` SSN** *and* **`[ATTORNEY_NAME]` placeholder** |
| 04 hallucinated cite | "Judge Ramirez previously ruled..." | **the entire fabricated `Westfield v. Carter, 891 F.3d 412 (3d Cir. 2018)`** |

The 3B model "smells" trouble (binary verdict reliable) but doesn't enumerate
every offending item. Particularly weak on (a) structurally-shaped patterns
that *look* like normal output to the model (SSN, case citation) and (b) when
multiple ungrounded items are bundled in one paragraph.

## v1 — Hybrid regex + LLM (current)

Added regex prefilters for the structural-pattern checks:

  - `pii_leak`: regex finds candidates (SSN, EIN, phone, email, placeholders,
    debug markers); LLM triages each as real leak vs benign. If regex finds
    zero candidates, LLM is never called.
  - `citation_format`: regex extracts federal-reporter / SCOTUS / F.Supp /
    L.Ed. citations from both OUTPUT and CONTEXT. Any OUTPUT citation absent
    from the CONTEXT set is flagged. No LLM call (legal citations are
    mechanical strings; legitimate paraphrase is essentially nonexistent).

| Fixture | v1 result | Improvement vs v0 |
|---|---|---|
| 01 baseline | PASS ✓ (10.0s; was 14.5s) | regex no-ops faster than LLM "no leaks found" |
| 02 entity drift | FAIL ✓ — caught county, rule (still misses docket digit) | unchanged on this fixture (the gap is semantic, not structural) |
| 03 PII leak | FAIL ✓ — **all 3 leaks caught**: `{client_name}`, `[ATTORNEY_NAME]`, `123-45-6789` | **1 of 3 → 3 of 3** — every leak now caught with reasoned triage |
| 04 hallucinated cite | FAIL ✓ — `citation_format` catches `891 F.3d 412 (3d Cir. 2018)` in 0ms | **0 of 1 → 1 of 1** — the most catastrophic legal hallucination, now perfectly caught |

## Remaining gaps (v1)

`entity_fidelity` is the weakest of the four checks. On fixture 02 it misses
the docket digit swap (`00847` → `00874`); on fixture 04 it doesn't catch the
hallucinated "Third Circuit" entity. These are semantic-recall problems —
the model can read the docket but doesn't reliably compare digit-by-digit.

Likely next moves to close these:
  - Try `qwen2.5:7B-Instruct` (Q4_K_M, ~4.5 GB, fits 3050 Ti VRAM tightly)
    as the verifier model. If recall improves materially, swap default.
  - Decompose entity_fidelity into per-type passes (numbers only / dates only
    / proper-nouns only) so the model's attention isn't split.
  - Add a numeric-exact-match prefilter (find every number in OUTPUT, check
    each against CONTEXT verbatim — same hybrid pattern that worked for PII
    and citations).

## How to re-calibrate

```bash
cd ~/ai/gentoo-machines
for f in tools/verify-panel-fixtures/*.json; do
    echo "=== $(basename "$f") ==="
    python3 tools/verify-panel.py --case "$f"
done
```

Latency on the XPS Ollama (`qwen2.5:3b-instruct-q4_K_M`, RTX 3050 Ti):
- entity_fidelity ~5-10 s (single LLM call, prompt size dependent)
- pii_leak: 0 ms when regex finds nothing; ~500ms × #candidates otherwise
- citation_format: 0 ms (pure regex)
- claim_grounding: ~5-15 s (1 extraction + N judgments)
- Total per fixture: ~10-17 s depending on how much triage runs
