# Claude Code Optimization Pack — Linux / macOS

Drop-in scaffolding that wires three behaviors into any Claude Code
project on Linux or macOS:

1. **Auto-managed `Checkpoint.md` + `EOD_Summary.md`** (append-only).
2. **Multi-persona roundtable reviews** (CEO/CFO/CTO/PM/Staff Eng/QA/
   Security/Independent Reviewer/LLM Researcher).
3. **Evidence-first, no-hand-waving operating rules.**

This pack uses **only built-in Claude Code primitives** — no
plugins, no MCP servers, no organization-specific subagents.

## Requirements

- Claude Code CLI installed.
- `bash` (every Linux distro and macOS ships it).
- `python` on PATH for JSON parsing in the PreCompact hook (degrades
  gracefully if absent — the hook still appends, just without
  session_id / transcript_path metadata).
- `find`, `awk`, `sort`, `head`, `cut`, `sed` (POSIX standard, ship
  with every distro and macOS).

## Install

```bash
# From the pack directory:
bash install.sh                      # install into the current directory
bash install.sh /path/to/project     # install into a specific project
```

The installer is idempotent. If `CLAUDE.md` or `.claude/settings.json`
already exist, it backs them up and writes companion files
(`CLAUDE.optimization.md`, `settings.json.bak`) for manual merge.

## Pack contents

```
.
├── install.sh                              # idempotent installer
├── CLAUDE.md                               # evidence-first project rules
└── .claude/
    ├── settings.json                       # hooks: SessionStart, PreCompact, Stop
    ├── hooks/
    │   ├── _lib.sh                         # shared resolver (file location lookup)
    │   ├── ensure-checkpoint-files.sh      # creates the two files if missing
    │   └── append-checkpoint.sh            # appends structured stub
    ├── commands/
    │   ├── EOD_Summary.md                  # /EOD_Summary [date]
    │   ├── persona-roundtable.md           # /persona-roundtable <scope>
    │   └── llm-audit.md                    # /llm-audit <prompt-or-transcript>
    └── agents/
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
| Session start | `ensure-checkpoint-files.sh` scans the project tree for existing `Checkpoint.md` / `EOD_Summary.md`. Adopts an existing file if found; creates a new one at project root only when none exists. |
| Pre-compaction | `append-checkpoint.sh` re-resolves the location and appends a timestamped stub with structured placeholders. The hook tells Claude (via `additionalContext`) which file was used and to fill in the placeholders before compaction completes. |
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
| 1 | `adopt` | Use that path (e.g. `docs/Checkpoint.md`) |
| 2+ with one at root | `ambiguous-root` | Use root copy, warn about duplicates |
| 2+ without root copy | `ambiguous-fallback` | Use shortest path (lex tiebreaker), warn |

The status and a human-readable note are passed to Claude in
`additionalContext` so the user always knows which file is in play.

## Verification (already done at build time)

- All bash scripts pass `bash -n` syntax check.
- `settings.json` parses as valid JSON.
- End-to-end smoke tests across **five resolution scenarios**:
  - No files anywhere → `create` at root.
  - Only `docs/Checkpoint.md` exists → `adopt` that path.
  - Root + `docs/` both have files → `ambiguous-root`, root wins,
    warning surfaced.
  - `docs/` + `notes/2026/` both have files (no root copy) →
    `ambiguous-fallback`, shortest path wins, warning surfaced.
  - Decoys in `.git`, `node_modules`, `dist` → pruned, treated as
    "no file found".
- All five scenarios produce correctly-formatted Checkpoint.md stubs
  and clean `additionalContext` JSON output.

## Uninstall

```bash
rm -rf .claude/hooks/ensure-checkpoint-files.sh \
       .claude/hooks/append-checkpoint.sh \
       .claude/commands/EOD_Summary.md \
       .claude/commands/persona-roundtable.md \
       .claude/commands/llm-audit.md \
       .claude/agents/{ceo,cfo,cto,pm,software-engineer,qa,llm-researcher}-persona.md
# Remove the three hook entries from .claude/settings.json by hand,
# or restore from .bak if the installer made one.
# Checkpoint.md and EOD_Summary.md persist unless you delete them.
```
