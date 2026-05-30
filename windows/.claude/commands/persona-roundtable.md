---
description: Run a multi-persona roundtable review of the current codebase or change
argument-hint: "<topic|path|gitref> [--exclude N,M,...] [--only N,M,...]"
allowed-tools: Agent, Read, Grep, Glob, Bash(git:*)
---

# /persona-roundtable

Run a structured, evidence-grounded roundtable on: **$ARGUMENTS**

The arguments string contains:

- The **topic / path / git-ref** (everything before any `--exclude`
  or `--only` flag).
- Optional **`--exclude <ordinals-or-names>`** to remove personas
  from the spawn set.
- Optional **`--only <ordinals-or-names>`** to spawn ONLY the listed
  personas.

`--exclude` and `--only` are **mutually exclusive**. If both are
present, error out and ask the user to pick one.

## Persona ordinal list (canonical)

The ordinals below are stable. Adding new personas appends to the
end — never reuse an ordinal, never renumber.

| # | Persona | Subagent type | Lens | Default-relevance trigger |
|---|---|---|---|---|
| 1 | CEO | ceo-persona | Strategic fit, opportunity cost, market risk | always |
| 2 | CFO | cfo-persona | Cost (compute, headcount, vendor), ROI, runway impact | always |
| 3 | CTO / CIO | cto-persona | Tech debt, scalability, observability, platform alignment | always |
| 4 | Software Architect | architect-persona | Component boundaries, separation of concerns, style fit, build-vs-buy, cross-cutting drift, extensibility | scope adds modules, dependencies, or new layers |
| 5 | Project Manager | pm-persona | Scope, schedule, dependencies, RAID log | always |
| 6 | Staff Software Engineer | software-engineer-persona | Code correctness, consistency with established patterns, test quality, maintainability | scope contains code |
| 7 | Independent Code Reviewer | general-purpose | Second-opinion code review (cross-checks Staff Engineer) — see prompt template below | scope contains code |
| 8 | Security Engineer | general-purpose | Authn/z, injection, data exposure, secrets — see prompt template below | scope contains code |
| 9 | QA Lead | qa-persona | Test coverage, edge cases, regression risk | scope contains code |
| 10 | ML/AI LLM Researcher | llm-researcher-persona | Output forensics, prompt bias surface, eval-loop design | scope involves LLM prompt, agent, or model output |
| 11 | DevOps / SRE | devops-sre-persona | Deploy story, rollback, observability, on-call burden | scope touches infra, deploy, or release-impacting code |
| 12 | Data Engineer | data-engineer-persona | Schema migrations, idempotency, lineage, replay, data quality | scope touches DB / ETL / events / pipelines |
| 13 | UX / Copy | ux-copy-persona | Error messages, naming consistency, empty states, microcopy, code-observable a11y | scope touches user-facing surface |
| 14 | Compliance / Privacy | compliance-privacy-persona | Data classification, retention, consent, audit trail, cross-border flows | scope touches user data |
| 15 | API Steward | api-steward-persona | Versioning, deprecations, backward compatibility, contract stability | scope touches public API, library exports, CLI flags, config keys, or event schemas |

### Selection precedence

1. Start with the **full set** (1–15).
2. If `--only` is provided, intersect with that set.
3. Else if `--exclude` is provided, subtract that set from the full set.
4. Apply **relevance gating** (the right-most column of the table):
   skip personas whose trigger condition isn't met by the current
   scope. **Exception:** if the user explicitly listed a persona via
   `--only`, do NOT relevance-gate it out — the user's instruction
   wins.
5. Spawn the resulting set.

### Argument syntax

`--exclude` / `--only` accept a comma-separated list of:

- **Ordinals**: `1,5,12`
- **Short names** (case-insensitive): `ceo,cfo,architect,pm,
  staff-eng,reviewer,security,qa,llm,devops,data,ux,compliance,api`
- **Mixed**: `1,security,12`

Whitespace inside the list is ignored. The orchestrator MUST resolve
every name to an ordinal before deciding the spawn set, and MUST
print the resolved ordinal list back to the user before spawning so
intent is auditable.

If a name doesn't resolve, the orchestrator stops and prints the
list of valid names — does not silently drop the unrecognized item.

### Short-name resolver (canonical)

| Short name | Resolves to |
|---|---|
| `ceo` | 1 |
| `cfo` | 2 |
| `cto`, `cio` | 3 |
| `architect`, `arch` | 4 |
| `pm`, `project-manager` | 5 |
| `staff-eng`, `engineer`, `eng` | 6 |
| `reviewer`, `code-reviewer`, `independent` | 7 |
| `security`, `sec` | 8 |
| `qa`, `qa-lead` | 9 |
| `llm`, `llm-researcher`, `researcher` | 10 |
| `devops`, `sre`, `devops-sre` | 11 |
| `data`, `data-engineer`, `de` | 12 |
| `ux`, `copy`, `ux-copy` | 13 |
| `compliance`, `privacy`, `compliance-privacy` | 14 |
| `api`, `api-steward`, `steward` | 15 |

### Examples

| Input | Spawn set |
|---|---|
| `/persona-roundtable origin/main..HEAD` | All 15, then relevance-gated |
| `/persona-roundtable HEAD~1..HEAD --exclude 1,2` | 3..15, then relevance-gated (no CEO, no CFO) |
| `/persona-roundtable src/payments/ --exclude ceo,cfo,pm` | 3,4,6..15, then relevance-gated |
| `/persona-roundtable docs/api.md --only 4,15` | Architect + API Steward (no relevance gate — user forced) |
| `/persona-roundtable HEAD~5..HEAD --only security,qa,reviewer` | 7,8,9 (forced) |
| `/persona-roundtable . --exclude 1,2,3,4,5` | Skip the C-suite + PM; review is just the tech personas |

### Auditing the spawn set

Before Phase 2 dispatch, print this block to chat:

```
Roundtable spawn plan
- topic: <resolved topic>
- selection mode: full | only | exclude
- requested: <ordinals as listed by user, normalized>
- after relevance gate: <final ordinals + names>
- skipped (explain): <ordinal — reason>
```

If the final set is empty, abort and tell the user — don't spawn an
empty roundtable.

## Phase 1 — Establish shared facts

Before spawning any persona, gather the ground truth they will all
review. No persona is allowed to invent facts; they all read from
the same evidence packet.

1. Strip `--exclude` / `--only` from `$ARGUMENTS` to get the topic.
2. If the topic looks like a path or glob, `Read` / `Grep` it.
3. If it looks like a git ref, run `git diff <ref>` and
   `git log <ref>`.
4. Otherwise, do a focused codebase survey relevant to the topic.
5. Write the evidence packet to
   `.agents/artifacts/roundtable-<timestamp>/facts.md` with:
   - Files in scope (paths + line counts)
   - Key code excerpts (with `file:line` citations)
   - Build / test status (commands run, exit codes)
   - Known constraints from `CLAUDE.md`

## Phase 2 — Dispatch personas in parallel

Spawn the resolved set **in a single message with multiple Agent tool
calls** so they run concurrently. Each gets the path to `facts.md`
and is told: *"You may only cite from facts.md or from files you
Read yourself. No speculation."*

### Prompt template — Independent Code Reviewer (general-purpose, ordinal 7)

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

### Prompt template — Security Engineer (general-purpose, ordinal 8)

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

For every "QUESTIONS FOR OTHER PERSONAS" item, send a follow-up
message to the addressed persona via `SendMessage` (continuing the
same agent). If the addressed persona was excluded from this run,
state explicitly: "@<role> not in this roundtable (excluded by user
or relevance gate). Question logged as open for human follow-up."
Collect responses. If a persona's answer contradicts another's,
flag it explicitly — do not paper over disagreement.

## Phase 4 — Synthesis

You (the orchestrator) write the final report to
`.agents/artifacts/roundtable-<timestamp>/report.md`:

1. **Spawn manifest** — full ordinal list, selection mode (full /
   only / exclude), and the resolved set actually spawned. Lets a
   reader audit which lenses were applied.
2. **Points of consensus** (with the personas that agreed + evidence).
3. **Points of disagreement** (each side, evidence, what would resolve).
4. **Unanimous risks** (highest confidence concerns).
5. **Recommended next steps**, each tagged with confidence level and
   the evidence that supports it.
6. **Open questions for the human** — things no persona could answer
   from the evidence alone, INCLUDING any cross-examination question
   that was routed to an excluded persona.
7. **Coverage gaps** — list lenses that were excluded and what they
   would have looked at, so the user knows what wasn't reviewed.

## Hard rules

- No persona may use phrases like "probably", "likely", "I think",
  or "in my experience" without an immediately following citation.
  If they do, the orchestrator rejects their verdict and re-prompts:
  *"Restate with file:line evidence or mark as OPINION."*
- The synthesis report must label every claim as **FACT** (cited),
  **INFERENCE** (reasoning chain shown), or **OPINION** (persona
  view, no ground truth).
- If facts.md is insufficient to answer a question, the answer is
  "insufficient evidence" — never a guess.
- The Spawn manifest is mandatory in every report — there is no
  scenario where the user shouldn't be able to audit who reviewed
  the change.
