# Claude Code Optimization Pack — Linux / macOS

Drop-in scaffolding that wires four behaviors into any Claude Code
project on Linux or macOS:

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
- `bash` (every Linux distro and macOS ships it).
- `python` on PATH. **Required** for the SDLC scanner hooks
  (secrets-guard, scope-guard, test-first, blast-radius). The
  checkpoint hooks degrade gracefully if `python` is absent (they
  still append, just without session_id metadata), but the SDLC
  hooks become inactive.
- `find`, `awk`, `sort`, `head`, `cut`, `sed` (POSIX standard).

## Install

```bash
# From the pack directory:
bash install.sh                      # install into the current directory
bash install.sh /path/to/project     # install into a specific project
```

The installer is idempotent. If `CLAUDE.md` or `.claude/settings.json`
already exist, it backs them up and writes companion files
(`CLAUDE.optimization.md`, `settings.json.bak`) for manual merge.

The installer **glob-copies all `*.sh` and `*.py`** from the source
`hooks/` directory — adding new hooks to the source pack does not
require editing the installer.

## Pack contents

```
.
├── install.sh                              # idempotent installer
├── CLAUDE.md                               # evidence-first project rules
└── .claude/
    ├── settings.json                       # hooks: SessionStart, PreToolUse,
    │                                       #        PostToolUse, PreCompact, Stop
    ├── hooks/                              # 8 shell wrappers + 5 python helpers
    │   ├── _lib.sh                         # shared file-location resolver
    │   ├── _secrets_scan.py                # credential pattern scanner
    │   ├── _test_first.py                  # test-edit detector
    │   ├── _scope_guard.py                 # in-scope checker
    │   ├── _blast_radius.py                # call-site counter
    │   ├── _session_state.py               # session-state helper
    │   ├── ensure-checkpoint-files.sh      # SessionStart
    │   ├── append-checkpoint.sh            # PreCompact + Stop
    │   ├── secrets-guard.sh                # PreToolUse — BLOCKS on credential
    │   ├── scope-guard.sh                  # PreToolUse — WARNS off-scope
    │   ├── test-first-enforcer.sh          # PreToolUse — WARNS no test yet
    │   ├── blast-radius.sh                 # PreToolUse — WARNS widely-imported
    │   └── edit-recorder.sh                # PostToolUse — silent state
    ├── commands/                           # 10 slash commands
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
    └── agents/                             # 13 persona files; 7 at v2 rigor
        ├── ceo-persona.md                  # v2 — 428 lines, full rigor
        ├── cfo-persona.md                  # v2 — 523 lines, full rigor
        ├── cto-persona.md                  # v2 — 412 lines, full rigor
        ├── architect-persona.md            # v2 — 471 lines, full rigor
        ├── pm-persona.md                   # v2 — 554 lines, full rigor (strategic + execution regimes)
        ├── software-engineer-persona.md    # v2 — 521 lines, full rigor
        ├── qa-persona.md                   # v1
        ├── llm-researcher-persona.md       # v2 — 602 lines, full rigor
        ├── devops-sre-persona.md           # v1
        ├── data-engineer-persona.md        # v1
        ├── ux-copy-persona.md              # v1
        ├── compliance-privacy-persona.md   # v1
        └── api-steward-persona.md          # v1
```

## How it works

### Hooks (auto-fire)

| Hook | Event | Tool match | Behavior |
|---|---|---|---|
| `ensure-checkpoint-files.sh` | `SessionStart` | * | Resolves `Checkpoint.md` / `EOD_Summary.md` location (tree scan, skips `.git` / `node_modules` / `.venv` / `dist` / `build` / etc.). Adopts existing files; creates at root only when none found. |
| `secrets-guard.sh` | `PreToolUse` | `Write\|Edit\|Bash` | **BLOCKS** when content contains AWS / GitHub / Anthropic / OpenAI / Stripe / Slack / Google tokens, RSA private keys, JWTs, or generic secret-name literals. Allowlist for `.env.example` / `fixtures/secrets/`. |
| `scope-guard.sh` | `PreToolUse` | `Write\|Edit` | WARNS when an edit lands outside the scope declared via `/scope`. |
| `test-first-enforcer.sh` | `PreToolUse` | `Write\|Edit` | WARNS when editing a source file with no test edited yet this session. Bypass via `[refactor]` / `no-test-needed` markers or `CLAUDE_SKIP_TEST_FIRST=1`. |
| `blast-radius.sh` | `PreToolUse` | `Write\|Edit` | WARNS when editing a file imported in 20+ places (default threshold; tune via `CLAUDE_BLAST_RADIUS_THRESHOLD`). |
| `edit-recorder.sh` | `PostToolUse` | `Write\|Edit` | Silent — records edits in `.claude/state/<session_id>.json` for the other nudge hooks. |
| `append-checkpoint.sh` | `PreCompact` + `Stop` | * | Appends a structured stub to `Checkpoint.md` and tells Claude to fill in placeholders before compaction completes. |

### Slash commands

| Command | Purpose |
|---|---|
| `/scope <items>` | Declare session scope (paths / dirs / globs). Read by `scope-guard`. |
| `/spec <feature>` | Produce a structured spec before code (problem, non-goals, acceptance, test plan, rollback). |
| `/repro <bug>` | Build a minimal failing test BEFORE attempting any fix. |
| `/adr <title>` | Record an immutable, numbered Architecture Decision (`docs/adr/NNNN-...`). |
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
| 1 | `adopt` | Use that path (e.g. `docs/Checkpoint.md`) |
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

## Verification (build-time)

- All `*.sh` scripts: `bash -n` clean.
- All `*.py` helpers: parse-clean.
- `settings.json`: valid JSON.
- Installer smoke test: copies all 13 hook files (8 shell + 5 python),
  sets executable bit on `*.sh`, creates target directory tree.
- Checkpoint resolution: 5/5 scenarios pass (no files / one file in
  subdir / ambiguous-root / ambiguous-fallback / pruned-decoys).
- secrets-guard: 12/12 scenarios pass (clean code, AWS/Anthropic/
  GitHub/Stripe/RSA/JWT detection, allowlist paths, placeholders,
  generic password literals).
- nudge-hook integration: 9/9 scenarios pass (scope-guard,
  test-first, blast-radius — both warning and silent paths).

## Uninstall

```bash
rm -rf .claude/hooks/_*.{sh,py} \
       .claude/hooks/{ensure-checkpoint-files,append-checkpoint,secrets-guard,scope-guard,test-first-enforcer,blast-radius,edit-recorder}.sh \
       .claude/commands/{EOD_Summary,persona-roundtable,llm-audit,scope,spec,repro,adr,pr-preflight,handoff,retro}.md \
       .claude/agents/{ceo,cfo,cto,architect,pm,software-engineer,qa,llm-researcher,devops-sre,data-engineer,ux-copy,compliance-privacy,api-steward}-persona.md
# Remove the hook entries from .claude/settings.json by hand,
# or restore from .bak if the installer made one.
# Checkpoint.md and EOD_Summary.md persist unless you delete them.
```
