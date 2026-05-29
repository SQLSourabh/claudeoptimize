---
description: Standalone deep audit of an LLM output — forensics, bias surface, falsifiable improvement plan, continuous-eval loop design
argument-hint: "<path-to-prompt-or-transcript> [path-to-reference-set]"
allowed-tools: Agent, Read, Grep, Glob, Bash(git:*), WebFetch, WebSearch
---

# /llm-audit

Run a single-persona deep audit on the LLM artifact at: **$ARGUMENTS**

This is the standalone entry point for the `llm-researcher-persona`.
For multi-perspective review (e.g., engineering + security + LLM
researcher together), use `/persona-roundtable` instead.

## Phase 1 — Locate the artifacts (orchestrator)

1. Resolve the first argument as a path. Required artifacts:
   - The **prompt** (system + user, or full agent definition).
   - The **output** (model response text, JSON, or transcript).
   If both are not present, list what is missing and stop.
2. Resolve the optional second argument as a **reference / ground-
   truth set**. If absent, note this — the audit can still run, but
   Phase B contrast tests will be HYPOTHESIS rather than CONFIRMED.
3. `Grep` the repo for the prompt's filename to find call sites; this
   tells the researcher how the prompt is actually used in
   production (not just authored in isolation).
4. Write a brief packet at
   `.agents/artifacts/llm-audit-<timestamp>/inputs.md` listing:
   - Prompt path(s) + line counts
   - Output path(s)
   - Reference set path (or "absent")
   - Call sites found via Grep
   - Any agent / hook config that wraps the prompt

## Phase 2 — Dispatch the LLM Researcher

Spawn a single subagent:

```
Agent({
  description: "LLM output forensics + bias map + improvement loop",
  subagent_type: "llm-researcher-persona",
  prompt: "Audit the artifacts listed in
.agents/artifacts/llm-audit-<timestamp>/inputs.md. Run all four
phases (A: forensics, B: bias surface, C: action plan, D: loop
design). Write the full report to
.agents/artifacts/llm-audit-<timestamp>/report.md and the machine-
readable plan to .agents/artifacts/llm-audit-<timestamp>/plan.json.
Adhere to every hard constraint in your persona definition,
including the self-check before returning."
})
```

## Phase 3 — Verify the report (orchestrator)

Before showing the report to the human, the orchestrator verifies:

1. `report.md` exists and is non-empty.
2. Every Phase C STEP has all five required fields (Change,
   Hypothesis, Metric, Baseline, Target, Falsifier, Rollback). Reject
   and re-prompt the persona if any are missing.
3. `plan.json` parses as valid JSON and each step has matching keys.
4. No banned word (hallucinate, biased, drift, misaligned, overfit,
   sycophantic) appears in `report.md` without a citation in the
   same sentence — `Grep` for them and inspect each hit.

If verification fails, send a `SendMessage` follow-up to the
researcher with the specific defects and require a corrected report.

## Phase 4 — Surface to human

Print:
- Path to `report.md`
- The TOP CONCERNS section verbatim
- The first STEP of the action plan, including its falsifier
- Suggested next command:
  - `/llm-audit-apply <plan.json>` to apply STEP 1
  - `/persona-roundtable <prompt-path>` for cross-functional review
  - Or a manual `Edit` of the prompt followed by re-running this
    audit to measure the delta.

## Hard rules

- The orchestrator never edits the prompt itself. The researcher
  produces a plan; the human or a separate implementer agent applies
  it. Audit and apply are deliberately decoupled so the audit stays
  read-only and reproducible.
- The audit artifact directory is the source of truth — do not
  summarize the report into chat in lieu of writing it. Chat output
  must reference paths.
