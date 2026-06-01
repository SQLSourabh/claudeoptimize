# Project Operating Rules for Claude

These rules apply to every session in this project. They are not
suggestions.

## 1. Evidence-first analysis (no hand-waving)

For every claim Claude makes — in plans, code reviews, commit
messages, or chat — Claude must:

1. **Label the claim** as one of:
   - `FACT` — directly observed in this repo / this session.
     Must include a citation: `path/to/file:line` or a command +
     exit code.
   - `INFERENCE` — derived from facts via explicit reasoning.
     Must show the reasoning chain and the underlying facts.
   - `OPINION` — preference or judgment. Must be marked as such.

2. **Forbidden phrasings without an immediate citation:**
   "probably", "likely", "should work", "I think", "in my experience",
   "best practice is", "typically", "usually". If you catch yourself
   typing one, stop and either find evidence or downgrade the
   statement to OPINION.

3. **Plans must be falsifiable.** Every step lists:
   - What file(s) will change
   - What command verifies success (and its expected exit code)
   - What signal would prove the step wrong

4. **No fabricated APIs.** Before referencing a function, type, env
   var, or config key, `Grep` for it. If it doesn't exist, say so.

5. **No fabricated metrics.** Pricing, latency, throughput, market
   size — never invent numbers. Cite a file in the repo or list the
   number under "needs human input".

6. **Verification before completion.** Never claim work is "done",
   "fixed", or "passing" without running the verifying command in
   this session and showing its output. Past sessions don't count.

## 2. Checkpoint & EOD contract

- `Checkpoint.md` and `EOD_Summary.md` are **append-only** wherever
  they live in the project tree. Do not delete, reorder, or rewrite
  prior entries.
- **Location resolution.** The hooks scan the project tree for
  existing `Checkpoint.md` and `EOD_Summary.md` files (skipping
  `.git`, `node_modules`, `.venv`, `dist`, `build`, etc.) and adopt
  whatever is already there:
  - 0 found → create at project root.
  - 1 found → adopt that path (e.g. `docs/Checkpoint.md`).
  - 2+ found → pick deterministically (root preferred, else shortest
    path) and emit a WARNING in `additionalContext` listing every
    match. Consolidate to a single file to silence the warning.
- The `SessionStart` hook surfaces the resolved paths via
  `additionalContext`. **Use those paths**, not assumptions about
  the project root.
- The `PreCompact` and `Stop` hooks append a structured stub to the
  resolved `Checkpoint.md`. Before compaction completes, fill in
  every `<!-- Claude: ... -->` placeholder with cited content from
  the current session.
- The `/EOD_Summary` command rolls up the day's checkpoint blocks
  into a new section of the resolved `EOD_Summary.md`. It never
  edits prior sections.

## 3. Multi-persona reviews

- Use `/persona-roundtable <scope>` to get a multi-perspective review
  of a change. Personas: CEO, CFO, CTO, **Software Architect**, PM,
  Staff Software Engineer, Independent Code Reviewer, Security
  Engineer, QA, ML/AI LLM Researcher, DevOps/SRE, Data Engineer,
  UX/Copy, Compliance/Privacy, API Steward.
- **All 15 personas are file-backed and at v2 rigor** (≥348
  lines each, audit-cost tier `quick`/`standard`/`deep`,
  evidence-regime constraints, codified boundary table,
  `NEEDS-HUMAN-INPUT` discipline, alternative-hypotheses
  requirement, multi-item self-checks). No `general-purpose`
  embedded-prompt personas exist — every persona dispatches
  via its own `subagent_type`. Sizes: LLM Researcher 602,
  PM 554, CFO 523, Software Engineer 521, Architect 471,
  Security Engineer 448, Data Engineer 443, CEO 428,
  Compliance/Privacy 421, API Steward 414, CTO 412, UX/Copy
  393, DevOps/SRE 391, Independent Code Reviewer 367, QA
  Lead 348.
- **Codified boundary tables.** Each v2 persona ships with a
  boundary table mapping every concern in the roundtable to its
  owner persona. When v2 personas run together, all defer per
  the same table. This eliminates overlapping verdicts.
- The orchestrator selects only personas relevant to the scope
  (e.g., skip Data Engineer if no DB / ETL involvement; skip API
  Steward if no public surface change). Use `--exclude N,M,...` /
  `--only N,M,...` to override; mutually exclusive.
- Selection accepts persona ordinals (1–15) or short names; see
  `.claude/commands/persona-roundtable.md` for the canonical list.
- Brief mode: pass a `.md` file whose H1 begins
  `# Roundtable brief:` and the personas treat it as
  instructions describing what to evaluate (not the artifact
  under review).
- All personas operate from the same `facts.md` evidence packet
  produced by the orchestrator. Personas may NOT invent facts;
  they may only reason from the packet or from files they read
  directly. v2 personas additionally use `NEEDS-HUMAN-INPUT` for
  data classes that aren't inventable (internal financials,
  customer voice, market sizing, runway).
- Cross-examination is mandatory: each persona's "QUESTIONS FOR
  OTHER PERSONAS" must be sent to the addressed persona and
  answered before synthesis. If the addressed persona was
  excluded, the question is logged as open for human follow-up.

## 3.5 Hooks active in every session

The pack installs PreToolUse / PostToolUse hooks that run on every
Write/Edit/Bash. They will surface or block as follows:

- **secrets-guard** (PreToolUse on Write|Edit|Bash, BLOCKS on match) —
  scans for credential patterns (AWS, GitHub, Anthropic, OpenAI,
  Stripe, Slack, Google, RSA keys, JWTs, generic secret-name
  assignments). Allowlist: `.env.example`, `fixtures/secrets/`, etc.
- **scope-guard** (PreToolUse on Write|Edit, WARNS) — when the user
  has declared a scope via `/scope`, warns if a write lands outside.
- **test-first-enforcer** (PreToolUse on Write|Edit, WARNS) — when
  editing a source file with no test edited yet this session, prompts
  for the failing test or a `[refactor]` / `no-test-needed` marker.
- **blast-radius** (PreToolUse on Write|Edit, WARNS) — when editing
  a file imported by 20+ call sites (default threshold), surfaces a
  count + sample so the user can calibrate caution.
- **edit-recorder** (PostToolUse on Write|Edit, READ-ONLY) — populates
  per-session state the other hooks read.

To bypass a warning, address it in your next message or set
`CLAUDE_SKIP_TEST_FIRST=1` (test-first), use the in-content marker
`[refactor]` / `no-test-needed`, or update `/scope` to expand scope.

## 4. Subagent dispatch defaults

- Independent work → parallel subagents (single message, multiple
  `Agent` tool calls).
- Read-only investigation → use the `Explore` agent or read-only
  persona agents — never the implementer.
- Implementation → only after a plan is written and the user has
  approved it.

## 5. File / artifact discipline

- All generated research, reports, and scratch files go in
  `.agents/artifacts/<topic>-<timestamp>/`.
- Never write `*.md` documentation files at the project root unless
  the user explicitly asks. The two exceptions are `Checkpoint.md`
  and `EOD_Summary.md`, which are managed by the hooks/commands
  defined here. Their location is resolved at runtime — see
  Section 2.
