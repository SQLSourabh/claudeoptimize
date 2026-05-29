# Claude Code Optimization Pack — Distribution

Two ready-to-deploy packages of the optimization pack. Both packages
are functionally identical — same `CLAUDE.md`, same persona agents,
same slash commands, same evidence-first rules. They differ only in
the hook implementation language so each platform runs natively.

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
  **append** a structured stub, then instruct Claude to fill in the
  placeholders with cited content before compaction completes.
- `/EOD_Summary [YYYY-MM-DD]` resolves the same way (via `Glob`),
  rolls up the day's checkpoint blocks into a new section of
  `EOD_Summary.md`. Never edits prior content.

### Goal 2 — Multi-persona roundtables (vanilla, no plugins)
`/persona-roundtable <scope>` runs four phases:
1. **Establish facts** — build `facts.md` (the single source of
   truth all personas may cite).
2. **Parallel dispatch** — 9 personas in one round-trip:
   - Bespoke: CEO, CFO, CTO, PM, Staff Software Engineer, QA Lead,
     LLM Researcher (these are local persona files).
   - Built-in `general-purpose` with embedded prompt templates:
     Independent Code Reviewer, Security Engineer.
3. **Cross-examination** — every "QUESTIONS FOR OTHER PERSONAS" is
   routed via `SendMessage` so personas literally talk to each
   other.
4. **Synthesis** — orchestrator writes `report.md` with consensus,
   disagreements, unanimous risks, and open human questions.

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
linux-macos/install.sh                              : bash -n OK
linux-macos/.claude/hooks/_lib.sh                   : bash -n OK
linux-macos/.claude/hooks/ensure-checkpoint-files.sh: bash -n OK
linux-macos/.claude/hooks/append-checkpoint.sh      : bash -n OK
linux-macos/.claude/settings.json                   : JSON valid
linux-macos resolution scenarios (5/5 PASS):
  - no files anywhere       -> create at root
  - only docs/ has files    -> adopt docs/ path
  - root + docs/ both       -> ambiguous-root, root wins, warn
  - docs/ + notes/2026/     -> ambiguous-fallback, shortest wins, warn
  - decoys in pruned dirs   -> pruned, treated as no-match

windows/install.ps1                              : PSParser OK
windows/.claude/hooks/_lib.ps1                   : PSParser OK
windows/.claude/hooks/ensure-checkpoint-files.ps1: PSParser OK
windows/.claude/hooks/append-checkpoint.ps1      : PSParser OK
windows/.claude/settings.json                    : JSON valid
windows resolution scenarios (5/5 PASS):
  - same five scenarios pass on Windows PowerShell 5.1
  - 8.3 short-name path canonicalization fixed (Get-Item, not Resolve-Path)
  - additionalContext JSON output is clean UTF-8
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
