---
description: Roll up Checkpoint.md entries into EOD_Summary.md (append-only). Supports today, a specific date, catch-up since the last entry, or an explicit date range.
argument-hint: "[YYYY-MM-DD] | [--since-last] | [--range YYYY-MM-DD..YYYY-MM-DD]"
allowed-tools: Read, Edit, Bash(date:*), Glob
---

# /EOD_Summary

Roll up `Checkpoint.md` blocks into `EOD_Summary.md`. Multiple
invocation modes — pick exactly one.

## Argument modes

| Mode | Syntax | Behavior |
|---|---|---|
| **today** (default) | `/EOD_Summary` | Summarize today (UTC). |
| **specific date** | `/EOD_Summary 2026-05-30` | Summarize one date. |
| **catch-up** | `/EOD_Summary --since-last` (alias `--catchup`) | Find the latest `## EOD Summary — <date>` heading already in `EOD_Summary.md`. Summarize every date from the day AFTER that through today (inclusive). If the file has no prior EOD heading, summarize from the earliest checkpoint date through today. |
| **explicit range** | `/EOD_Summary --range 2026-05-29..2026-05-31` | Summarize each date in the inclusive range. |

The modes are **mutually exclusive**. Passing more than one is an
error. If `$ARGUMENTS` is empty, default to **today**.

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
   - 0 matches → ERROR. Do not fabricate. Tell the user to
     start a fresh session so the hook creates the file.
   - 1 match → use that path.
   - 2+ matches → if a root-level copy exists, use it; else pick
     the shortest path (lex tiebreaker) AND warn the user that
     multiple copies exist and should be consolidated.
3. Record the resolved paths at the top of your reasoning before
   reading anything. Use those paths consistently for the rest of
   the command.

## Step 1 — Resolve the target-date list

Parse `$ARGUMENTS` and produce a list of target dates in
`YYYY-MM-DD` form (UTC, sorted ascending).

### Mode A — today (default)

`$ARGUMENTS` is empty.

```
target_dates = [today_utc]
```

### Mode B — specific date

`$ARGUMENTS` is a single token matching `^\d{4}-\d{2}-\d{2}$`.

```
target_dates = [<that date>]
```

### Mode C — catch-up (`--since-last` or `--catchup`)

1. Read `EOD_Summary.md` in full.
2. Find every `## EOD Summary — <YYYY-MM-DD>` heading, in order.
3. Take the **maximum** date — call it `last_eod_date`.
4. Resolve the target list:

| Condition | Target list |
|---|---|
| No prior `## EOD Summary —` headings exist | All dates from the **earliest** `## Checkpoint @ <date>` in `Checkpoint.md` through today (inclusive). |
| `last_eod_date < today` | All dates from `last_eod_date + 1` through today (inclusive). |
| `last_eod_date == today` | **No-op.** Print: "EOD already current — last entry is today (`<date>`). Nothing to do." Stop. |
| `last_eod_date > today` | **ERROR.** "EOD_Summary.md contains a future-dated section (`<date>`). Refusing to backfill 'past' entries when the file is already past today. Resolve manually before retrying." |

Cap the resulting target list at **30 dates**. If the gap is
larger, summarize only the most recent 30 dates and **warn**:
"Catch-up window exceeded 30 days; summarized the most recent 30.
Re-run with `--range` for a larger window."

### Mode D — explicit range (`--range <start>..<end>`)

Parse the token after `--range`. Must match
`^\d{4}-\d{2}-\d{2}\.\.\d{4}-\d{2}-\d{2}$`.

```
target_dates = [start, start+1, ..., end]   (inclusive, UTC)
```

Reject if `start > end`. Reject if any date is in the future
(beyond today UTC). Cap at 90 dates; if larger, error rather than
truncate (explicit-range users probably mean it).

### Mode collision

If more than one mode is requested (e.g., a positional date AND
`--since-last`), abort with:
"Mode collision: pick one of <today|date|--since-last|--range>."

## Step 2 — Per-date summarization

For each target date in the resolved list:

1. Read `Checkpoint.md` in full (read once; reuse across dates).
2. Identify every `## Checkpoint @ <ISO-timestamp>` block whose
   date matches the target date.
3. If zero matching blocks exist, the section for that date is:

   ```
   ## EOD Summary — <YYYY-MM-DD>

   No checkpoints recorded for <YYYY-MM-DD>.

   ---
   ```

   Do NOT fabricate.

4. Otherwise, build the section in this exact shape:

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

## Step 3 — Append (atomic per invocation)

Concatenate the per-date sections in date-ascending order, then
append the entire concatenation to `EOD_Summary.md` in a single
write. **Never modify or delete any prior section.**

Use `Edit` with the file's current trailing content as
`old_string` plus the new sections appended, OR read the file
and rewrite by appending — then verify with `Read` afterward
that no prior content changed.

## Step 4 — Confirmation report

Print exactly this report to chat after appending:

```
EOD_Summary update — <mode> mode
- Target file: <resolved EOD_Summary.md path>
- Dates processed: <N>
  - <date1>: <K1 checkpoint blocks consumed | "no checkpoints recorded">
  - <date2>: <K2 checkpoint blocks consumed | ...>
  - ...
- New section bytes appended: <N>
- File size before: <bytes>
- File size after: <bytes>
- Append-only verified: <yes — first <N> bytes unchanged>
- Warnings: <list, or "none">
```

## Rules

- **Append-only.** Never modify or delete any prior section of
  `EOD_Summary.md`. Always verify post-write that the file's
  pre-existing prefix is byte-identical to its pre-write state.
- **No hand-waving.** Every bullet traces back to a checkpoint
  block. If a checkpoint placeholder was left unfilled
  (`<!-- Claude: ... -->`), record it as `(checkpoint incomplete)`
  rather than inventing content.
- **Deduplicate** across multiple sessions on the same day; if
  two sessions both touched `foo.py`, list it once.
- **Cite, don't summarize vaguely.** "Fixed auth bug" is bad.
  "Fixed null-deref in `auth/session.py:142` — verified by
  `pytest tests/auth/ -k session` exit 0" is good.
- **Idempotency.** Re-running `--since-last` after a successful
  run should produce the no-op message ("EOD already current"),
  not duplicate sections.
- **UTC throughout.** Dates derived from `## Checkpoint @
  <ISO-timestamp>Z` are interpreted in UTC. The user can pass
  any date string; treat it as a UTC calendar date.

## Examples

```
# Default — today
/EOD_Summary

# Specific date
/EOD_Summary 2026-05-30

# Catch up since the last EOD entry (most common new use case)
/EOD_Summary --since-last

# Explicit window
/EOD_Summary --range 2026-05-25..2026-05-31

# Error cases
/EOD_Summary 2026-05-30 --since-last
  → "Mode collision: pick one of today|date|--since-last|--range."

/EOD_Summary --range 2026-06-01..2026-05-29
  → "Range start must precede end."
```
