# Claude Code Optimization Pack — Distribution

Two ready-to-deploy packages of the optimization pack. Both packages
are functionally identical — same `CLAUDE.md`, same persona agents,
same slash commands, same evidence-first rules. They differ only in
the hook implementation language so each platform runs natively.

> **New here?** Read **[USAGE.md](./USAGE.md)** for end-to-end
> examples of every command and hook, plus four full workflows
> (new feature, bug fix, PR review, prompt audit).

| Folder | Platform | Hook language | Installer |
|---|---|---|---|
| `linux-macos/` | Linux, macOS, WSL | bash + `python` (optional) | `bash install.sh [target]` |
| `windows/` | Windows | PowerShell (`powershell`, not `pwsh`) | `powershell -ExecutionPolicy Bypass -File install.ps1 [-Target target]` |

## What both packs deliver

### Goal 1 — Auto-managed checkpoint + EOD rollup
- `SessionStart` hook **scans the project tree** for existing
  `Checkpoint.md` / `EOD_Summary.md`. Adopts existing files (e.g.
  `docs/Checkpoint.md`); creates new ones at project root only when
  none are found. Multiple copies trigger a warning surfaced to
  Claude via `additionalContext`. Skips `.git`, `node_modules`,
  `.venv`, `dist`, `build`, etc.
- `PreCompact` and `Stop` hooks re-resolve the location and
  append a partial-but-true block: header + **Files touched**
  (from `edit-recorder` session state) + **Verification
  evidence** (bash exit codes from the transcript) + **Slash
  commands invoked** (from the transcript) — all populated
  deterministically. The four narrative sections (Goals /
  Decisions / Open / Blockers) carry placeholders.
- **`/checkpoint`** is a new manual slash command that fills in
  the four narrative sections by reading the session's
  transcript and synthesizing language-level content with
  citations. It also accepts `--from-transcript <path>` to
  recover narrative from old transcripts whose blocks were
  lost (or never written, before the v2 hook contract).
- The resolver caches its decision in
  `.claude/state/project.json` (committable) so the path
  resolution survives across sessions. Subsequent hook fires
  return `cached` instead of re-scanning. If the cached path
  goes missing, the cache invalidates automatically and the
  resolver falls back to a tree scan.
- `/EOD_Summary` rolls up checkpoint blocks into
  `EOD_Summary.md`. Four mutually-exclusive modes: today
  (default), specific date, `--since-last` (catch up since
  the latest entry already in the file), and
  `--range YYYY-MM-DD..YYYY-MM-DD`. Append-only, idempotent.

### Goal 2 — Multi-persona roundtables (vanilla, no plugins)
`/persona-roundtable <scope>` runs four phases:
1. **Establish facts** — build `facts.md` (the single source of
   truth all personas may cite).
2. **Parallel dispatch** — up to 15 personas in one round-trip,
   ALL file-backed under `.claude/agents/`. (The former
   `general-purpose` embedded-prompt personas — Independent
   Code Reviewer and Security Engineer — have been promoted to
   file-backed v2.)
   - **All 15 personas at v2 rigor** (≥348 lines each, audit-
     cost tier, evidence-regime constraints, codified boundary
     table, `NEEDS-HUMAN-INPUT` discipline, alternative-
     hypotheses requirement, multi-item self-checks):
     LLM Researcher (602), PM (554), CFO (523), Software
     Engineer (521), Architect (471), Security Engineer (448),
     Data Engineer (443), CEO (428), Compliance/Privacy (421),
     API Steward (414), CTO (412), UX/Copy (393), DevOps/SRE
     (391), Independent Code Reviewer (367), QA Lead (348).
   - Selection flags: `--exclude N,M,...` and `--only N,M,...`
     accept persona ordinals (1–15) or short names. Mutually
     exclusive. Default = full set, then relevance-gated by
     scope.
   - Brief mode: pass a `.md` file whose H1 begins
     `# Roundtable brief:` and the personas treat it as
     instructions describing what to evaluate (not the
     artifact under review).
   - The orchestrator selects only the personas relevant to the
     scope (e.g., skip Data Engineer if no DB/ETL involvement).
3. **Cross-examination** — every "QUESTIONS FOR OTHER PERSONAS" is
   routed via `SendMessage` so personas literally talk to each
   other.
4. **Synthesis** — orchestrator writes `report.md` with consensus,
   disagreements, unanimous risks, coverage gaps, and open
   human questions.

### Goal 3 — Factual analysis only
`CLAUDE.md` codifies five hard rules:
1. Three-label system (`FACT` / `INFERENCE` / `OPINION`) on every
   claim.
2. Banned hand-wavy phrases without immediate citation.
3. Falsifiable plans (file changes + verifying command + falsifier).
4. No fabricated APIs / configs / metrics.
5. Verification before completion — re-run the command this session.

### Bonus — `/llm-audit`
Standalone LLM forensics + bias map + falsifiable improvement plan
+ continuous-eval loop design, powered by the
`llm-researcher-persona`.

### Goal 4 — SDLC safety nets (PreToolUse / PostToolUse hooks)

The pack installs hooks that fire automatically on every `Write`,
`Edit`, and `Bash` so you don't have to remember a slash command:

| Hook | Tool match | Behavior |
|---|---|---|
| `secrets-guard` | `Write\|Edit\|Bash` | **BLOCKS** when content contains an AWS key, GitHub/Anthropic/OpenAI/Stripe/Slack/Google token, RSA private key, JWT, or a generic `*_KEY="..."` literal. Allowlist: `.env.example`, `fixtures/secrets/`, etc. Placeholders like `${VAR}` and `os.environ["X"]` pass through. |
| `scope-guard` | `Write\|Edit` | WARNS when an edit falls outside the scope declared via `/scope`. Nudge, not block — pauses for confirmation. |
| `test-first-enforcer` | `Write\|Edit` | WARNS when editing a source file with no test edited yet this session. Bypass via `[refactor]` / `no-test-needed` in content or `CLAUDE_SKIP_TEST_FIRST=1`. |
| `blast-radius` | `Write\|Edit` | WARNS when editing a file imported in 20+ places (configurable). Surfaces a count + sample so the user can calibrate caution. |
| `edit-recorder` | `Write\|Edit` (PostToolUse) | Read-only state recorder feeding the other nudge hooks. |

### Goal 5 — Slash commands for the SDLC

Beyond `/persona-roundtable`, `/llm-audit`, `/EOD_Summary`,
`/checkpoint`:

| Command | Purpose |
|---|---|
| `/scope <items>` | Declare session scope (paths, dirs, globs); used by `scope-guard`. |
| `/spec <feature>` | Produce a structured spec (problem, non-goals, acceptance, test plan, rollback) before code. Writes to `.agents/artifacts/specs/`. |
| `/repro <bug>` | Build a minimal failing test BEFORE attempting any fix. Refuses to fix until red exists. |
| `/adr <title>` | Record an immutable, numbered Architecture Decision (`docs/adr/NNNN-...`). |
| `/pr-preflight [--strict]` | Run lint + types + tests + secrets-on-diff + commit-style + line-budget; verdict before push. |
| `/handoff [topic]` | Forward-looking "next session starts here" doc with the exact next command to run. |
| `/retro` | Session retrospective with proposed CLAUDE.md edits (opt-in). |

## Pure-vanilla compatibility

Neither pack references any of these:

- ❌ Third-party MCP servers
- ❌ Organization-specific subagent plugins
- ❌ Domain-specific Claude Code skills

The Independent Code Reviewer and Security Engineer roles use the
built-in `general-purpose` subagent type with **embedded prompt
templates** — no external dependencies.

## Verification log (run at build time)

```
== Linux/macOS ==
- All bash scripts: bash -n OK
- All settings.json: JSON valid
- Checkpoint resolution scenarios (5/5 PASS):
  - no files anywhere       -> create at root
  - only docs/ has files    -> adopt docs/ path
  - root + docs/ both       -> ambiguous-root, root wins, warn
  - docs/ + notes/2026/     -> ambiguous-fallback, shortest wins, warn
  - decoys in pruned dirs   -> pruned, treated as no-match
- secrets-guard scenarios (12/12 PASS):
  - clean code, AWS key (deny), .env.example allowlist,
    placeholder, Anthropic-in-Bash (deny), JWT in fixtures,
    GitHub token in Edit (deny), generic password (deny),
    password via getenv, RSA key block (deny), prose,
    Read tool (no scan)
- nudge-hook scenarios (9/9 PASS):
  - scope-guard no-op without scope
  - scope-guard warns on out-of-scope edit
  - scope-guard silent on in-scope edit
  - test-first warns when no test changed
  - test-first bypassed by [refactor] marker
  - test-first silent when editing the test itself
  - test-first silent after a test edit was recorded
  - blast-radius warns on heavily-imported file (25 importers)
  - blast-radius silent on uncited file

== Windows ==
- All .ps1 scripts: PSParser OK
- All settings.json: JSON valid
- Same five checkpoint resolution scenarios PASS on PS 5.1
- secrets-guard 7/7 sampled scenarios PASS on PS 5.1
- 8.3 short-name path canonicalization (Get-Item not Resolve-Path)
- additionalContext stdout forced to UTF-8
```

## Bugs caught and fixed during build-time testing

1. **Linux/macOS** — `find` quoting needed dynamic `-prune` clause
   construction so adding a new skip-dir doesn't break the command.
   Verified all five scenarios.
2. **Windows** — `Resolve-Path` returns 8.3 short names when the
   project lives under a path like `C:\Users\SOURAB~1.AGA\...`
   while `Get-ChildItem.FullName` returns the long form. Prefix
   comparison failed; relative-path computation produced "C" instead
   of `docs\Checkpoint.md`. Fixed by switching canonicalization to
   `Get-Item`.
3. **Windows** — Console output encoding default mangled non-ASCII
   characters in `additionalContext` JSON. Fixed by forcing UTF-8
   on `[Console]::OutputEncoding` and `$OutputEncoding` at the top
   of every hook.
4. **Secrets guard** — `python - <<'PYEOF'` consumed stdin entirely,
   making `sys.stdin.read()` always empty so every payload silently
   passed. Fixed by extracting the scanner into a sibling Python
   file (`_secrets_scan.py`) the bash wrapper invokes via
   `python <script>` while still piping the payload through stdin.
5. **Secrets guard** — placeholder regex included `\bEXAMPLE\b` and
   `\bREDACTED\b`, which false-suppressed real key matches when a
   line legitimately contained `api.example.com`. Removed those two
   tokens; kept the structural placeholders (`${VAR}`,
   `process.env.X`, `os.environ["X"]`, `<YOUR_KEY>`).
6. **Secrets guard** — generic password pattern used `\bpassword\b`,
   but `\b` doesn't fire between underscore and letter, so
   `DB_PASSWORD = "..."` slipped past. Anchored on
   `(?:^|[^A-Za-z0-9])` instead.
