---
description: Standalone audit of an LLM prompt or output — forensics, bias surface, falsifiable improvement plan, continuous-eval loop design
argument-hint: "<prompt-or-transcript-path> [reference-set-path] [--tier quick|standard|deep]"
allowed-tools: Agent, Read, Grep, Glob, Bash(git:*), WebFetch, WebSearch
---

# /llm-audit

Run a single-persona audit on the LLM artifact at: **$ARGUMENTS**

This is the standalone entry point for the `llm-researcher-persona`.
For multi-perspective review (e.g., engineering + security + LLM
researcher together), use `/persona-roundtable` instead.

## Argument syntax

```
/llm-audit <prompt-or-transcript-path>
           [reference-set-path]
           [--tier quick|standard|deep]
```

The first non-flag argument is the prompt or transcript path. An
optional second non-flag argument is a reference / ground-truth set.
The optional `--tier` flag controls audit rigor.

### Audit-cost tiers

The persona's evidence requirements scale with the tier you pick.
A `quick` audit cannot pretend to be `deep` — the persona enforces
this in its self-check.

| Tier | When to use | Inputs the orchestrator will require | Depth of report |
|---|---|---|---|
| **quick** | Pre-commit smell test before a small change ships. | Prompt + at least 1 representative output; sampling params (temperature, top_p) if available. | Phase A correlational + Phase B HYPOTHESIS-tagged + 1–2 STEPs. No ablations required. |
| **standard** *(default)* | PR-grade audit. Default if no `--tier` given. | Prompt + ≥10 outputs at temp=0 with same params; reference set OR existing eval set; tool roster if agentic. | All phases. Ablation evidence on top 3 drivers. Slice analysis on existing eval if available. |
| **deep** | Pre-production launch; post-incident root-cause; before promoting a prompt change to a high-stakes path. | Standard + ≥150-prompt sized eval set; LLM-judge validation against ≥50 human-labeled gold-set; cost / latency telemetry. | All phases at full rigor. Reproducibility manifest. Per-slice CIs. Distribution-shift baseline established. |

### Tier resolution

1. If `--tier <value>` is present and `value ∈ {quick, standard, deep}`, use it.
2. If `--tier` is given with any other value, abort with the list of valid tiers.
3. If `--tier` is absent, default to **standard**.
4. State the resolved tier at the top of the orchestrator's chat output AND in the report.

### Examples

```
/llm-audit prompts/triage-agent.md
   → tier=standard (default)

/llm-audit prompts/triage-agent.md --tier quick
   → light pre-commit check

/llm-audit prompts/triage-agent.md transcripts/2026-Q2.jsonl --tier deep
   → full rigor; orchestrator will refuse to spawn until inputs
     match the deep tier's requirements

/llm-audit prompts/agent.md --tier flashy
   → ERROR: invalid tier. Valid: quick, standard, deep.
```

## Phase 1 — Locate the artifacts (orchestrator)

1. Parse `$ARGUMENTS` to extract: prompt-path, optional
   reference-set-path, optional `--tier` flag value. Anything
   ambiguous → ask the user.
2. Resolve the prompt path. Required:
   - The **prompt** (system + user, or full agent definition).
   - The **output** (model response text, JSON, or transcript).
   If either is missing, list what is missing and stop.
3. Resolve the optional reference / ground-truth set. If absent,
   note it in `inputs.md` — Phase B contrast tests will run as
   HYPOTHESIS rather than CONFIRMED.
4. **Tier-gating:** check that the inputs match the tier's
   requirements (see the Tiers table). For example:
   - `--tier deep` requires a sized eval set ≥150 prompts AND
     a human-labeled gold-set OR explicit acknowledgment that
     the deep-tier promotion criteria can't be satisfied without
     these.
   - If gated, list the missing inputs and either drop to a lower
     tier (with the user's explicit confirmation) or stop.
5. `Grep` the repo for the prompt's filename to find call sites;
   this tells the researcher how the prompt is actually used in
   production (not just authored in isolation).
6. Write `inputs.md` at `.agents/artifacts/llm-audit-<timestamp>/inputs.md`:
   - Resolved tier
   - Prompt path(s) + line counts
   - Output path(s)
   - Reference set path (or "absent")
   - Eval set path (or "absent")
   - Call sites found via Grep
   - Any agent / hook config that wraps the prompt
   - Reproducibility-manifest fields available (model_id,
     temperature, top_p, seed, tool_roster, rag_corpus) — values
     or "unknown"

## Phase 2 — Dispatch the LLM Researcher

Spawn a single subagent. Pass the tier explicitly so the persona
can apply tier-appropriate evidence requirements.

```
Agent({
  description: "LLM forensics + bias surface + improvement plan",
  subagent_type: "llm-researcher-persona",
  prompt: "AUDIT TIER: <quick|standard|deep>

Audit the artifacts listed in
.agents/artifacts/llm-audit-<timestamp>/inputs.md.

Run all phases (0: reproducibility manifest, A: forensics,
A.1: agentic forensics if multi-turn, B: bias / failure surface,
C: action plan with C.0 manifest + sample-size justification,
D: continuous-improvement loop with D.2 drift monitor).

State the audit tier at the top of report.md. The depth of the
report MUST match the tier — a quick audit may not pretend to be
deep, and a deep audit may not skip rigor required at that tier.

Write the full report to
.agents/artifacts/llm-audit-<timestamp>/report.md, the machine-
readable plan to .agents/artifacts/llm-audit-<timestamp>/plan.json,
and the structured manifest to
.agents/artifacts/llm-audit-<timestamp>/manifest.json.

Adhere to every hard constraint in your persona definition,
including the 16-item self-check before returning."
})
```

## Phase 3 — Verify the report (orchestrator)

Before showing the report to the human, the orchestrator verifies:

1. `report.md` exists, is non-empty, and states the AUDIT TIER at
   the top. The stated tier matches the requested tier (or is
   explicitly downgraded with reason).
2. `manifest.json` parses and contains the Phase 0 fields. Any
   `unknown` field is acknowledged in the report.
3. Every Phase C STEP has all required fields:
   - Change
   - Hypothesis
   - Eval set (with manifest reference)
   - Detectable effect at this N (MDE statement)
   - Metrics tuple: `(quality_metric, tokens_in_avg,
     tokens_out_avg, p50_latency_ms, p95_latency_ms,
     cost_per_call_usd)`
   - LLM-judge integrity block (if a judge is used)
   - Slice analysis (per-slice baselines + targets)
   - Baseline (per-slice + aggregate, with CIs)
   - Target (per-slice + aggregate)
   - Falsifier (with slice-level guardrails)
   - Rollback
   - Alternative hypotheses considered (≥2 with reasons rejected)
   Reject and re-prompt the persona if any field is missing.
4. `plan.json` parses as valid JSON; each step has matching keys.
5. No banned word from the persona's banned list (`hallucinate`,
   `biased`, `drift`, `misaligned`, `overfit`, `sycophantic`,
   `robust`, `aligned`, `performant`, `agentic`, `reliable`,
   `capable`, `intelligent`, `smart`, `dumb`, `confused`, `knows`,
   `understands`, `thinks`) appears in `report.md` without a
   same-sentence citation. `Grep` and inspect each hit.
6. Phase A rows marked HIGH confidence have `Ablation` or
   `LogProb` evidence. If any HIGH row only has `Correlational-only`
   evidence, the orchestrator demands the row be downgraded.
7. Phase B vectors include both refusal-direction calibrations
   (over- and under-cautious) when applicable.
8. If transcripts are multi-turn / agentic, Phase A.1 is present
   with a turn-by-turn causal path.

If verification fails, send a `SendMessage` follow-up to the
researcher with the specific defects and require a corrected
report. Do NOT show the human a report that fails verification.

## Phase 4 — Surface to human

Print:

- Path to `report.md`
- Resolved tier (and any tier downgrade with reason)
- TOP CONCERNS section verbatim (with confidence + alternatives)
- First STEP of the action plan, including its falsifier and
  per-slice guardrails
- Suggested next command:
  - `/llm-audit-apply <plan.json>` to apply STEP 1 (separate
    command; not part of this audit)
  - `/persona-roundtable <prompt-path>` for cross-functional review
  - Or a manual `Edit` of the prompt followed by re-running this
    audit to measure the delta.

## Hard rules

- The orchestrator never edits the prompt itself. The researcher
  produces a plan; the human or a separate implementer applies it.
  Audit and apply are deliberately decoupled so the audit stays
  read-only and reproducible.
- The audit artifact directory is the source of truth — do not
  summarize the report into chat in lieu of writing it. Chat
  output must reference paths.
- Tier integrity: never silently downgrade the tier. If the
  inputs don't support the requested tier, ask the user to either
  provide the missing inputs or explicitly accept a lower tier.
