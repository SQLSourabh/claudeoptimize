---
description: Run a multi-persona roundtable review of the current codebase or change
argument-hint: "<topic|path|gitref> [--brief] [--exclude N,M,...] [--only N,M,...]"
allowed-tools: Agent, Read, Grep, Glob, Bash(git:*)
---

# /persona-roundtable

Run a structured, evidence-grounded roundtable on: **$ARGUMENTS**

The arguments string contains:

- The **topic** — one of:
  - a free-text question (`"Should we migrate to Postgres?"`)
  - a path or glob (`src/auth/`, `*.py`)
  - a git ref (`HEAD~5..HEAD`, `origin/main..HEAD`)
  - a path to a **brief file** (a `.md` describing what to evaluate
    — see "Brief mode" below)
- Optional **`--brief`** to force brief-mode interpretation of a
  `.md` topic path.
- Optional **`--exclude <ordinals-or-names>`** to remove personas
  from the spawn set.
- Optional **`--only <ordinals-or-names>`** to spawn ONLY the listed
  personas.

`--exclude` and `--only` are **mutually exclusive**. If both are
present, error out and ask the user to pick one.

## Brief mode

A **brief** is a markdown file that describes the evaluation —
question, context, files of interest, specific concerns. It is
NOT the artifact under review; the personas do not review the
brief file itself. They read it as instructions and then apply
their lenses to whatever the brief points at (code, an idea, a
proposal, a vendor evaluation, etc.).

### When brief mode triggers

In priority order:

1. The user passed `--brief` explicitly.
2. The topic resolves to a `.md` file whose first H1 starts with
   `# Roundtable brief:` (case-insensitive). Auto-detected.

If neither condition holds and the topic is a `.md` path, the
orchestrator falls back to current behavior (treat as artifact
to review). When in doubt, ask the user — don't assume.

### Brief file schema

A well-formed brief looks like this:

```markdown
# Roundtable brief: <one-sentence question>

## Question
<free-form prose stating exactly what you want evaluated. The
personas read this and treat it as their charge.>

## Context
- Background bullet
- Background bullet
- Files of interest: <paths or globs — orchestrator reads them>
- Related artifacts: <ADR paths, prior PRs, proposal docs>

## Specific concerns
- <topic 1>
- <topic 2>
- ...

## Out of scope
- <thing the personas should NOT spend cycles on>

## Suggested ordinals (advisory)
<comma-separated list — informational only. Persona selection is
controlled by --only / --exclude on the command line. The
orchestrator surfaces this list to the user as a hint but does
NOT auto-apply it.>
```

Every section is optional except `## Question`. If `## Question`
is missing, abort and tell the user the brief is malformed.

### What the orchestrator does in brief mode

1. Reads the brief in full.
2. Uses `## Question` as the topic statement passed to every
   persona (in addition to facts.md).
3. Reads every path / glob in `## Context.Files of interest` and
   includes excerpts in facts.md.
4. Reads every ADR / proposal / artifact in `## Context.Related
   artifacts` and cites them in facts.md.
5. Surfaces `## Specific concerns` to the personas as priority
   focus areas.
6. Honors `## Out of scope` by adding it as a hard rule to each
   persona's prompt: "do not spend cycles on these topics".
7. If `## Suggested ordinals` is present AND the user provided
   neither `--only` nor `--exclude`, prints a one-line hint:
   `Brief suggests ordinals [3, 4, 11, 12]. Apply via --only or
   ignore. Spawning full set.` Does NOT auto-apply.

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
- topic kind: brief | gitref | path | freetext
- brief path: <path>            (only if kind=brief)
- brief charge: <one-line excerpt of the brief's ## Question>
- selection mode: full | only | exclude
- requested: <ordinals as listed by user, normalized>
- after relevance gate: <final ordinals + names>
- skipped (explain): <ordinal — reason>
- brief-suggested ordinals: <list>   (informational only)
```

If the final set is empty, abort and tell the user — don't spawn an
empty roundtable.

## Phase 1 — Establish shared facts

Before spawning any persona, gather the ground truth they will all
review. No persona is allowed to invent facts; they all read from
the same evidence packet.

### 1.1 Resolve topic kind

Strip `--brief`, `--exclude`, `--only` from `$ARGUMENTS` to get the
remaining topic string, then classify it:

| Kind | Detection | Example |
|---|---|---|
| **brief** | `--brief` flag present, OR topic is a `.md` whose first H1 starts with `# Roundtable brief:` | `proposals/postgres-migration.md` |
| **gitref** | matches `^[A-Za-z0-9._/~^-]+\.\.[A-Za-z0-9._/~^-]+$` or starts with `HEAD`, `origin/`, `pull/` | `HEAD~5..HEAD` |
| **path** | exists on disk OR contains a `/` or wildcard | `src/auth/`, `*.py` |
| **freetext** | none of the above | `"Should we adopt pgvector?"` |

If the topic is `.md` AND `--brief` is not given AND the H1 doesn't
match the brief signature, ask the user explicitly:

```
Topic is a .md file. Two interpretations:
  1. Treat as an artifact to review (current behavior).
  2. Treat as a brief — instructions for what to evaluate.
Pass --brief to choose option 2, or confirm option 1.
```

Do not guess.

### 1.2 Build facts.md per kind

Write `.agents/artifacts/roundtable-<timestamp>/facts.md` with the
evidence packet. Always include:

- Files in scope (paths + line counts)
- Key code excerpts (with `file:line` citations)
- Build / test status (commands run, exit codes)
- Known constraints from `CLAUDE.md`

Per kind, also include:

- **brief:** Read the brief in full and copy:
  - `## Question` verbatim into facts.md as `## Charge from brief`
  - `## Context.Files of interest` paths — read each, include
    excerpts (cited)
  - `## Context.Related artifacts` paths — read each, summarize
    each in 2-4 sentences (cited)
  - `## Specific concerns` verbatim as `## Priority focus areas`
  - `## Out of scope` verbatim as `## Out-of-scope (do not address)`
  - `## Suggested ordinals` as a metadata note only
- **gitref:** Run `git diff <ref>` and `git log <ref>`; include
  diff stat and the commit messages.
- **path:** `Read` the file or `Grep`/`Glob` the pattern; include
  excerpts.
- **freetext:** Do a focused codebase survey relevant to the
  free-text question.

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

## Appendix — Brief template

Copy this into a file (e.g., `proposals/<topic>.md`), fill it in,
then run `/persona-roundtable proposals/<topic>.md`.

```markdown
# Roundtable brief: Should we migrate from MySQL to Postgres?

## Question
Evaluate whether migrating our primary OLTP database from MySQL 8
to Postgres 16 is worth the cost and risk over the next two
quarters. Decision needed by end of Q3.

## Context
- We currently run MySQL 8 on RDS (cited from infra/rds.tf:14).
- Volume: ~2TB, 4k QPS p99, 99.95% SLO.
- Felt-pain motivators:
  - JSON column performance issues (citing
    docs/perf/2026-Q1-review.md§"JSON queries").
  - Missing PG-specific features (CTEs, generate_series).
- Files of interest:
  - infra/rds.tf
  - schema/migrations/
  - docs/perf/2026-Q1-review.md
- Related artifacts:
  - docs/adr/0008-chose-mysql.md (the decision being revisited)
  - PRs #1247, #1389 (recent JSON-related workarounds)

## Specific concerns
- Operational complexity during the transition (read-replica swap,
  cutover, rollback path).
- Vendor / RDS pricing delta.
- Application-layer changes required (ORM, raw SQL).
- Team expertise — who's run Postgres in production at this scale?

## Out of scope
- NoSQL / NewSQL alternatives (this is MySQL→Postgres only).
- Multi-region; that's tracked separately in ADR 0021.

## Suggested ordinals (advisory)
2, 3, 4, 11, 12, 14
(CFO, CTO, Architect, DevOps, Data Engineer, Compliance)
```

The personas will treat the brief's `## Question` as their charge
and apply each lens to the surrounding context. The brief itself
is NOT what they review — they review the actual subject the brief
points at.
