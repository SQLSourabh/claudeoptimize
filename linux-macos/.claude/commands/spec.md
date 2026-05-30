---
description: Produce a structured spec before any implementation work
argument-hint: "<feature name or one-line description>"
allowed-tools: Read, Write, Glob, Grep, Bash(git:*)
---

# /spec

Produce a structured spec for: **$ARGUMENTS**

Specs are mandatory before implementation work. They force the
front-loaded thinking that vibe coders skip and leave a record that
later investigations can audit.

## Output

Write the spec to `.agents/artifacts/specs/<slug>-<timestamp>.md`
where `<slug>` is a kebab-case version of the title.

## Required sections

```
# Spec: <title>

## Problem
- **What is broken / missing today?** (one sentence + cited file:line evidence)
- **Who is affected?** (cite a file, ticket, or user statement; no fabrication)
- **Why now?** (forcing function — deadline, blocker, dependent work)

## Non-goals
- Bullet list of explicitly out-of-scope items.
- Each non-goal should be a thing a reviewer might reasonably ASSUME
  is included; calling it out prevents scope creep.

## Acceptance criteria
- Numbered, falsifiable. Each criterion includes the verifying command
  and expected exit code (or expected output).

## Test plan
- For each acceptance criterion, the test that proves it.
- Format: `<test file path>::<test name> — exercises <criterion N>`
- Mark which tests already exist vs need to be written.

## Implementation sketch
- Bullet list of files to change, in order.
- Each bullet has: file path, type of change (new / edit / delete),
  one-sentence purpose.
- DO NOT write code here — just locations.

## Risks / unknowns
- Things that could invalidate the plan. Each one labeled
  FACT (cited) | INFERENCE (reasoning shown) | OPINION.

## Rollback plan
- How do we undo this change if it causes issues in production?
- Migration reversibility, feature flag, revert commit, etc.

## Effort estimate
- T-shirt size (XS/S/M/L/XL) with rationale based on similar past work
  in this repo. Cite a comparable PR or commit if possible. If no
  comparable work exists, mark as OPINION.

## Open questions for the human
- List anything the spec couldn't resolve from the codebase alone.
```

## Hard rules

- **No fabrication.** Every cited fact must come from a file you read
  or a command whose output you have. If unsure, list under "Open
  questions" instead of inventing.
- **Refuse to start coding.** If the user pivots from spec to "now
  implement it," remind them the spec needs human approval first.
- **Write to disk.** Don't summarize the spec in chat instead of
  writing the file. Print just the path + section count when done.
- **Idempotent.** If a spec with the same slug already exists for
  today, append `-v2`, `-v3`, etc. — never overwrite.

After writing, also append a one-line summary to
`.agents/artifacts/specs/INDEX.md` (create if missing, append-only):
`- <date> | <slug> | <one-sentence problem statement> | <path>`
