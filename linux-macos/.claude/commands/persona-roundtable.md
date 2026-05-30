---
description: Run a multi-persona roundtable review of the current codebase or change
argument-hint: "<topic or path or PR ref>"
allowed-tools: Agent, Read, Grep, Glob, Bash(git:*)
---

# /persona-roundtable

Run a structured, evidence-grounded roundtable on: **$ARGUMENTS**

## Phase 1 — Establish shared facts (you, the orchestrator, do this first)

Before spawning any persona, gather the ground truth they will all
review. No persona is allowed to invent facts; they all read from the
same evidence packet.

1. If $ARGUMENTS looks like a path or glob, `Read` / `Grep` it.
2. If it looks like a git ref, run `git diff <ref>` and `git log <ref>`.
3. Otherwise, do a focused codebase survey relevant to the topic.
4. Write the evidence packet to
   `.agents/artifacts/roundtable-<timestamp>/facts.md` with:
   - Files in scope (paths + line counts)
   - Key code excerpts (with `file:line` citations)
   - Build / test status (commands run, exit codes)
   - Known constraints from `CLAUDE.md`

## Phase 2 — Dispatch personas in parallel

Spawn these subagents **in a single message with multiple Agent tool
calls** so they run concurrently. Each gets the path to `facts.md` and
is told: *"You may only cite from facts.md or from files you Read
yourself. No speculation."*

| Persona | Subagent type | Lens |
|---|---|---|
| CEO | ceo-persona | Strategic fit, opportunity cost, market risk |
| CFO | cfo-persona | Cost (compute, headcount, vendor), ROI, runway impact |
| CTO / CIO | cto-persona | Architecture, tech debt, platform alignment |
| Project Manager | pm-persona | Scope, schedule, dependencies, RAID log |
| Staff Software Engineer | software-engineer-persona | Code correctness, consistency with established patterns, test quality, maintainability |
| Independent Code Reviewer | general-purpose | Second-opinion code review (cross-checks the Staff Engineer persona) — see prompt template below |
| Security Engineer | general-purpose | Authn/z, injection, data exposure, secrets — see prompt template below |
| QA Lead | qa-persona | Test coverage, edge cases, regression risk |
| ML/AI LLM Researcher | llm-researcher-persona | Output forensics, prompt bias surface, eval-loop design (use whenever scope involves an LLM prompt, agent, or model output) |
| DevOps / SRE | devops-sre-persona | Deploy story, rollback, observability, on-call burden (use whenever scope touches infra, deploy, or release-impacting code) |
| Data Engineer | data-engineer-persona | Schema migrations, idempotency, lineage, replay, data quality (use whenever scope touches DB / ETL / events / pipelines) |
| UX / Copy | ux-copy-persona | Error messages, naming consistency, empty states, microcopy, code-observable a11y (use whenever scope touches user-facing surface) |
| Compliance / Privacy | compliance-privacy-persona | Data classification, retention, consent, audit trail, cross-border flows (use whenever scope touches user data) |
| API Steward | api-steward-persona | Versioning, deprecations, backward compatibility, contract stability (use whenever scope touches a public API, library export, CLI flag, config key, or event schema) |

### Prompt template — Independent Code Reviewer (general-purpose)

```
You are an independent staff-level code reviewer. Your only goal is
to second-guess another reviewer who has already audited this change
(the Staff Software Engineer persona). Read facts.md at <path>, then
read the changed files yourself.

Hard rules:
- Cite every claim with file:line.
- Label every claim FACT / INFERENCE / OPINION.
- Banned phrasings without a same-sentence citation: cleaner,
  idiomatic, best practice, code smell, anti-pattern, over-engineered.
- If you agree with the Staff Engineer persona's verdict on a point,
  say so explicitly — do not pad the report.
- Surface anything they missed: subtle correctness bugs, untested
  branches, brittle mocks, API contract changes that ripple.

Return the same schema as the Staff Engineer persona, but add a
section AGREEMENT-WITH-STAFF-ENG listing each of their TOP CONCERNS
and whether you concur, with one-line reason.
```

### Prompt template — Security Engineer (general-purpose)

```
You are a security engineer reviewing this change for vulnerabilities.
Read facts.md at <path>, then read the changed files yourself.

Scan, in priority order:
1. Authentication — new endpoints, token handling, session lifecycle.
2. Authorization — permission checks present at every boundary.
3. Injection — SQL, command, template, LDAP, XPath, deserialization.
4. Data exposure — logging of secrets/PII, error messages leaking
   internal state, response payloads with too much detail.
5. Crypto — algorithms used, key handling, randomness sources.
6. Multi-tenant isolation (if applicable) — tenant ID threaded
   through all queries; cite call sites.
7. Dependency risk — new third-party libs; check lockfile diffs.
8. Secret hygiene — hard-coded keys, .env in commits, tokens in
   tests.

Hard rules:
- Cite every finding with file:line.
- Label every claim FACT / INFERENCE / OPINION.
- For each finding: include a concrete attack scenario (input X
  reaches file:line and produces outcome Y) — abstract concerns are
  downgraded to HYPOTHESIS.
- No "consider hardening" without a verifying command (e.g., a
  test that demonstrates the fix).

Return:
ROLE: Security Engineer
TOP CONCERNS (severity Critical / High / Med / Low) with citations
ATTACK SCENARIOS (one per finding)
QUESTIONS FOR OTHER PERSONAS
RECOMMENDATIONS (each with verifying command)
OPEN QUESTIONS FOR THE HUMAN
```

Each persona returns a structured verdict:

```
ROLE: <persona>
TOP CONCERNS (ranked):
  1. <concern> — evidence: <file:line or facts.md§> — severity: H/M/L
  2. ...
QUESTIONS FOR OTHER PERSONAS:
  - @<role>: <question>
RECOMMENDATIONS:
  - <action> — owner: <role> — confidence: <high/med/low + why>
```

## Phase 3 — Cross-examination round

For every "QUESTIONS FOR OTHER PERSONAS" item, send a follow-up message
to the addressed persona via `SendMessage` (continuing the same agent).
Collect their responses. If a persona's answer contradicts another's,
flag it explicitly — do not paper over disagreement.

## Phase 4 — Synthesis

You (the orchestrator) write the final report to
`.agents/artifacts/roundtable-<timestamp>/report.md`:

1. **Points of consensus** (with the personas that agreed + evidence).
2. **Points of disagreement** (each side, evidence, what would resolve).
3. **Unanimous risks** (highest confidence concerns).
4. **Recommended next steps**, each tagged with confidence level and
   the evidence that supports it.
5. **Open questions for the human** — things no persona could answer
   from the evidence alone.

## Hard rules

- No persona may use phrases like "probably", "likely", "I think", or
  "in my experience" without an immediately following citation. If they
  do, the orchestrator rejects their verdict and re-prompts: *"Restate
  with file:line evidence or mark as OPINION."*
- The synthesis report must label every claim as **FACT** (cited),
  **INFERENCE** (reasoning chain shown), or **OPINION** (persona view,
  no ground truth).
- If facts.md is insufficient to answer a question, the answer is
  "insufficient evidence" — never a guess.
