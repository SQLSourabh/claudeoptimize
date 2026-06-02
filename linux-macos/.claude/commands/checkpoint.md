---
description: Fill in the narrative sections (Goals / Decisions / Open / Blockers) of a Checkpoint block by reading the session's transcript. Manual; not auto-invoked.
argument-hint: "[--from-transcript <path-to-jsonl>]"
allowed-tools: Read, Edit, Glob, Bash(python:*)
---

# /checkpoint

Fill in the four narrative sections of a Checkpoint block — Goals,
Decisions made, Open / In-flight, Blockers — by reading the
session's transcript and synthesizing language-level content.

This command is **manual** — the PreCompact / Stop hook captures
deterministic facts (files touched, bash exit codes, slash
commands invoked) but cannot capture narrative because hooks
cannot wait for Claude to think. Run `/checkpoint` whenever you
want narrative committed.

## Argument modes

| Mode | Syntax | What it does |
|---|---|---|
| **default** | `/checkpoint` | Upgrade the **latest** block in `Checkpoint.md` — the one most recently appended by the hook. Replaces the four `<!-- Claude: fill in via /checkpoint -->` placeholders with cited narrative. |
| **recover / re-target** | `/checkpoint --from-transcript <path>` | Read the supplied JSONL transcript. Compute its `block_id` (sha8 of `session_id + transcript_path`). Search `Checkpoint.md` for an existing block whose `checkpoint-meta` footer matches the `block_id` and upgrade it. If no matching block exists, **append a new block** at the end of the file with both deterministic facts AND narrative filled in. Use this to recover narrative for sessions whose blocks were lost or never written. |

## Step 0 — Resolve `Checkpoint.md`

Use the same logic as `/EOD_Summary` Step 0: `additionalContext`
from `SessionStart` if available, otherwise `Glob` for
`**/Checkpoint.md` (skipping `.git/**`, `node_modules/**`,
`.venv/**`, `dist/**`, `build/**`, `.claude/**`, `.agents/**`)
with the same multi-match priority (root preferred, shortest
path tiebreaker).

If no `Checkpoint.md` exists AND `--from-transcript` was passed,
create one at project root with the standard header (the same
header the hook bootstraps) before appending.

## Step 1 — Determine target block

### Default mode

1. Read `Checkpoint.md` in full.
2. Find every line matching `^## Checkpoint @ ` and pick the
   **latest** (last occurrence, since the file is append-only).
3. Within that block, locate the `<!-- checkpoint-meta: ... -->`
   footer and parse `transcript=<path>`.
4. The transcript path is your synthesis source.
5. If no block exists OR the latest block has no
   `checkpoint-meta` footer → ERROR. Tell the user: "No latest
   block found with a checkpoint-meta pointer. Either run a
   session under the v2 hook, or use `--from-transcript`."

### --from-transcript mode

1. Read the supplied JSONL.
2. Run the transcript reader to compute `block_id` and parse
   `session_id`:
   ```
   python .claude/hooks/_transcript_reader.py <path> --json
   ```
   The JSON output includes `block_id` and `session_id`.
3. Read `Checkpoint.md` and search every block's
   `checkpoint-meta` footer for one with `block_id=<value>`.
4. If found → that block is your target (upgrade in place).
5. If not found → your target is a NEW block appended to the
   end of the file, populated with BOTH deterministic
   sections (files touched, bash, slash) AND narrative.

## Step 2 — Read transcript & synthesize narrative

Read the transcript (`Read`) and use it to populate the four
sections. **Cite turn timestamps or message IDs** for every
non-trivial claim.

### Goals for this session

1–3 bullets describing what the user set out to do. Anchor on:
- The first user message of the session (cite its timestamp).
- Any `/spec` or `/scope` invocations (cite each).
- Topic shifts that introduce new goals — cite the user
  message.

If goals genuinely cannot be determined from the transcript,
write `(no clear goal stated in transcript)` rather than
inventing.

### Decisions made

For each significant assistant response that contains a
decision-shaped statement (e.g., "I'll use X because Y",
"recommend deferring Z", "the right fix is..."), record:

- The decision (one sentence).
- Cited turn timestamp.
- Evidence: `file:line` or command output the assistant used
  to ground the decision.

Skip decisions that are just acknowledgments ("OK",
"understood"). Capture decisions with consequences.

### Open / In-flight

Items the assistant or user mentioned but did not resolve:

- Tests that were attempted but failed (cite the failed bash
  command from the transcript).
- TODOs the assistant added to its own messages but didn't
  complete.
- Files mentioned for future modification (cite the message).

### Blockers / Unresolved questions

Anything explicitly flagged as `NEEDS-HUMAN-INPUT`,
`NEEDS-LEGAL-REVIEW`, or `NEEDS-VERIFICATION` in the
transcript. Plus any final-message open question — if the
last few messages contain unanswered questions to the human,
those are blockers.

## Step 3 — Write back

### Default mode (in-place upgrade)

Use `Edit` to replace each of the four placeholder strings
within the targeted block:

- `<!-- Claude: fill in via /checkpoint -->` (Goals section)
- `<!-- Claude: fill in via /checkpoint -->` (Decisions section)
- `<!-- Claude: fill in via /checkpoint -->` (Open section)
- `<!-- Claude: fill in via /checkpoint -->` (Blockers section)

Each `Edit` must match enough surrounding context (the
section heading + the placeholder) to be unique. If a prior
`/checkpoint` already filled in a section, **replace the
existing narrative** for that section (re-running is
idempotent at the section level — latest run wins).

### --from-transcript mode → matching block found

Same as default mode — in-place upgrade of the matching block.

### --from-transcript mode → no matching block (append)

Build a complete block from scratch:

1. Header line: `## Checkpoint @ <last_event_ts from transcript>`.
2. Date / Session ID / Transcript fields.
3. **Files touched** — render via:
   ```
   python .claude/hooks/_transcript_reader.py <path> --markdown=files \
     --edits-json='[]'
   ```
   (For recovery, you don't have session-state edits; rely on
   transcript-derived files written if present.)
4. **Verification evidence** — render via `--markdown=bash`.
5. **Slash commands invoked** — render via `--markdown=slash`.
6. The four narrative sections **filled in** (not placeholders).
7. `checkpoint-meta` footer with the recovered `session_id`,
   `transcript`, `block_id`.
8. `---` separator.

Append the entire new block to `Checkpoint.md`.

## Step 4 — Verify append-only

After `Edit` (default mode) or append (--from-transcript-new
mode), verify:

1. Re-read the file.
2. Every prior `## Checkpoint @ ` block other than the target
   block must be **byte-identical** to its pre-write state.
   Read both halves of the file (before and after the target
   block) and confirm.
3. If verification fails, the file write is corrupt — ERROR
   loudly and tell the user to roll back via `git diff` /
   `git checkout`. Do NOT attempt to auto-repair.

## Step 5 — Confirmation report

Print exactly this report to chat after the write:

```
/checkpoint update — <mode> mode
- Target file:           <resolved Checkpoint.md path>
- Mode:                  default | from-transcript-existing | from-transcript-new
- Transcript:            <path>
- block_id:              <id>
- Block timestamp:       <## Checkpoint @ ts>
- Sections filled:       Goals | Decisions | Open | Blockers
- Bytes changed:         <N> (inside target block only)
- Append-only verified:  yes | NO — file may be corrupted, see error
- Citations attached:    <count>
```

## Hard rules

- **Cite, don't summarize vaguely.** "Worked on auth" is bad.
  "Refactored auth/session.py:142 to remove the null-deref;
  verified by `pytest tests/auth/ -k session` exit 0 at
  14:32" is good.
- **No fabrication.** If the transcript is sparse, the
  narrative sections are sparse. Better one cited bullet than
  five invented ones.
- **Append-only at file level.** Edits are confined to the
  target block. Prior blocks must be byte-identical
  pre/post-write. The verification step is mandatory.
- **Idempotency.** Re-running `/checkpoint` on the same block
  replaces the narrative sections in place — never appends a
  duplicate block, never double-writes within a section.
- **No auto-invocation.** This command is manual. Do NOT
  prompt the user to run it; the hook's `additionalContext`
  already does that. If this command is invoked
  programmatically (e.g., from another slash command), abort
  with: "/checkpoint must be invoked manually."

## Examples

```
# Most common: capture today's session narrative.
/checkpoint

# Recovery: a session ran before the hook contract landed; you
# still have the JSONL.
/checkpoint --from-transcript ~/.claude/projects/proj-X/old-session.jsonl

# Recovery: an older block in the file is incomplete.
/checkpoint --from-transcript /path/to/that-session.jsonl
# → if a block with matching block_id exists, upgrade it in
# place; otherwise append.
```
