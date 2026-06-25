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

1. **Latency.** Default v4 config is 50-100s per panel run on 7B local
   (60-80s typical, up to 109s with `VERIFY_VOTES=3`). Even with
   psrouter `Legal Generalist` as judge (~43s), this is far above the
   "draft a reply, hit send" interaction budget. Blocking a paralegal
   for ~1 minute per send would be a usability regression.

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
