---
description: Write a minimal failing reproducer BEFORE attempting any bug fix
argument-hint: "<bug description or ticket reference>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(*)
---

# /repro

Build a minimal failing reproducer for: **$ARGUMENTS**

This command is a **gate**. Until a failing test exists that
demonstrates the bug, the system refuses to attempt a fix. This
mirrors disciplined debugging: red → green → refactor.

## Phase 1 — Understand the bug

1. Read the bug description / ticket carefully.
2. Identify the affected code by `Grep`-ing for keywords from the
   description. Capture file:line citations.
3. State the bug in one sentence using the format:
   "Given <input X>, expected <Y>, observed <Z>."
   If you cannot fill in all three, refuse to proceed and ask the
   user for the missing piece. **Do not guess.**

## Phase 2 — Locate or create the test file

1. Find the existing test file for the affected module via `Glob`.
2. If none exists, create one in the project's standard test path
   (mirror the existing test layout).
3. Pick a test name that includes the bug ID or a short descriptor:
   `test_<short_descriptor>_reproduces_<bug_id>`.

## Phase 3 — Write the failing test

Write a test that:
- Sets up the minimal input that triggers the bug.
- Asserts the EXPECTED behavior (not the buggy one).
- Has zero dependencies on external state (no live network, no
  actual DB unless the project uses a test DB fixture).

## Phase 4 — Verify it actually fails

Run the test in isolation (`pytest path::name`, `npm test -- -t name`,
`go test -run`, etc.). Capture the exact failure output. The test
MUST fail BEFORE the fix — that's what makes it a reproducer.

If the test passes unexpectedly:
- The bug isn't reproduced. Dig deeper before claiming victory.
- Possibilities: timing-dependent, environment-dependent, the bug
  was already fixed, or your understanding is wrong. Investigate.

## Phase 5 — Output

Print:

```
## Reproducer ready

**Bug:** <one-sentence statement>
**Test file:** <path>
**Test name:** <name>
**Failure command:** <exact command>
**Failure output (last 20 lines):**
\`\`\`
...
\`\`\`

Next steps:
1. Now you may attempt the fix. Implementation must make THIS test
   pass without breaking any currently-passing test.
2. After the fix, the test commit should reference the failure mode
   in its message.
```

## Hard rules

- **No fix attempts in this command.** /repro produces a failing test
  and stops. The user (or a follow-up implementer) writes the fix.
- **No mocking the bug away.** If the bug only reproduces against a
  specific dependency version or environment, the test must pin
  that — don't add a mock that hides the underlying cause.
- **Cite, don't speculate.** Every claim about how the code works
  must come from a file you read in this session.
