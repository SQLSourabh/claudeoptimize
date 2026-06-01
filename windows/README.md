# Claude Code Optimization Pack — Windows

Drop-in scaffolding that wires four behaviors into any Claude Code
project on Windows:

1. **Auto-managed `Checkpoint.md` + `EOD_Summary.md`** (append-only,
   tree-walking file resolver).
2. **Multi-persona roundtable reviews** — up to 15 personas in
   parallel with `--exclude` / `--only` ordinal selection and
   brief-mode (`.md` as instructions).
3. **SDLC safety nets** — PreToolUse / PostToolUse hooks that block
   credential leaks, nudge TDD discipline, flag scope creep, and
   warn on widely-imported edits.
4. **Evidence-first, no-hand-waving operating rules.**

This pack uses **only built-in Claude Code primitives** — no
plugins, no MCP servers, no organization-specific subagents.

> For end-to-end usage examples of every command and hook, see
> [USAGE.md](../USAGE.md) at the top level of the pack.

## Requirements

- Claude Code CLI installed.
- Windows PowerShell 5.1 or newer (ships with every modern Windows).
  Hooks invoke `powershell` (Windows PowerShell), not `pwsh`.
- **`python` on PATH** — required for the SDLC scanner hooks
  (secrets-guard, scope-guard, test-first, blast-radius). The
  scanner logic is shared cross-platform, written once in Python,
  and invoked by the PowerShell wrappers. Without `python` the
  SDLC hooks become inactive (the wrappers detect this and exit
  silently); the checkpoint hooks still work.

## Install

```powershell
# From the pack directory:
powershell -ExecutionPolicy Bypass -File install.ps1
# or target a specific project:
powershell -ExecutionPolicy Bypass -File install.ps1 -Target C:\path\to\project
```

The installer is idempotent. If `CLAUDE.md` or `.claude\settings.json`
already exist, it backs them up and writes companion files
(`CLAUDE.optimization.md`, `settings.pack.json`, `settings.json.bak`)
for manual merge.

The installer **glob-copies all `*.ps1` and `*.py`** from the source
`hooks\` directory — adding new hooks to the source pack does not
require editing the installer.

## Pack contents

```
.
├── install.ps1                             # idempotent installer
├── CLAUDE.md                               # evidence-first project rules
└── .claude\
    ├── settings.json                       # hooks: SessionStart, PreToolUse,
    │                                       #        PostToolUse, PreCompact, Stop
    ├── hooks\                              # 8 PowerShell wrappers + 5 python helpers
    │   ├── _lib.ps1                        # shared file-location resolver
    │   ├── _secrets_scan.py                # credential pattern scanner
    │   ├── _test_first.py                  # test-edit detector
    │   ├── _scope_guard.py                 # in-scope checker
    │   ├── _blast_radius.py                # call-site counter
    │   ├── _session_state.py               # session-state helper
    │   ├── ensure-checkpoint-files.ps1     # SessionStart
    │   ├── append-checkpoint.ps1           # PreCompact + Stop
    │   ├── secrets-guard.ps1               # PreToolUse — BLOCKS on credential
    │   ├── scope-guard.ps1                 # PreToolUse — WARNS off-scope
    │   ├── test-first-enforcer.ps1         # PreToolUse — WARNS no test yet
    │   ├── blast-radius.ps1                # PreToolUse — WARNS widely-imported
    │   └── edit-recorder.ps1               # PostToolUse — silent state
    ├── commands\                           # 10 slash commands
    │   ├── EOD_Summary.md                  # /EOD_Summary [date]
    │   ├── persona-roundtable.md           # /persona-roundtable [--brief|--exclude|--only]
    │   ├── llm-audit.md                    # /llm-audit [--tier quick|standard|deep]
    │   ├── scope.md                        # /scope <items>
    │   ├── spec.md                         # /spec <feature>
    │   ├── repro.md                        # /repro <bug>
    │   ├── adr.md                          # /adr <title>
    │   ├── pr-preflight.md                 # /pr-preflight [--strict]
    │   ├── handoff.md                      # /handoff [topic]
    │   └── retro.md                        # /retro
    └── agents\                             # 15 persona files; ALL at v2 rigor
        ├── ceo-persona.md                  # v2 — 428 lines
        ├── cfo-persona.md                  # v2 — 523 lines
        ├── cto-persona.md                  # v2 — 412 lines
        ├── architect-persona.md            # v2 — 471 lines
        ├── pm-persona.md                   # v2 — 554 lines (strategic + execution regimes)
        ├── software-engineer-persona.md    # v2 — 521 lines
        ├── qa-persona.md                   # v2 — 348 lines (test-pyramid + negative-space)
        ├── llm-researcher-persona.md       # v2 — 602 lines
        ├── devops-sre-persona.md           # v2 — 391 lines (SLO + toil instrument)
        ├── data-engineer-persona.md        # v2 — 443 lines (data-quality SLO + lineage)
        ├── ux-copy-persona.md              # v2 — 393 lines (WCAG-anchored a11y)
        ├── compliance-privacy-persona.md   # v2 — 421 lines (13-framework taxonomy)
        ├── api-steward-persona.md          # v2 — 414 lines (17-row breaking-change taxonomy)
        ├── security-engineer-persona.md    # v2 — 448 lines (vulnerability surface + STRIDE)
        └── independent-reviewer-persona.md # v2 — 367 lines (cross-checks Staff Engineer)
```

## How it works

### Hooks (auto-fire)

| Hook | Event | Tool match | Behavior |
|---|---|---|---|
| `ensure-checkpoint-files.ps1` | `SessionStart` | * | Resolves `Checkpoint.md` / `EOD_Summary.md` location (tree scan, skips `.git` / `node_modules` / `.venv` / `dist` / `build` / etc.). Adopts existing files; creates at root only when none found. |
| `secrets-guard.ps1` | `PreToolUse` | `Write\|Edit\|Bash` | **BLOCKS** when content contains AWS / GitHub / Anthropic / OpenAI / Stripe / Slack / Google tokens, RSA private keys, JWTs, or generic secret-name literals. Allowlist for `.env.example` / `fixtures/secrets/`. |
| `scope-guard.ps1` | `PreToolUse` | `Write\|Edit` | WARNS when an edit lands outside the scope declared via `/scope`. |
| `test-first-enforcer.ps1` | `PreToolUse` | `Write\|Edit` | WARNS when editing a source file with no test edited yet this session. Bypass via `[refactor]` / `no-test-needed` markers or `CLAUDE_SKIP_TEST_FIRST=1`. |
| `blast-radius.ps1` | `PreToolUse` | `Write\|Edit` | WARNS when editing a file imported in 20+ places (default threshold; tune via `CLAUDE_BLAST_RADIUS_THRESHOLD`). |
| `edit-recorder.ps1` | `PostToolUse` | `Write\|Edit` | Silent — records edits in `.claude\state\<session_id>.json` for the other nudge hooks. |
| `append-checkpoint.ps1` | `PreCompact` + `Stop` | * | Appends a structured stub to `Checkpoint.md` and tells Claude to fill in placeholders before compaction completes. |

### Slash commands

| Command | Purpose |
|---|---|
| `/scope <items>` | Declare session scope (paths / dirs / globs). Read by `scope-guard`. |
| `/spec <feature>` | Produce a structured spec before code (problem, non-goals, acceptance, test plan, rollback). |
| `/repro <bug>` | Build a minimal failing test BEFORE attempting any fix. |
| `/adr <title>` | Record an immutable, numbered Architecture Decision (`docs\adr\NNNN-...`). |
| `/pr-preflight [--strict]` | Run lint + types + tests + secrets-on-diff + commit-style + line-budget; verdict before push. |
| `/handoff [topic]` | Forward-looking "next session starts here" doc with the exact next command to run. |
| `/retro` | Session retrospective + opt-in CLAUDE.md edit proposals. |
| `/EOD_Summary [date]` | Roll up the day's checkpoint blocks into `EOD_Summary.md` (append-only). |
| `/persona-roundtable <topic\|path\|gitref\|brief.md> [--brief] [--exclude N,M] [--only N,M]` | Multi-perspective review with persona-ordinal selection. |
| `/llm-audit <prompt-path> [reference-set] [--tier quick\|standard\|deep]` | Standalone LLM forensics + bias map + falsifiable improvement plan + continuous-eval loop. |

See [USAGE.md](../USAGE.md) for full examples of each.

### Checkpoint file-location resolution

The checkpoint hook searches the project tree, **skipping**: `.git`,
`.hg`, `.svn`, `node_modules`, `.venv`, `venv`, `env`, `dist`,
`build`, `out`, `.next`, `.nuxt`, `target`, `__pycache__`,
`.pytest_cache`, `.mypy_cache`, `.tox`, `.gradle`, `.idea`,
`.vscode`, `.claude`, `.agents`.

| Matches found | Status surfaced | Action |
|---|---|---|
| 0 | `create` | Create at project root |
| 1 | `adopt` | Use that path (e.g. `docs\Checkpoint.md`) |
| 2+ with one at root | `ambiguous-root` | Use root copy, warn about duplicates |
| 2+ without root copy | `ambiguous-fallback` | Use shortest path (lex tiebreaker), warn |

The status and a human-readable note are passed to Claude in
`additionalContext` so the user always knows which file is in
play.

## Configuration knobs (env vars)

| Env var | Default | Effect |
|---|---|---|
| `CLAUDE_PROJECT_DIR` | (set by Claude Code) | Project root used by all hooks. |
| `CLAUDE_SKIP_TEST_FIRST` | `0` | When `1`, disables `test-first-enforcer` for the session. |
| `CLAUDE_BLAST_RADIUS_THRESHOLD` | `20` | Call-site count above which `blast-radius` warns. |

Set in PowerShell:

```powershell
$env:CLAUDE_BLAST_RADIUS_THRESHOLD=10
claude
```

## Notes specific to Windows

- The hook scripts force UTF-8 on stdout (`[Console]::OutputEncoding`)
  so the JSON `additionalContext` reaches Claude unmangled. Without
  this, Windows PowerShell 5.1 emits OEM-encoded bytes and breaks
  non-ASCII characters in chat.
- `settings.json` invokes `powershell.exe` with
  `-ExecutionPolicy Bypass -NoProfile` so the hooks run regardless
  of system policy and aren't slowed down by user profile loading.
- `Add-Content -Encoding UTF8` is used everywhere we touch
  `Checkpoint.md` to keep the file consistent.
- The resolver uses `Get-Item` (not `Resolve-Path`) for path
  canonicalization. `Resolve-Path` does NOT expand 8.3 short names
  (e.g., `SOURAB~1.AGA`), but `Get-ChildItem.FullName` returns the
  long form, so prefix comparisons used to fail when the user's
  project lived under a path with a short-name segment. `Get-Item`
  expands consistently.
- The SDLC scanner hooks are written in **Python** (not PowerShell)
  so the regex / state logic is shared cross-platform. The
  PowerShell wrappers here only marshal stdin → python →
  `additionalContext` JSON.

## Verification (build-time)

- All `*.ps1` scripts pass `[System.Management.Automation.PSParser]::Tokenize()`.
- All `*.py` helpers parse-clean.
- `settings.json`: valid JSON.
- Installer smoke test: copies all 13 hook files (8 PowerShell + 5
  python), creates target directory tree.
- Checkpoint resolution: 5/5 scenarios pass on Windows PowerShell 5.1
  (8.3 short-name path canonicalization + UTF-8 stdout fixes verified).
- secrets-guard: 7/7 sampled scenarios pass on Windows PowerShell 5.1
  (clean code, AWS / Anthropic / GitHub / Stripe / RSA / JWT
  detection, allowlist paths, placeholders, generic password literals).

## Uninstall

```powershell
Remove-Item .claude\hooks\_*.ps1
Remove-Item .claude\hooks\_*.py
Remove-Item .claude\hooks\ensure-checkpoint-files.ps1
Remove-Item .claude\hooks\append-checkpoint.ps1
Remove-Item .claude\hooks\secrets-guard.ps1
Remove-Item .claude\hooks\scope-guard.ps1
Remove-Item .claude\hooks\test-first-enforcer.ps1
Remove-Item .claude\hooks\blast-radius.ps1
Remove-Item .claude\hooks\edit-recorder.ps1
Get-ChildItem .claude\commands\*.md | Remove-Item
Get-ChildItem .claude\agents\*-persona.md | Remove-Item
# (the glob covers all 15 personas including security-engineer-persona.md
#  and independent-reviewer-persona.md)
# Remove the hook entries from .claude\settings.json by hand,
# or restore from .bak if the installer made one.
# Checkpoint.md and EOD_Summary.md persist unless you delete them.
```
