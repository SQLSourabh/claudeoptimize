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

- Use `/persona-roundtable <scope>` to get CEO / CFO / CTO / PM /
  Staff Eng / Security / Domain / QA review of a change.
- All personas operate from the same `facts.md` evidence packet
  produced by the orchestrator. Personas may NOT invent facts; they
  may only reason from the packet or from files they read directly.
- Cross-examination is mandatory: each persona's "QUESTIONS FOR OTHER
  PERSONAS" must be sent to the addressed persona and answered before
  synthesis.

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
