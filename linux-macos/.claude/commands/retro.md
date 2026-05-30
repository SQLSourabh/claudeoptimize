---
description: Session retrospective — what worked, what didn't, propose CLAUDE.md updates
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash(git:*)
---

# /retro

Session retrospective. **Five-minute exercise**, structured.

## Output

Append to `.agents/artifacts/retros/<YYYY-MM-DD>.md`. Append-only.

## Required sections

```
## Retro @ <ISO timestamp>

### What went well (3 bullets max)
- <bullet> — evidence: <citation>

### What didn't go well (3 bullets max)
- <bullet> — evidence: <citation>
  - root cause (one sentence)
  - what would prevent recurrence

### Time / token sinks
- <activity> — estimated impact (citing token / time tracker if
  available, else label OPINION)

### Lessons that should be encoded as rules
- <lesson> — proposed CLAUDE.md edit:
  ```
  <exact diff: section X, replace Y with Z>
  ```
  - This is a PROPOSAL. It is NOT applied automatically. The user
    decides whether to merge it via a follow-up Edit.

### Lessons that should NOT become rules
(things that are project-specific or one-off — call them out so
they don't bloat CLAUDE.md)

### One thing to try differently next session
- <single concrete experiment>
```

## Hard rules

- **No pseudo-improvements.** "Be more careful" is invalid.
  "Run `npm run typecheck` before claiming the build passes" is
  valid (specific, falsifiable, easy to verify next session).
- **CLAUDE.md proposals are OPT-IN.** Print the proposed diff but
  do NOT apply it. The user reviews and decides.
- **Cite session evidence.** Every "didn't go well" should reference
  a specific commit, exit code, or `additionalContext` log.

After writing, print: retro path + the lessons-to-encode count + a
prompt: "Want to apply any of the proposed CLAUDE.md edits? Reply
with the lesson number(s)."
