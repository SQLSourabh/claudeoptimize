---
description: Declare the file scope of this session (used by scope-creep guard)
argument-hint: "<comma-separated paths or globs>  e.g.  src/auth/, tests/auth/, *.md"
allowed-tools: Bash(python:*)
---

# /scope

Declare the file scope of this session: **$ARGUMENTS**

The `scope-guard` PreToolUse hook reads this declaration and warns
when an edit is about to land on a file outside the declared scope.
This is a **nudge**, not a block — it pauses Claude so the user can
confirm or expand scope.

## Items syntax

Comma-separated. Each item is one of:
- exact path: `src/auth.py`
- directory prefix: `src/auth/`  (note trailing slash)
- glob: `*.py`, `tests/**/test_*.py`

## What this command does

1. Get the current `session_id` from `additionalContext` (or the most
   recent SessionStart context).
2. Parse `$ARGUMENTS` into a JSON array of items.
3. Call the helper:
   ```
   python .claude/hooks/_session_state.py set-scope <session_id> '<json-array>'
   ```
4. Print a confirmation listing the declared items and reminding the
   user that edits outside this set will trigger a `scope-guard`
   warning until they /scope again to expand.

## Safety

- If $ARGUMENTS is empty, print current scope (no change).
- If no session_id is available, print: "Cannot declare scope yet —
  session_id not in context. Wait for the next assistant turn."
