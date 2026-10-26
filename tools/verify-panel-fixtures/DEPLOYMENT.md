# verify-panel — deployment surface decision

This file records the deployment decision for the verify-panel tool as of
the v4 calibration baseline. It exists separately from CALIBRATION.md
because deployment decisions are operational and have different revision
cadence than the algorithmic calibration history.

## Decision (2026-06-25)

**The panel ships as a CLI tool (already done) plus a nightly sampling
cron (to be built). Inline real-time pre-send gating is NOT in scope yet.**

```
                         ┌─────────────────────────────┐
                         │  CLI: tools/verify-panel.py │  ← already shipped
                         │  one-off, scriptable        │     used ad-hoc + by
                         │                             │     other automation
                         └─────────────────────────────┘
                                       │
                                       │ subprocess invocation
                                       ▼
            ┌─────────────────────────────────────────────────┐
            │  Nightly sampling cron (to be added)            │
            │  • 3 AM daily                                   │
            │  • iterates over drafts produced in last 24h    │
            │  • appends to verify-panel-stats/runs.jsonl     │
            │  • writes a daily report; alerts on high-       │
            │    confidence ungroundings (numeric_fidelity,   │
            │    citation_format catches)                     │
            └─────────────────────────────────────────────────┘
```

## Why this surface and not inline

**Inline pre-send gating is out of scope today.** Two reasons:

1. **Latency.** Measured 108 s mean per fixture across the 14-fixture
   v5 baseline corpus (range 54-174 s, mostly 100-145 s). `claim_grounding`
   alone averages 59 s; `entity_fidelity` 49 s. The pure-regex checks
   (citation_format, numeric_fidelity, pii_leak) contribute ~0 ms. Even
   with psrouter `Legal Generalist` as judge (~43 s on the demo), this
   is far above the "draft a reply, hit send" interaction budget.
   Blocking a paralegal for ~2 minutes per send would be a usability
   regression.

2. **False-positive cost in a blocking context.** v4 dramatically
   reduced FP rate vs v3, but the panel still produces some — and an
   inline blocker turns every FP into a "why can't I send this?"
   support call. Cost-of-FP is much higher in inline than in sampling.

A sampling cron amortizes both costs:
- Latency: 50-100s per draft × N drafts = several minutes, run overnight.
  No user-perceived delay.
- FP cost: surfaces in a morning report that a human reviews. False
  positive ≈ "this looked fine on review", not "I can't send my reply".

## Cron design

**Frequency**: nightly at 3 AM (after the firm's iChris poller has
processed the day's drafts).

**Sample shape**: all drafts produced in the prior 24 hours.

**Per-draft invocation**:
```bash
tools/verify-panel.py --case <draft.json> \
    --stats-log /var/log/verify-panel/runs.jsonl
```

**Output**: a daily report written to `/var/log/verify-panel/daily/<date>.md`
with:
- Drafts processed (count + total latency)
- Findings by check (entity_fidelity / pii_leak / citation_format /
  numeric_fidelity / claim_grounding)
- Highest-confidence ungroundings surfaced for human review
  (e.g. citation_format hits, since those are pure-regex and have
  near-zero false-positive risk)

**Alerting**: a separate small wrapper (e.g.
`tools/verify-panel-alert.sh`) parses the daily report and sends an
email or ntfy push when:
- Any `citation_format` finding (these are deterministically
  hallucinated authority — high precision, immediate review needed)
- More than 3 distinct ungroundings across drafts (cluster signal —
  the upstream model may have drifted)
- Panel error rate > 10% in a single day (verifier infrastructure
  problem; alarm regardless of content)

**Stats log**: all runs append to `verify-panel-stats/runs.jsonl`.
`tools/panel-stats.py` reads it for accuracy and drift analysis.

## v5 baseline — empirical numbers from the 14-fixture corpus run (2026-06-25)

First run of `tools/run-calibration-batch.sh` against the freshly-built
real-psrouter corpus, default v4 config (qwen2.5:7b-instruct-q4_K_M local,
no voting). Reproducible with `tools/panel-stats.py
tools/verify-panel-stats/runs.jsonl --by-fixture --by-model`.

### Per-check reliability

| Check | Pass rate | Mean latency | Notes |
|---|---|---|---|
| citation_format | 100.0% | 0 ms | Pure regex — no findings on this corpus |
| pii_leak | 100.0% | 0 ms | No PII patterns in psrouter outputs |
| numeric_fidelity | 78.6% | 0 ms | 3 fixtures caught hallucinated numbers (mostly "1964" from Civil Rights Act expansion) |
| entity_fidelity | 78.6% | 49 s | 15 verbatim-overrides fired across 14 runs — v4 fix preventing the v3 false-positive class |
| claim_grounding | 14.3% | 59 s | Catches the doctrine additions (temporal proximity, McDonnell Douglas burden-shifting, statute expansions) every real model output drifts into |

### Panel-level metrics

- Total wall time: 27 min for 14 fixtures
- Mean per-fixture latency: 108 s (range 54-174 s)
- All 14 fixtures: FAIL — expected because every real psrouter answer adds
  some legal doctrine or expansion beyond the bare matter facts. The
  interesting question is *which* checks fail, not whether any do.
- Failure surface is narrow: 11/14 corpus fixtures fail on exactly ONE
  check (vs 2-3 on the v3-baseline fixtures), suggesting v4 converged the
  panel's signal rather than spraying noise.

### What this means for the cron design

- Throughput planning: at 108 s/draft, a nightly run can process roughly
  N drafts in N×108 s. At 50 drafts/day that's 90 min nightly; at 200
  drafts it's 6 hours. **If draft volume exceeds ~100/day, parallelize**
  the batch runner (Ollama's `OLLAMA_NUM_PARALLEL=2` permits two
  concurrent panels at the cost of extra VRAM pressure).
- Alerting priority: `citation_format` findings remain the highest-value
  signal (deterministic, near-zero FP). `numeric_fidelity` is similarly
  deterministic but lower precision (it flags any number not in CONTEXT
  including new years that may be benign — see "1964" pattern). LLM-driven
  checks need human-review pairing before automated alerts.
- Stats log will accumulate ~500 bytes per draft. At 50 drafts/day = 25KB/day
  = 9MB/year. JSONL stays usable for years without rotation.

### Caveats for this baseline

- All-fail is **content-driven**, not a v4 quality issue. Every prompt
  in the corpus was designed to give the model room to add doctrine; the
  panel correctly flags that.
- No human-labeled ground truth yet. "Pass rate" is the panel's verdict
  rate, not its accuracy against human review. Building that ground truth
  is the next operational step (sample 20-30 panel findings, classify
  each as TRUE or FALSE positive, recompute per-check precision).
- Drift signal (first 7 vs last 7 runs) shows content-driven variation
  (employment vs IP outputs have different hallucination patterns), not
  model drift. Becomes meaningful when the *same* fixtures run repeatedly
  over time.

## What's deferred (will revisit)

- **Inline pre-send gate**. Becomes interesting if all three hold:
  1. Per-draft latency drops below ~15s (e.g. via a smaller judge model,
     reduced check set, parallel-fan-out of LLM calls).
  2. False-positive rate drops below ~2% on real production drafts
     (currently unknown — that's what the calibration corpus and
     sampling cron will measure over time).
  3. A clear UI integration path exists (Outlook add-in? Monday board
     hook?).

- **Per-tenant policy** (different checks active for different work types).
  Out of scope for a single-firm deployment; would matter at multi-firm scale.

- **Active learning loop** — flag drafts the panel marked "fail" but
  human review later marked "actually fine", retrain or re-prompt to
  reduce that class of FP. Requires the sampling cron + human-review
  workflow to exist first.

## Decision retrieval

When revisiting this decision, the relevant artifacts are:
- This file (the decision + rationale)
- `tools/verify-panel-fixtures/CALIBRATION.md` (algorithm decisions
  v0 → v4 and the calibration numbers that justify them)
- `verify-panel-stats/runs.jsonl` (empirical data once the cron is live)
- `tools/panel-stats.py` (analysis tool)

Decision change-criteria: meaningful new data (production drift,
material false-positive rate, a UX integration that makes inline
practical), or change in the upstream firm AI stack (different
psrouter models, different draft pipeline).
