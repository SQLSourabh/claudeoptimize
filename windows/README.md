# Claude Code Optimization Pack — Windows

Drop-in scaffolding that wires three behaviors into any Claude Code
project on Windows:

1. **Auto-managed `Checkpoint.md` + `EOD_Summary.md`** (append-only).
2. **Multi-persona roundtable reviews** (CEO/CFO/CTO/PM/Staff Eng/QA/
   Security/Independent Reviewer/LLM Researcher).
3. **Evidence-first, no-hand-waving operating rules.**

This pack uses **only built-in Claude Code primitives** — no
plugins, no MCP servers, no organization-specific subagents.

## Requirements

- Claude Code CLI installed.
- Windows PowerShell 5.1 or newer (ships with every modern Windows).
  Hooks invoke `powershell` (Windows PowerShell), not `pwsh`.
- No Python required. All hook logic is native PowerShell.

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

## Pack contents

```
.
├── install.ps1                             # idempotent installer
├── CLAUDE.md                               # evidence-first project rules
└── .claude\
    ├── settings.json                       # hooks: SessionStart, PreCompact, Stop
    ├── hooks\
    │   ├── _lib.ps1                        # shared resolver (file location lookup)
    │   ├── ensure-checkpoint-files.ps1     # creates the two files if missing
    │   └── append-checkpoint.ps1           # appends structured stub
    ├── commands\
    │   ├── EOD_Summary.md                  # /EOD_Summary [date]
    │   ├── persona-roundtable.md           # /persona-roundtable <scope>
    │   └── llm-audit.md                    # /llm-audit <prompt-or-transcript>
    └── agents\
        ├── ceo-persona.md
        ├── cfo-persona.md
        ├── cto-persona.md
        ├── pm-persona.md
        ├── software-engineer-persona.md
        ├── qa-persona.md
        └── llm-researcher-persona.md
```

## How it works

| Trigger | What happens |
|---|---|
| Session start | `ensure-checkpoint-files.ps1` scans the project tree for existing `Checkpoint.md` / `EOD_Summary.md`. Adopts an existing file if found; creates a new one at project root only when none exists. |
| Pre-compaction | `append-checkpoint.ps1` re-resolves the location and appends a timestamped stub with structured placeholders. The hook tells Claude (via `additionalContext`) which file was used and to fill in the placeholders before compaction completes. |
| Session stop | Same hook fires again — guarantees a checkpoint even if the user never compacts. |
| `/EOD_Summary [date]` | Resolves `Checkpoint.md` / `EOD_Summary.md` via `Glob` (same rules as the hook), reads the day's blocks, appends a rollup section to `EOD_Summary.md`. Never edits prior content. |
| `/persona-roundtable <scope>` | Builds `facts.md`, dispatches 9 personas in parallel, runs cross-examination via `SendMessage`, writes `report.md`. |
| `/llm-audit <prompt-or-transcript>` | Runs the LLM Researcher standalone for prompt forensics + bias map + falsifiable improvement plan + continuous-eval loop design. |

### File-location resolution rules

The hook searches the project tree, **skipping**: `.git`, `.hg`,
`.svn`, `node_modules`, `.venv`, `venv`, `env`, `dist`, `build`,
`out`, `.next`, `.nuxt`, `target`, `__pycache__`, `.pytest_cache`,
`.mypy_cache`, `.tox`, `.gradle`, `.idea`, `.vscode`, `.claude`,
`.agents`.

| Matches found | Status surfaced | Action |
|---|---|---|
| 0 | `create` | Create at project root |
| 1 | `adopt` | Use that path (e.g. `docs\Checkpoint.md`) |
| 2+ with one at root | `ambiguous-root` | Use root copy, warn about duplicates |
| 2+ without root copy | `ambiguous-fallback` | Use shortest path (lex tiebreaker), warn |

The status and a human-readable note are passed to Claude in
`additionalContext` so the user always knows which file is in play.

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

## Verification (already done at build time)

- All `.ps1` scripts pass `[System.Management.Automation.PSParser]::Tokenize()`.
- `settings.json` parses as valid JSON.
- End-to-end smoke tests on Windows PowerShell 5.1 across **five
  resolution scenarios**:
  - No files anywhere → `create` at root.
  - Only `docs\Checkpoint.md` exists → `adopt` that path.
  - Root + `docs\` both have files → `ambiguous-root`, root wins,
    warning surfaced.
  - `docs\` + `notes\2026\` both have files (no root copy) →
    `ambiguous-fallback`, shortest path wins, warning surfaced.
  - Decoys in `.git`, `node_modules`, `dist` → pruned, treated as
    "no file found".
- All five scenarios produce correctly-formatted Checkpoint.md stubs
  and clean UTF-8 `additionalContext` JSON output.

## Uninstall

```powershell
Remove-Item .claude\hooks\ensure-checkpoint-files.ps1
Remove-Item .claude\hooks\append-checkpoint.ps1
Remove-Item .claude\commands\EOD_Summary.md
Remove-Item .claude\commands\persona-roundtable.md
Remove-Item .claude\commands\llm-audit.md
Get-ChildItem .claude\agents\*-persona.md | Remove-Item
# Remove the three hook entries from .claude\settings.json by hand,
# or restore from .bak if the installer made one.
# Checkpoint.md and EOD_Summary.md persist unless you delete them.
```
