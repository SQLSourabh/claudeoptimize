---
description: Roll up today's Checkpoint.md entries into EOD_Summary.md (append-only)
argument-hint: "[YYYY-MM-DD] (optional, defaults to today UTC)"
allowed-tools: Read, Edit, Bash(date:*), Glob
---

# /EOD_Summary

You are producing the **End-of-Day Summary** for the date $1 (or today UTC
if $1 is empty). Follow this contract exactly.

## Step 0 — Resolve file locations

Do NOT assume `Checkpoint.md` and `EOD_Summary.md` live at project
root. The SessionStart hook resolves them dynamically and surfaces
the chosen paths in `additionalContext` at session start. If you
have those paths in context, use them. Otherwise:

1. Use `Glob` to find every `**/Checkpoint.md` and
   `**/EOD_Summary.md`, excluding `.git/**`, `node_modules/**`,
   `.venv/**`, `venv/**`, `dist/**`, `build/**`, `.next/**`,
   `target/**`, `__pycache__/**`, `.claude/**`, `.agents/**`.
2. Apply the same resolution rules as the hook:
   - 0 matches → ERROR. Do not fabricate. Tell the user to start a
     fresh session so the hook creates the file.
   - 1 match → use that path.
   - 2+ matches → if a root-level copy exists, use it; else pick
     the shortest path (lex tiebreaker) AND warn the user that
     multiple copies exist and should be consolidated.
3. Record the resolved paths at the top of your reasoning before
   reading anything. Use those paths consistently for the rest of
   the command.

## Inputs

1. Read the resolved `Checkpoint.md` in full.
2. Identify every `## Checkpoint @ <ISO-timestamp>` block whose date
   matches the target date.
3. If zero matching blocks exist, append a section that explicitly says
   "No checkpoints recorded for <date>." and stop. Do NOT fabricate.

## Output (append to the resolved EOD_Summary.md, never overwrite)

Append a new top-level section in this exact shape:

```
## EOD Summary — <YYYY-MM-DD>

### Sessions included
- <session_id> @ <timestamp>  (one line per checkpoint block consumed)

### Completed / Resolved today
- <bullet> — evidence: <file:line | command + exit code | PR link>

### Decisions made
- <bullet> — rationale: <one sentence> — evidence: <citation>

### Still open / In-flight
- <bullet> — owner: <name or "unassigned"> — next step: <one sentence>

### Blockers / Unresolved questions
- <bullet> — what is needed to unblock

### Files touched (deduplicated across sessions)
- created: <paths>
- modified: <paths>
- deleted: <paths>

### Verification log (facts only)
- <command> → <exit code> (<one-line interpretation>)

---
```

## Rules

- **Append-only.** Never modify or delete any prior section of
  `EOD_Summary.md`. Use `Edit` with the file's current trailing content
  as `old_string` plus the new section appended, OR read the file and
  rewrite by appending — but verify with `Read` afterward that no prior
  content changed.
- **No hand-waving.** Every bullet must trace back to a checkpoint
  block. If a checkpoint placeholder was left unfilled
  (`<!-- Claude: ... -->`), record it as `(checkpoint incomplete)`
  rather than inventing content.
- **Deduplicate** across multiple sessions on the same day; if two
  sessions both touched `foo.py`, list it once.
- **Cite, don't summarize vaguely.** "Fixed auth bug" is bad.
  "Fixed null-deref in `auth/session.py:142` — verified by
  `pytest tests/auth/ -k session` exit 0" is good.

After appending, print a 5-line confirmation: target date, count of
checkpoint blocks consumed, count of bullets in each section, and the
byte offset where the new section starts.
