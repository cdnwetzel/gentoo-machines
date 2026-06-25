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

## v1.5 — 7B vs 3B comparison run (2026-06-24)

Pulled `qwen2.5:7b-instruct-q4_K_M` (~4.7 GB) and re-ran all four fixtures
with `VERIFY_MODEL=qwen2.5:7b-instruct-q4_K_M`. Direct A/B against v1 (3B):

| Fixture | Check | 3B (v1) | 7B |
|---|---|---|---|
| 01 baseline | all 4 | PASS, 10s | PASS, **70s** |
| 02 entity drift | entity_fidelity | caught county + rule, **missed docket digit** | **catches all 4 deltas** including docket digit |
| 02 entity drift | claim_grounding | 2 grounded, 1 partial | 3 grounded, 1 ungrounded (sharper) |
| 03 PII | pii_leak | **3/3 leaks caught** | **only 1/3** — SSN + `[ATTORNEY_NAME]` triaged as benign |
| 04 hallucinated cite | entity_fidelity | **passed (false neg on Westfield)** | **catches Westfield + February 2026** |
| 04 hallucinated cite | claim_grounding | caught Ramirez ruling | catches **both** Westfield holding AND Ramirez ruling |

Root causes:

- **7B's semantic-check gains are real**: bigger attention bandwidth lets it
  enumerate every offending item rather than picking the most obvious one
  and moving on. This closes both of v1's open gaps (docket digit drift,
  Westfield-as-entity miss).
- **7B's PII-triage regression is a prompt artifact, not a model truth**:
  the bigger model used its better context-awareness to interpret
  "your SSN on file (123-45-6789)" as ambiguously-attributed and so
  potentially-benign. The triage prompt's "benign vs leak" categories were
  written assuming a naive 3B that flags everything; 7B took the
  context-judgment latitude and over-applied it.
- **7B's 7× latency is largely a CPU-spill artifact**: only 2.7 GB
  resident in VRAM (4 GB total on the 3050 Ti), the rest split to CPU.
  Acceptable for offline validation; would be painful for inline real-time use.

## v2 plan — single-model 7B with tightened PII triage

### Recommendation

**Promote `qwen2.5:7b-instruct-q4_K_M` as the default verifier model. Tighten
the `pii_leak` triage prompt to restore the v1 hybrid's 3/3 PII recall on
fixture 03. Keep `qwen2.5:3b-instruct-q4_K_M` available as a fallback
(both pulled on the box).**

### Why C over A or B

- **A** (`OLLAMA_MAX_LOADED_MODELS=2`, per-check model) — combined ~6.6 GB
  model weight vs 4 GB VRAM forces both models to partially CPU-spill
  on every call. Likely slower overall than C *and* adds per-check model
  plumbing. Net negative.
- **B** (single load slot, swap per check) — each check pays a 10-30s
  swap cost first time per fixture. With 4 checks that's 40-120s *added*
  per fixture. Strictly worse than C.
- **C** (single 7B + tighter triage prompt) — addresses the actual root
  cause (over-permissive triage rules) rather than routing around it with
  model gymnastics. Single model = simplest operational footprint and
  predictable VRAM. The 7× latency vs 3B is acceptable for the validation-
  pipeline use case (we're not running this on every keystroke).

### Plan steps

1. **Tighten `PII_TRIAGE_SYSTEM`** in `tools/verify-panel.py`:
   - Add an explicit meta-rule at the top: *"When uncertain, FLAG. False
     positives are recoverable in human review; missed leaks are not."*
   - Make SSN handling unambiguous: *"Any string matching the NNN-NN-NNNN
     pattern is ALWAYS a leak unless the surrounding text explicitly marks
     it as test/demo/training data (e.g., 'example SSN', 'sample only',
     redacted-with-asterisks form like XXX-XX-NNNN)."*
   - Make unfilled placeholder handling unambiguous: *"Any literal
     `{...}`, `[ALLCAPS_NAME]`, or `<ALLCAPS_NAME>` in client-facing
     content is ALWAYS an unfilled placeholder leak, regardless of how
     the surrounding text reads."*
   - Keep the firm-signature carve-out for phone/email — those still
     benefit from context.

2. **Change the default `VERIFY_MODEL`** in `verify-panel.py` from
   `qwen2.5:3b-instruct-q4_K_M` to `qwen2.5:7b-instruct-q4_K_M`. Keep it
   env-overridable so 3B is still one env var away.

3. **Re-run all four fixtures** with the new prompt + 7B model.
   Acceptance criteria:
   - Fixture 03 `pii_leak`: catches all 3 (`{client_name}`,
     `[ATTORNEY_NAME]`, `123-45-6789`). Same 3/3 recall as v1 hybrid.
   - Fixture 04 `entity_fidelity`: still catches Westfield + February
     2026 (no regression from 7B baseline).
   - Fixture 02 `entity_fidelity`: still catches docket digit swap (no
     regression).
   - Fixture 01: still PASS (no false positive introduced).
   - Latencies broadly comparable to the 7B baseline (~70s per fixture);
     no surprising slowdowns.

4. **If acceptance criteria fail**: fall back to Option B (model per
   check) — use 7B for the semantic checks (`entity_fidelity`,
   `claim_grounding`) and 3B for `pii_leak` triage. Pay the swap cost
   once per panel run. Document the decision in this file.

5. **Update Ollama service config** (`machines/xps-9510/ollama.confd`):
   - Keep `OLLAMA_MAX_LOADED_MODELS=1` (default — letting Ollama evict
     and reload as needed; both models fit on disk, only one in VRAM
     at a time).
   - Consider raising `OLLAMA_KEEP_ALIVE` from `24h` → `168h` so the 7B
     model doesn't get evicted by an inactivity timer mid-week. Decide
     after observing real usage.

6. **Update `CALIBRATION.md`** with v2 results (this section will become
   the v1.5 baseline; a new "v2" section will record what happened).

7. **Commit + push** the verify-panel.py changes, the updated CALIBRATION.md,
   and a one-line note in `machines/xps-9510/HARDWARE.md` AI verifier
   section that the default model is now 7B.

### Rollback

One env-var revert: `VERIFY_MODEL=qwen2.5:3b-instruct-q4_K_M` returns to
v1 behavior. The 3B model stays pulled on the box; no infrastructure
change needed.

## v2 — landed 2026-06-25

Three changes:

1. Default `VERIFY_MODEL` → `qwen2.5:7b-instruct-q4_K_M`.
2. `PII_TRIAGE_SYSTEM` rewritten with explicit ALWAYS-FLAG categories
   (SSN, placeholders, debug markers, credit-card-shaped) and a
   meta-rule "when uncertain, FLAG."
3. `check_entity_fidelity` computes verdict from entity statuses instead
   of trusting the model's `verdict` field. Brings entity_fidelity into
   line with pii_leak and claim_grounding, which already do this. Fixes
   a structural-JSON failure mode where 7B places `verdict` inside the
   last entity object instead of at the top level (parses OK but lacks
   the top-level key).

### Acceptance criteria — all met

| Criterion | Result |
|---|---|
| Fixture 01: PASS, no false positives | ✅ PASS (62s) |
| Fixture 02 `entity_fidelity`: catches docket digit | ✅ FAIL with docket 00847 marked partial vs 00874, county ungrounded, rule partial — all expected drifts caught |
| Fixture 03 `pii_leak`: 3/3 leaks | ✅ FAIL with all 3 flagged: `{client_name}`, `[ATTORNEY_NAME]` ("ALWAYS-FLAG category"), SSN ("SSN-shaped string in client-facing content without explicit marking as test/demo") |
| Fixture 04 `entity_fidelity`: Westfield + Feb 2026 | ✅ FAIL with both caught; citation_format also catches via regex |

### v2 measured latency (RTX 3050 Ti, 7B partially CPU-spilled)

| Fixture | v2 total | v1 (3B) | factor |
|---|---|---|---|
| 01 baseline      |  62 s | 10 s | 6.2× |
| 02 entity drift  |  60 s | 12 s | 5.0× |
| 03 PII           |  65 s | 13 s | 5.0× |
| 04 hallucinated  |  78 s | 17 s | 4.6× |
| **full battery** | **265 s** (~4.4 min) | ~52 s | ~5× |

Acceptable for offline validation pipelines (not inline-real-time use).

### Remaining noise (not blocking)

- Fixture 02 entity_fidelity raises a `Smith v. Acme Corp.` false-positive
  because CONTEXT has a trailing comma after the case name and OUTPUT
  doesn't. Doesn't change the verdict (FAIL is correct anyway); minor
  noise in the per-entity list.
- One `evidence` value in fixture 02's output retains a stray `}` from
  the model's malformed-JSON moment. Cosmetic; ignored by code now that
  verdict is computed from statuses.

## v3 — real psrouter outputs (2026-06-25) — synthetic confidence was misleading

Ran the panel against two real psrouter responses to the same employment-
matter prompt:
  - `Legal Generalist` (spark2 32B) — 22s response, 265 tokens out
  - `PS-Legal-72B` (spark1 72B) — 115s response, 362 tokens out

Both outputs are realistic legal prose: the model reasons about retaliation
vs gender-discrimination theories of liability, cites the matter facts, and
adds legal doctrine (temporal proximity, pretext) not in the CONTEXT. No
fabricated case law in either response. Both expand "Title VII" to
"Title VII of the Civil Rights Act of 1964" — the canonical hallucination
to catch.

Fixtures saved at `verify-panel-fixtures/real-psrouter/`.

### The findings

**1. The 7B verifier is non-deterministic on real prose.** Two runs of the
same fixtures produced different verdicts at the entity-fidelity level:

| Fixture | Run 1 entity_fidelity | Run 2 entity_fidelity |
|---|---|---|
| 32B output | FAIL — `June 3, 2019` partial (false positive) | PASS — no findings |
| 72B output | FAIL — `April 17, 2026`, `$4,200` (both false positives) | FAIL — caught Civil Rights Act of 1964 ✓, plus 4 more false positives |

`temperature=0.0` in the request notwithstanding, Ollama / CUDA sampling
isn't fully deterministic. Same input, different output.

**2. False-positive rate is high on real prose.** Entities that appear
verbatim in CONTEXT get flagged as ungrounded or partial when the
verifier loses track of which surrounding text supports them:
  - `April 17, 2026` — in CONTEXT ("Ms. Carter was terminated on
    April 17, 2026"), flagged ungrounded
  - `$78,400 annual salary` — in CONTEXT verbatim, flagged ungrounded
  - `$4,200` — in CONTEXT verbatim ("year-end bonus of $4,200"),
    flagged partial because the surrounding sentence is rephrased
  - `June 3, 2019` — in CONTEXT verbatim, flagged partial

The verifier extracts the entity correctly but matches it against the
wrong section of CONTEXT, then concludes "not in context" or "different".
On clearly-distorted entities the synthetic fixtures used (`docket 00874`
vs `00847`, `Hunterdon` vs `Mercer County`), this didn't happen because
the distortion was structural — every appearance in OUTPUT was the wrong
form. On natural prose with one mention in OUTPUT and a more elaborate
phrasing in CONTEXT, the model gets confused.

**3. `claim_grounding` is too lenient on real prose.** Both runs of both
fixtures returned "7 grounded, 0 partial, 0 ungrounded" — including the
Civil Rights Act of 1964 expansion. The 2-call decomposition (extract
claims → judge each) didn't help because the model's judgments are
liberal: it sees Title VII in CONTEXT, sees Title VII in the claim, and
calls the whole claim grounded even when the claim adds "Civil Rights
Act of 1964" — content not in CONTEXT.

**4. Pure-regex checks were the only reliable ones.** Across both runs
of both fixtures, `pii_leak` (regex prefilter) and `citation_format`
(pure regex) behaved consistently and correctly. The hybrid pattern is
robust; the pure-LLM patterns are not.

### What this means for the use case

The panel is **not** ready as a pre-send check on real iChris drafts. The
false-positive rate on natural prose would have humans dismissing too
many alarms; the false-negative rate on subtle expansions (Civil Rights
Act, doctrine additions) means real hallucinations would still slip.
Combined with non-determinism, the same draft could be cleared one
moment and rejected the next.

Where it IS ready:
  - `pii_leak` — structural patterns, reliable across runs.
  - `citation_format` — fabricated federal/SCOTUS citations get caught
    deterministically because the regex enumerates citations and set-
    compares against CONTEXT. No model involvement.

### Required improvements before this is production-trustworthy

In rough priority order:

  1. **Multi-sample voting** for the LLM checks. Run each LLM call 3 or 5
     times with explicit-different temperatures or seeds, majority-vote
     on the verdict. Trades latency for reliability. With the panel
     already at ~80s per fixture, this is the most expensive but most
     impactful change.

  2. **Numeric-fidelity regex prefilter**. Same pattern as `pii_leak` and
     `citation_format`: extract every number / dollar amount / docket /
     date from OUTPUT via regex, check each against CONTEXT verbatim.
     This catches the entity-drift cases (docket digit swap, $-amount
     drift) *deterministically* and removes them from the LLM's load.
     The LLM check is then narrower (named entities + paraphrased
     references) which it handles more reliably.

  3. **Tighten `claim_grounding` prompt with explicit examples** of
     subtle expansions that should fail (Title VII → Title VII of the
     Civil Rights Act of 1964 should be flagged as adding ungrounded
     content). Few-shot examples may be necessary; 7B's zero-shot
     judgment on these is too liberal.

  4. **Improve entity_fidelity context-matching**. Either decompose
     (one call per entity, with the entity quoted and the full CONTEXT
     in scope), or post-process model output by doing a string-grep
     of each extracted entity against CONTEXT before trusting the
     model's "ungrounded" call.

  5. **Try a stronger judge model**. The firm's `Legal Generalist`
     (32B) or `PS-Legal-72B` via psrouter are accessible from the
     XPS while it's in office; using them as the verifier judge
     (not just the thing being verified) is a different architecture
     but may be the right move for this domain. Calibration cost
     would be substantial — likely a full re-pass of the fixture set
     with the new judge.

### Conclusion

Real-world testing did what synthetic-fixture testing could not: it
revealed the failure modes that matter in production. Pure-regex checks
work. LLM-driven semantic checks (entity_fidelity, claim_grounding) on
the 7B verifier are not yet trustworthy on natural legal prose. The
required improvements are concrete and prioritized but represent real
work — not a one-prompt tweak.

The panel as it stands today is useful for:
  - Catching unfilled placeholders (pii_leak)
  - Catching fabricated federal/SCOTUS citations (citation_format)
  - Spot-checking drafts where consistent false-positive noise is
    tolerable for human review

It is NOT yet useful for:
  - Automated gating of iChris-style draft pipelines
  - High-precision grounding checks where a single false positive
    is expensive (human-review fatigue)
  - Catching subtle expansions ("Title VII" → "Title VII of the
    Civil Rights Act of 1964") that human reviewers would otherwise
    miss

### Next experiments (deprioritized — addressed in v3 findings above)

- Inline streaming mode — premature; the panel isn't accurate enough yet
  to be worth running inline.

## v4 — landed 2026-06-25

All five v3-identified improvements implemented in `verify-panel.py`. Order
of priority matches the v3 plan section.

### #1 — Multi-sample voting (env-gated)

New env var `VERIFY_VOTES` (default `1`). When > 1:
- `entity_fidelity` runs its extraction call N times, then aggregates with
  `_vote_on_entities()`: keep only findings appearing in ≥ majority of runs,
  take majority status, attach a `votes` field showing agreement count.
- `claim_grounding` extracts claims once (extraction is comparatively
  stable; the volatile step is judgment) and judges each claim N times
  via `_judge_one_claim()`, taking majority status per claim.

Costs N× LLM latency. Default 1 preserves the v3 fast path; set
`VERIFY_VOTES=3` for the reliability mode.

### #2 — Numeric-fidelity regex prefilter

New check `numeric_fidelity`. Same hybrid pattern as `pii_leak` and
`citation_format`: regex extracts every currency amount, date (long-form,
ISO, slash), docket, comma-grouped number, and 4-digit year from OUTPUT,
set-compares (after normalization) against the same regex run on CONTEXT.

Verified end-to-end on fixture 05 (`Legal Generalist`): catches `1964`
deterministically — that's the year embedded in "Title VII of the Civil
Rights Act of 1964" which CONTEXT doesn't contain. Same catch on fixture
06 (`PS-Legal-72B`).

Cleared the entire class of v3 false positives on grounded numbers
(`April 17, 2026`, `$78,400`, `$4,200`, `June 3, 2019`) — they're now
verbatim-matched in the regex step rather than judged by the LLM at all.

### #3 — Few-shot examples in `JUDGE_CLAIM_SYSTEM`

Five explicit examples added to the claim-grounding judge prompt covering:
  - **Example 1** — *expansion ungrounded*: "Title VII" → "Title VII of
    the Civil Rights Act of 1964" must be `ungrounded`, with an explicit
    note that the expansion being TRUE in the real world doesn't make it
    grounded
  - **Example 2** — *trivial rewording grounded* (same date, added "on")
  - **Example 3** — *doctrine framework ungrounded* (adding "McDonnell
    Douglas burden-shifting" to a fact pattern that didn't mention it)
  - **Example 4** — *detail drift partial* (salary $78,400 → $78,500)
  - **Example 5** — *new citation ungrounded* (`Westfield v. Carter` not
    in CONTEXT)

Plus a META-RULE at the top: *"When the CLAIM adds detail not in the
CONTEXT, the answer is NOT 'grounded' — even if the added detail is true
in the real world."*

### #4 — Verbatim string-grep override on `entity_fidelity`

`check_entity_fidelity` now post-processes the LLM's per-entity statuses:
for any entity the LLM marked `ungrounded` or `partial`, run
`_appears_verbatim()` against CONTEXT (lightly normalized). If the entity
text literally appears in CONTEXT, override the LLM's status to
`grounded` and record the override.

Result: real-prose false positives (April 17 2026, $78,400, $4,200, June
3 2019) — all in CONTEXT verbatim — are no longer flagged. The LLM is
treated as a high-recall extractor; the verbatim match is the precision
filter.

### #5 — psrouter as judge (alternative backend)

New env vars `JUDGE_BACKEND` (`ollama` | `openai-compat`),
`JUDGE_BASE_URL`, `JUDGE_MODEL`. When `JUDGE_BACKEND=openai-compat`,
the LLM dispatcher calls a `/v1/chat/completions` endpoint with
`response_format={"type": "json_object"}` — works with psrouter (vLLM
backend) and any other OpenAI-compatible server.

Verified end-to-end:

```bash
JUDGE_BACKEND=openai-compat \
JUDGE_BASE_URL=http://192.168.111.162:8888 \
JUDGE_MODEL="Legal Generalist" \
python3 tools/verify-panel.py --case <fixture>
```

On a "Title VII → Civil Rights Act of 1964" test claim, `Legal Generalist`
(spark2 32B) returned `status: ungrounded` with evidence *"The CONTEXT
mentions 'Title VII' but not the expansion to 'Civil Rights Act of 1964'."*
— it picked up the few-shot pattern and applied it correctly. ~6.8s per
judgment vs ~30-50s for 7B local (32B fully on the firm's GPU pool vs
7B partially CPU-spilled on the XPS).

### How to drive v4

Default (everything off, fastest):
```bash
python3 tools/verify-panel.py --case <fixture>
```

Reliability mode (multi-sample voting):
```bash
VERIFY_VOTES=3 python3 tools/verify-panel.py --case <fixture>
```

psrouter judge mode (faster + domain-tuned):
```bash
JUDGE_BACKEND=openai-compat JUDGE_BASE_URL=http://192.168.111.162:8888 \
    JUDGE_MODEL="Legal Generalist" python3 tools/verify-panel.py --case <fixture>
```

Combine all three for the strongest configuration (high reliability +
psrouter judge):
```bash
VERIFY_VOTES=3 JUDGE_BACKEND=openai-compat \
JUDGE_BASE_URL=http://192.168.111.162:8888 \
JUDGE_MODEL="Legal Generalist" \
    python3 tools/verify-panel.py --case <fixture>
```

### What v4 changes about production-readiness

The two structural failure modes from v3 (false positives on grounded
numbers/entities, missed subtle expansions in claim grounding) are
addressed by deterministic regex-based checks and few-shot prompting
respectively. Non-determinism is addressed by an opt-in voting mode
that trades latency for reliability.

The panel is now at a point where it could plausibly gate a sampling-
based human-review pipeline (run on a percentage of drafts, surface
the high-confidence ungroundings) without unacceptable false-positive
fatigue. Inline real-time gating still depends on per-call latency
budget — for that use case, `VERIFY_VOTES=1` and a faster judge model
(psrouter Legal Generalist or 3B local) keeps the panel under ~15s per
draft.

Remaining work belongs to a different category — operational:
  - Build a calibration corpus from real (anonymized) draft logs, not
    just synthetic + one-shot psrouter outputs
  - Track per-check accuracy over time as model versions / fine-tunes change
  - Decide on a deployment surface (CLI tool? inline before draft commit?
    sampling cron?)

### Head-to-head on fixture 06 (`PS-Legal-72B` employment-matter output)

claim_grounding only, three v4 configurations:

| Config | Verdict | Findings | Latency |
|---|---|---|---|
| v4 default (just the new few-shot prompt) | FAIL | 4 grounded, **3 ungrounded** — Civil Rights Act of 1964, "temporal proximity" doctrine framework, "gender as factor" inference | 49 s |
| v4 + `VERIFY_VOTES=3` | FAIL | Same 4/3 split, with vote agreement noted per judgment | 109 s (2.2×) |
| v4 + psrouter `Legal Generalist` as judge | FAIL | 5 grounded, **1 ungrounded** — only catches Civil Rights Act; misses doctrine + inference. Evidence text exemplary — cites Example 1 from the prompt | 43 s |

Three real findings:

1. **The few-shot prompt is the highest-impact change.** Single-sample v4
   with the new prompt catches all three subtle expansions; v3 caught none.
2. **Voting was redundant here** — same verdict, 2.2× latency. The few-shot
   prompt is stable enough that single-sample is reliable. Voting still
   matters on noisier prompts; not a free pass to always-on.
3. **Legal Generalist trades speed + evidence quality for leniency.**
   Faster than 7B local on this fixture (43s vs 49s — 32B on a real GPU
   pool beats 7B partially CPU-spilled on a laptop), evidence text is
   exemplary (cites the few-shot rule verbatim), but misses the
   temporal-proximity doctrine and "gender as factor" expansions.
   A legal-tuned model sees doctrine as implicit-from-facts rather than
   as an addition — domain fluency vs conservative grounding tradeoff.

For the firm's use case (catching hallucinations is paramount), 7B local
is the more conservative choice. For latency-sensitive sampling work,
Legal Generalist is interesting. Voting is the dial to turn when a
specific prompt is observed to be unreliable on a specific content type.

## v5 — operational: calibration corpus + stats + deployment decision

### Calibration corpus

`tools/build-calibration-corpus.py` generates a meaningful-volume real-prose
corpus by querying psrouter with varied legal-domain prompts. Default run
covers 3 matter types (employment, contract, IP trade secret) × 4 question
shapes (strongest theory, intake summary, discovery targets, opposing
arguments) = 12 fixtures, captured under `real-psrouter/10-…21-…json`.

The matter contexts are synthetic but realistic — rich varied concrete
entities (specific docket numbers, parties, dates, dollar amounts, judges,
contracts referenced by section) so the panel has meaningful grounding to
stress-test against.

```bash
tools/build-calibration-corpus.py \
    --out tools/verify-panel-fixtures/real-psrouter/ \
    --model "Legal Generalist"
```

The 2026-06-25 batch is the v5 baseline. Each fixture's `meta` field
records the matter type and question shape so future runs can be
slice-and-diced by content category.

### Stats logging

`tools/verify-panel.py` now accepts `--stats-log <path>` (or the
`VERIFY_STATS_LOG` env var). Each run appends one JSON line with:
timestamp, fixture, config (model/backend/votes), per-check verdicts,
latencies, finding counts, and override counts.

`tools/panel-stats.py` reads the log and prints aggregates: overall
panel pass rate, per-check pass rate + mean latency + mean findings,
per-fixture breakdown, per-model/backend breakdown, and a drift signal
that splits the run history at the midpoint to surface trends.

```bash
# Baseline run on the whole corpus
tools/run-calibration-batch.sh tools/verify-panel-stats/runs.jsonl

# Summary
tools/panel-stats.py tools/verify-panel-stats/runs.jsonl --by-fixture
```

The stats directory is gitignored — these accumulate over time and
shouldn't pollute commit history. The summary tool is what survives.

### Deployment surface

The deployment decision lives in `DEPLOYMENT.md` next to this file. Short
version: **CLI tool (already shipped) + nightly sampling cron (to build).
NOT inline real-time gating** — latency makes inline impractical today,
and the false-positive cost in a blocking context is too high.

See DEPLOYMENT.md for the rationale, cron design, alerting thresholds, and
the "what's deferred" list.

## How to re-calibrate

```bash
cd ~/ai/gentoo-machines
for f in tools/verify-panel-fixtures/*.json; do
    [ "$f" = "tools/verify-panel-fixtures/CALIBRATION.md" ] && continue
    echo "=== $(basename "$f") ==="
    python3 tools/verify-panel.py --case "$f"
done
# A/B against the other model:
VERIFY_MODEL=qwen2.5:3b-instruct-q4_K_M python3 tools/verify-panel.py --case <fixture>
```

Latency on the XPS Ollama (RTX 3050 Ti, 4 GB VRAM):

| Check | qwen2.5:3b (1.9 GB on disk, fits VRAM) | qwen2.5:7b (4.7 GB on disk, partial CPU spill) |
|---|---|---|
| entity_fidelity | 5-10 s | 40-50 s |
| pii_leak | 0 ms (regex no-op) or 0.5-2 s (triage) | 0 ms or 2-6 s |
| citation_format | 0 ms (pure regex) | 0 ms (pure regex) |
| claim_grounding | 5-15 s | 20-30 s |
| **per fixture** | **~10-17 s** | **~60-75 s** |
