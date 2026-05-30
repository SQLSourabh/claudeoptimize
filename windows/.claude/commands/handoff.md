---
description: Produce a structured "next session starts here" handoff doc
argument-hint: "[topic]  (optional — defaults to inferring from session)"
allowed-tools: Read, Write, Edit, Bash(git:*), Glob
---

# /handoff

Produce a structured handoff document optimized for **resuming work
across sessions**. This is different from `/EOD_Summary` (which is
historical) — this is forward-looking and operational.

## Output

Append to `.agents/artifacts/handoffs/<topic-slug>.md`. **Always
append-only.** Each session's handoff is a new section, dated.

## Required sections

```
## Handoff @ <ISO timestamp>  —  <topic>

### Where we are right now
- Current branch: `<git branch --show-current>` (cite output)
- Last commit: `<git log -1 --oneline>` (cite output)
- Working tree: clean / dirty (cite `git status -s`)

### Last known good
- Last verified-passing commit: <sha> (cite `git log` if there's a
  test-passed marker, else state OPINION)
- Last verifying command + exit code: <command> → 0

### In-progress files (uncommitted)
- <path>:<line ranges> — <one-sentence purpose of the change>
  (cite `git diff --stat`)

### Open decisions
- <decision> — options on the table — what's needed to resolve

### Blockers
- <blocker> — what would unblock — owner

### Exact next command to run
- `<command>` — runs the test that's currently red, OR continues
  the partially-written feature, OR resumes the failed deploy.
- This must be SOMETHING the next session can copy-paste verbatim.
- If you don't know what to run, that's a blocker — list it above.

### Context gotchas
- Things the next session would NOT notice from `git status` alone.
  Examples: a feature flag is on, a stub was inserted, a config
  value was overridden, a personal API key is in `.env.local`.

### Pointer to artifacts
- Spec: <path>
- Latest checkpoint: <path>
- ADR: <path>
- Roundtable / audit reports: <paths>
```

## Hard rules

- **Operational, not historical.** Don't recap what we did — that's
  what `Checkpoint.md` and `EOD_Summary.md` are for. Focus on what
  the next session needs to STARTUP fast.
- **Every claim cited.** "Branch is clean" → run `git status -s`.
  "Tests pass" → run them and cite the exit code.
- **The "exact next command" is a contract.** It must work without
  modification when pasted into a fresh session. If you can't
  produce one, mark it as "no clear next step — read the spec
  again" rather than guessing.
- **Append-only.** Never delete or rewrite a prior handoff section.
  Future sessions can read the historical sequence.

After writing, print only: file path, byte offset of the new
section, and the "exact next command" so the user can act on it.
