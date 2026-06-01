# Usage Guide — Claude Code Optimization Pack

End-to-end examples for every command and hook in the pack. Skim
the table of contents, jump to what you need.

> Convention used in this guide:
> - `> ...` lines are what **you type to Claude in chat**.
> - Code fences are what **Claude or your shell prints back**.
> - The pack assumes a `CLAUDE_PROJECT_DIR` is set to the project
>   root by Claude Code (which it does automatically).

---

## Table of contents

**Hooks (auto-fire, no command needed)**

- §1. [secrets-guard](#1-secrets-guard) — blocks credential leaks
- §2. [scope-guard](#2-scope-guard) — warns on out-of-scope edits
- §3. [test-first-enforcer](#3-test-first-enforcer) — nudges TDD
- §4. [blast-radius](#4-blast-radius) — warns on widely-imported files
- §5. [edit-recorder](#5-edit-recorder) — silent state collector
- §6. [SessionStart / PreCompact / Stop checkpoint hooks](#6-checkpoint-hooks) — session memory

**Slash commands**

- §7. [/scope](#7-scope) — declare session scope
- §8. [/spec](#8-spec) — structured spec before code
- §9. [/repro](#9-repro) — failing test before fix
- §10. [/adr](#10-adr) — architecture decision record
- §11. [/pr-preflight](#11-pr-preflight) — pre-push verdict
- §12. [/handoff](#12-handoff) — next-session resumption doc
- §13. [/retro](#13-retro) — session retrospective
- §14. [/EOD_Summary](#14-eod_summary) — daily rollup
- §15. [/persona-roundtable](#15-persona-roundtable) — multi-perspective review
- §16. [/llm-audit](#16-llm-audit) — LLM output forensics

**Personas (used inside /persona-roundtable)**

- §17. [Persona reference](#17-persona-reference) — when to invoke each

**Workflows (combining commands)**

- §18. [Building a new feature, end-to-end](#18-workflow-new-feature)
- §19. [Fixing a production bug](#19-workflow-bug-fix)
- §20. [Reviewing someone else's PR](#20-workflow-pr-review)
- §21. [Auditing a Claude prompt](#21-workflow-prompt-audit)
- §22. [Resuming after a long break](#22-workflow-resumption)

**Ops**

- §23. [Configuration knobs](#23-configuration)
- §24. [Disabling hooks temporarily](#24-disabling-hooks)
- §25. [Troubleshooting](#25-troubleshooting)

---

# Hooks

These run automatically. You don't invoke them — you see them act.

## 1. secrets-guard

**Fires:** `PreToolUse` on `Write`, `Edit`, or `Bash`.
**Behavior:** **BLOCKS** the call when credential patterns are
detected outside an allowlisted path or placeholder context.

### What it catches

| Pattern | Example match |
|---|---|
| AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| AWS Secret Access Key | `aws_secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"` |
| GitHub PAT / OAuth | `ghp_...`, `gho_...`, `github_pat_...` |
| Anthropic API key | `sk-ant-...` |
| OpenAI API key | `sk-...` (20+ chars) |
| Stripe live key | `sk_live_...`, `pk_live_...` |
| Slack bot token | `xoxb-...` |
| Google API key | `AIza...` |
| RSA / OpenSSH private key block | `-----BEGIN RSA PRIVATE KEY-----` |
| JWT | `eyJ....eyJ....<sig>` |
| Generic secret assignment | `password = "P@ssw0rd-real-prod-1234"` |

### When it allows

| Bypass | How |
|---|---|
| Allowlist path | `.env.example`, `.env.template`, `fixtures/secrets/`, `tests/**/fixtures/`, `docs/*.md`, the hook itself |
| Placeholder syntax | `${VAR_NAME}`, `<YOUR_KEY_HERE>`, `process.env.KEY`, `os.environ["X"]`, `os.getenv("X")`, `getenv("X")`, `XXXX...`, `YOUR_..._HERE` |

### Example: it BLOCKS

> Edit src/config.py to set `STRIPE_KEY = "<a real-looking sk_live_... value>"`

```
[BLOCKED by secrets-guard: tool 'Edit' would write 1 suspected
credential(s) into src/config.py.
  - Stripe Live Key: sk_l…<masked>  (line: 'STRIPE_KEY = "sk_live_..."')

Resolve by ONE of:
(a) replace the literal with a placeholder like ${VAR_NAME} or
    <YOUR_KEY_HERE>;
(b) move the value to .env / .env.example with a placeholder;
(c) if this is intentional test data, write to a file under
    fixtures/secrets/ which is on the allowlist.]
```

Claude will then propose:

```python
# src/config.py
STRIPE_KEY = os.environ["STRIPE_KEY"]
```

Plus an addition to `.env.example`:

```
STRIPE_KEY=<YOUR_STRIPE_LIVE_KEY_HERE>
```

### Example: it ALLOWS (allowlist path)

> Add `AWS_KEY=AKIAIOSFODNN7EXAMPLE` to `.env.example` so contributors know the format.

The hook silently allows because `.env.example` is on the allowlist.

### Example: it ALLOWS (placeholder)

> Write `src/auth.py` so it reads the GitHub token from the environment.

```python
# src/auth.py
TOKEN = os.environ["GITHUB_TOKEN"]
```

The pattern `os.environ[` is a placeholder marker, so the hook
allows even if there's a real-looking literal nearby.

### When the hook decides wrong

If you genuinely need a credential-shaped string in source (e.g.,
a public test vector or a documented sample value), put it under
`fixtures/secrets/` — that path is allowlisted.

If you've hit a false positive that **should** be allowed, see
[Troubleshooting](#25-troubleshooting) for how to tune patterns.

---

## 2. scope-guard

**Fires:** `PreToolUse` on `Write` or `Edit`.
**Behavior:** WARNS (does not block) when an edit lands outside
the scope declared via `/scope`. Surfaces `additionalContext`
asking Claude to confirm or expand scope.

### Example session

> /scope src/auth/, tests/auth/

```
Scope set:
  - src/auth/
  - tests/auth/
Edits outside this set will trigger a scope-guard warning.
```

> Now refactor the password hashing in src/auth/password.py.

(Claude edits `src/auth/password.py` — **silent**, in scope.)

> Also bump the version in pyproject.toml.

```
[scope-guard] SCOPE WARNING: about to edit pyproject.toml,
which is OUTSIDE the declared session scope (src/auth/, tests/auth/).
Either: (a) confirm this edit is necessary and explain why in
your next message, or (b) update the scope via /scope to add
this file/pattern.
```

> Yes that's fine, it's part of the auth refactor release. Update scope.

> /scope src/auth/, tests/auth/, pyproject.toml

(Subsequent edits to `pyproject.toml` are silent.)

### Scope item syntax

- `src/auth.py` — exact file
- `src/auth/` — directory prefix (note trailing slash)
- `*.md` — glob
- `tests/**/test_*.py` — recursive glob

---

## 3. test-first-enforcer

**Fires:** `PreToolUse` on `Write` or `Edit` of source files.
**Behavior:** WARNS when editing a `.py / .js / .ts / .go / ...`
file if **no test file has been edited** yet this session. Skips
docs / config / migrations / examples / scripts.

### What's a "test file"

The hook recognizes:
- Anything under `tests/`, `test/`, `__tests__/`
- `_test.go`
- `test_*.py`, anything starting with `test_`
- `*.test.{js,ts,jsx,tsx}`, `*.spec.{js,ts,jsx,tsx}`

### Example: nudges

> Add a JWT verifier function to src/auth/jwt.py.

```
[test-first] NUDGE: about to edit a source file (src/auth/jwt.py),
but no test file has been edited yet this session. Best practice
for new behavior is: write the failing test FIRST, see it fail,
then implement.

If this edit is for a refactor / docs / configuration / obvious
bugfix, include `no-test-needed` or `[refactor]` in the file
content (a comment is fine), or set env var
CLAUDE_SKIP_TEST_FIRST=1 for the session.

Proceeding without a test is allowed — this is a nudge, not a
block. But please justify briefly in your next message why a
test isn't required.
```

Claude will typically respond by writing the test first:

> I'll write the failing test first. Creating `tests/auth/test_jwt.py`...

After that, subsequent source edits are silent because a test
edit has been recorded.

### Bypass

**Per-edit (in content):**

```python
# [refactor] renaming for clarity, no behavior change
def verify_jwt(token): ...
```

Or any of: `no-test-needed`, `[skip test-first]`, `[refactor]`.

**Per-session (env var):**

Set `CLAUDE_SKIP_TEST_FIRST=1` before launching Claude Code, e.g.,
when the session is purely docs / formatting / dependency bumps.

---

## 4. blast-radius

**Fires:** `PreToolUse` on `Write` or `Edit` of an existing source file.
**Behavior:** WARNS when the file's basename is imported in **20+
places** (configurable). Surfaces a count + sample call sites.

### Example

> Refactor src/utils.py to use a dict instead of a tuple.

(Suppose `utils` is imported in 47 places.)

```
[blast-radius] BLAST RADIUS WARNING: src/utils.py appears to be
imported in 47+ places (threshold: 20).
Sample call sites:
  - app/handlers/login.py:3
  - app/handlers/logout.py:3
  - app/handlers/signup.py:5
  - app/middleware/auth.py:7
  - app/services/user.py:2
Consider whether this change needs: a deprecation shim, a
backwards-compatible alias, or a coordinated update of call sites.
If the change is purely internal (no API or contract change),
this warning can be ignored.
```

### Tuning the threshold

Set `CLAUDE_BLAST_RADIUS_THRESHOLD` before launching Claude Code:

```bash
# Linux/macOS
CLAUDE_BLAST_RADIUS_THRESHOLD=10 claude

# Windows PowerShell
$env:CLAUDE_BLAST_RADIUS_THRESHOLD=10; claude
```

### When it doesn't fire

- The file you're editing doesn't exist yet (creating new files).
- The file isn't a recognized source extension.
- Fewer call sites than the threshold.

---

## 5. edit-recorder

**Fires:** `PostToolUse` on `Write` or `Edit`.
**Behavior:** **Silent.** Records the edit in
`.claude/state/<session_id>.json` so other hooks (test-first,
scope-guard) can read session-wide context.

You will never see this hook produce output. It exists so the
nudge hooks above can know what's happened earlier in the session.

The state file is automatically scoped to the session and is
stored under `.claude/state/`. Add this directory to `.gitignore`
if you don't already have a broad `.claude/state` ignore:

```
# .gitignore
.claude/state/
```

---

## 6. Checkpoint hooks

Three hooks share a contract for `Checkpoint.md` and `EOD_Summary.md`:

| Hook event | What happens |
|---|---|
| `SessionStart` | Scans the project for existing `Checkpoint.md` / `EOD_Summary.md`. Adopts a single match; creates at root if zero matches; warns on duplicates. |
| `PreCompact` | Appends a structured stub to the resolved `Checkpoint.md` and tells Claude to fill in the placeholders before compaction completes. |
| `Stop` | Same as `PreCompact` — guarantees a checkpoint even if compaction never runs. |

### What you'll see at session start

If files don't exist:

```
[additionalContext]
Checkpoint resolution: Checkpoint.md (create). No existing
Checkpoint.md found in project tree; will create at project
root. EOD resolution: EOD_Summary.md (create). ... Append-only
contract: NEVER overwrite either file.
```

If a file exists at `docs/Checkpoint.md`:

```
[additionalContext]
Checkpoint resolution: docs/Checkpoint.md (adopt). Adopted
existing Checkpoint.md at docs/Checkpoint.md (single match in
tree). ...
```

If two copies exist (e.g., root + docs):

```
[additionalContext]
Checkpoint resolution: Checkpoint.md (ambiguous-root). WARNING:
2 Checkpoint.md files found in tree (Checkpoint.md,
docs/Checkpoint.md). Using Checkpoint.md. Consolidate to a
single file to silence this warning. ...
```

Read more in [README → Goal 1](./README.md#goal-1--auto-managed-checkpoint--eod-rollup).

---

# Slash commands

## 7. /scope

**Purpose:** Declare which files / directories / globs are in
scope for this session. Read by `scope-guard`.

**Syntax:** `/scope <comma-separated items>`

### Example

> /scope src/payments/, tests/payments/, docs/payments.md

```
Scope set:
  - src/payments/
  - tests/payments/
  - docs/payments.md
Edits outside this set will trigger a scope-guard warning.
```

### Show current scope

> /scope

```
Current scope (declared at 2026-05-30T01:42:11Z):
  - src/payments/
  - tests/payments/
  - docs/payments.md
```

### Clear scope

> /scope (none)

Or simply call `/scope` with no items to inspect; to actually
clear, declare `/scope **` (everything in scope).

---

## 8. /spec

**Purpose:** Force a structured spec **before** any implementation
work. Catches scope creep, missing acceptance criteria, and
hand-wavy plans early.

**Output:** `.agents/artifacts/specs/<slug>-<timestamp>.md` plus
an entry in `.agents/artifacts/specs/INDEX.md`.

### Example

> /spec rate-limiter on /api/login

Claude produces (writes to file):

```markdown
# Spec: rate-limiter on /api/login

## Problem
- **What is broken / missing today?** /api/login has no rate
  limit (cited at src/routes/login.py:14 — middleware list lacks
  any throttle).
- **Who is affected?** Risk to all users from credential-stuffing
  attacks; cited from docs/threat-model.md:line 47.
- **Why now?** Pen-test report 2026-Q2 flagged this as P1 — cited.

## Non-goals
- Bot detection beyond IP-based throttling.
- Per-account locking (separate work).
- Distributed rate limiter — single-node Redis is sufficient.

## Acceptance criteria
1. 6+ failed logins in 60s from same IP → 429 with Retry-After.
   Verify: `pytest tests/security/test_login_rate_limit.py -v` → 0.
2. Limit is per-IP, not per-username (verified by test 2).
3. Successful login resets counter (test 3).
4. ...

## Test plan
- tests/security/test_login_rate_limit.py::test_blocks_after_6 — exercises 1
- tests/security/test_login_rate_limit.py::test_per_ip — exercises 2
- (NEW — needs writing)

## Implementation sketch
- `src/middleware/rate_limit.py` (new): Redis-backed token bucket
- `src/routes/login.py` (edit): wire middleware
- `src/config.py` (edit): add LIMITER_REDIS_URL config

## Risks / unknowns
- INFERENCE: existing Redis instance has bandwidth headroom — no
  current metrics in repo, flag for human verification.

## Rollback plan
- Feature flag LIMITER_ENABLED defaults off; toggle off to revert.

## Effort estimate
- M (similar to PR #1234, 2-day work). cited.

## Open questions for the human
- Should bypass list (internal IPs) be config or hard-coded?
```

### Tell Claude to start coding from the spec

> ok the spec looks right. Implement it.

Claude will refuse to start without your explicit approval (per
the spec.md rules) and may also refuse without a failing test
(per `/repro` workflow). Combine with `/repro` to make this hard.

---

## 9. /repro

**Purpose:** Build a minimal **failing test** before any bug-fix
attempt. The command is a gate — it produces red, not green.

**Output:** A test file that fails when run, plus a saved record
of the failure command and output.

### Example

> /repro Login rejects valid passwords containing emoji

Claude:
1. `Grep`s the codebase for password handling — cites
   `src/auth/password.py:24`.
2. States the bug: "Given a password containing 🦄, expected
   `verify_password` returns True, observed it returns False."
3. Locates `tests/auth/test_password.py`; adds:
   ```python
   def test_emoji_password_reproduces_issue_842():
       hashed = hash_password("hello🦄world")
       assert verify_password("hello🦄world", hashed) is True
   ```
4. Runs `pytest tests/auth/test_password.py::test_emoji_password_reproduces_issue_842 -v`.
5. Confirms it FAILS:
   ```
   AssertionError: assert False is True
   ```
6. Prints the reproducer summary:
   ```
   ## Reproducer ready
   Bug: Given password "hello🦄world", expected verify_password=True, observed False
   Test file: tests/auth/test_password.py
   Test name: test_emoji_password_reproduces_issue_842
   Failure command: pytest tests/auth/test_password.py::test_emoji_password_reproduces_issue_842 -v
   Failure output (last 20 lines): ...
   Next steps:
   1. Now you may attempt the fix. Implementation must make THIS test pass without breaking any currently-passing test.
   ```

> Now fix it.

Claude diagnoses (probably an encoding / byte-vs-string mismatch),
patches `src/auth/password.py`, re-runs the test → green, runs the
full suite → all green.

### When the test "passes" unexpectedly

If the failing test you wrote passes on the first run, the bug
isn't actually reproduced. Possibilities the command will surface:
- timing / environment dependent
- already fixed
- your understanding of the bug is wrong

It will not "just close the ticket" — you have to dig deeper.

---

## 10. /adr

**Purpose:** Record an immutable, numbered Architecture Decision
Record. Captures **why** a decision was made.

**Output:** `docs/adr/<NNNN>-<slug>.md` plus a row in `docs/adr/README.md`.

### Example

> /adr Move session storage from in-memory to Redis

Claude:
1. `Glob`s `docs/adr/NNNN-*.md` to find the next number (suppose `0017`).
2. Writes `docs/adr/0017-move-session-storage-to-redis.md`:
   ```markdown
   # ADR 0017: Move session storage from in-memory to Redis

   - Status: Accepted
   - Date: 2026-05-30
   - Deciders: human + cto-persona + devops-sre-persona

   ## Context
   In-memory session storage (cited at src/auth/sessions.py:12)
   does not survive process restarts. We just rolled out
   horizontal scaling (cited at infra/k8s/auth.yaml) so logged-in
   users now bounce randomly between pods, getting logged out.

   ## Decision
   Use Redis with a 24-hour TTL for session storage.

   ## Options considered
   1. Sticky load-balancing
      - Pros: minimal code change.
      - Cons: defeats horizontal-scaling rebalancing; cited at
        ADR-0011 §"Why we abandoned sticky".
      - Rejected.
   2. JWT in cookie (stateless)
      - Pros: zero infra. Cons: revocation is hard; cited at
        threat-model.md:line 91.
      - Rejected.
   3. Redis (chosen)
      - Pros: existing Redis cluster; revocation is `DEL key`.
      - Cons: now session reads are network calls.

   ## Consequences
   - All session reads become Redis calls; observability MUST
     include a redis-call latency histogram.
   - Rollback requires data migration.

   ## Verification
   - `kubectl exec auth-pod-0 -- redis-cli KEYS 'session:*' | wc -l`
     returns >0 after first login.
   ```
3. Appends to `docs/adr/README.md`:
   ```markdown
   - [ADR-0017: Move session storage from in-memory to Redis](./0017-move-session-storage-to-redis.md) — 2026-05-30 — In-memory sessions don't survive horizontal scaling; switch to Redis with TTL.
   ```

### Superseding a prior ADR

> /adr Switch from Redis to ValKey (supersedes ADR-0017)

Claude writes ADR-0042 with a `Supersedes: ADR-0017` line, AND
edits the *single* allowed field on the old ADR — `Superseded by:`
— to point at the new one. No other field on the old ADR is
mutated.

---

## 11. /pr-preflight

**Purpose:** Run **every** pre-push check on your current branch
and produce a verdict before you create a PR.

**Modes:**

- `/pr-preflight` — warnings allowed
- `/pr-preflight --strict` — warnings count as failures

### What gets run (auto-detected)

- `npm run lint` / `npm run typecheck` / `npm test` (if `package.json`)
- `pytest`, `ruff check`, `mypy` (if Python config files exist)
- `go vet ./...`, `go test ./...` (if `go.mod`)
- `cargo clippy`, `cargo test` (if `Cargo.toml`)
- `pre-commit run --all-files` (if `.pre-commit-config.yaml`)
- Plus universal checks: secrets-on-diff, conventional-commit,
  line-budget, TODO/FIXME budget, test/source ratio, generated-files
  check, branch-sanity (refuses pushing to main).

### Example

> /pr-preflight

```
## /pr-preflight verdict — 2026-05-30
Branch: feature/rate-limiter
Diff size: 7 files, +312/-18 lines

### Checks run (8)
| Check | Result | Time | Detail |
|---|---|---|---|
| npm run lint | PASS | 4.2s | 0 errors |
| npm run typecheck | PASS | 6.8s | |
| npm test | PASS | 12.1s | 47 tests, 0 failures |
| secrets-scan-on-diff | PASS | 0.3s | clean |
| conventional-commit-check | PASS | 0.1s | "feat(auth): add rate limiter" |
| line-budget | WARN | - | src/middleware/rate_limit.py +287 lines |
| todo-budget | PASS | - | 1 new TODO (limit: 5) |
| test/source ratio | PASS | - | 4 source / 4 test edits |

### Failures (0)

### Warnings (1)
- line-budget: src/middleware/rate_limit.py +287 lines
  - recommendation: split implementation across submodules

### VERDICT: PASS (with 1 warning)

Ready to push: `git push origin feature/rate-limiter`
```

### Example: --strict mode catches the warning

> /pr-preflight --strict

```
### VERDICT: FAIL

Required fixes:
1. line-budget: src/middleware/rate_limit.py +287 lines exceeds
   500-line file budget. Split before pushing.
```

---

## 12. /handoff

**Purpose:** Forward-looking "next session starts here" doc.
Different from `Checkpoint.md` (which is a log) — this is
**operational**, with the exact next command to run.

**Output:** Appends to `.agents/artifacts/handoffs/<topic>.md`.

### Example

> /handoff rate-limiter

Claude runs `git status`, `git log -1`, `git diff --stat` and writes:

```markdown
## Handoff @ 2026-05-30T18:42:11Z — rate-limiter

### Where we are right now
- Current branch: `feature/rate-limiter` (cited)
- Last commit: `f3a9b21 feat(auth): add Redis rate limiter middleware` (cited)
- Working tree: dirty — 2 modified files (cited git status -s)

### Last known good
- Last verified-passing commit: f3a9b21 (cited /pr-preflight at 18:30)
- Last verifying command: `pytest tests/security/ -v` → 0

### In-progress files (uncommitted)
- src/routes/login.py:1-30 — wiring middleware into the route
- tests/security/test_login_rate_limit.py:120-160 — adding the
  per-IP isolation test

### Open decisions
- Whether to bypass internal IPs (10.0.0.0/8). Awaiting infra-team input.

### Blockers
- (none)

### Exact next command to run
- `pytest tests/security/test_login_rate_limit.py::test_per_ip -v`
- This is the test currently red. Make it green, then run
  /pr-preflight before pushing.

### Context gotchas
- LIMITER_REDIS_URL is in .env.local (not committed) — copy from
  .env.example and fill in.
- Feature flag LIMITER_ENABLED is OFF in dev; turn on with
  `export LIMITER_ENABLED=1` before testing manually.

### Pointer to artifacts
- Spec: .agents/artifacts/specs/rate-limiter-2026-05-30.md
- Latest checkpoint: Checkpoint.md (last block @ 18:42)
- ADR: docs/adr/0017-move-session-storage-to-redis.md (related)
```

### Tomorrow's first prompt becomes trivial

> Read .agents/artifacts/handoffs/rate-limiter.md and resume from "Exact next command to run".

---

## 13. /retro

**Purpose:** Five-minute session retrospective. Proposes (does NOT
auto-apply) `CLAUDE.md` edits to encode lessons.

**Output:** Appends to `.agents/artifacts/retros/<YYYY-MM-DD>.md`.

### Example

> /retro

```markdown
## Retro @ 2026-05-30T18:55:00Z

### What went well
- /spec caught that "rate limiter" without per-IP scope was
  ambiguous (cited spec.md§Acceptance criteria).
- /repro forced a real reproducer for the off-by-one — saved
  ~30min of speculation.

### What didn't go well
- I claimed the test passed without re-running after the patch
  (cited transcript turn 14 — said "should pass now" but ran
  pytest only at turn 18).
  - root cause: skipped verification step under time pressure
  - prevention: enforce explicit "verifying command + exit code"
    block in every "done" claim.

### Lessons that should be encoded as rules
- Lesson 1: "Done" claims must include the verifying command's
  output in the same message. Proposed CLAUDE.md edit:
  ```
  Section 1.6 — append:
  - When claiming "done", "fixed", or "passing", include the
    EXACT verifying command output in the same message. A
    one-line summary like "tests pass" is insufficient.
  ```

### Lessons that should NOT become rules
- The Redis-vs-Memcached debate was project-specific.

### One thing to try differently next session
- Run /pr-preflight BEFORE writing the commit message, not
  after.
```

### Apply a proposed lesson

> Apply lesson 1 to CLAUDE.md.

Claude makes the targeted Edit to CLAUDE.md (and ONLY that edit).

---

## 14. /EOD_Summary

**Purpose:** Roll up today's `Checkpoint.md` blocks into a daily
summary section in `EOD_Summary.md`. Append-only.

**Syntax:** `/EOD_Summary [YYYY-MM-DD]`  (default = today UTC)

### Example

> /EOD_Summary

```markdown
## EOD Summary — 2026-05-30

### Sessions included
- sess-abc-123 @ 14:02
- sess-def-456 @ 18:42

### Completed / Resolved today
- Rate-limiter middleware wired into /api/login —
  evidence: src/routes/login.py:14, pytest exit 0
- ADR-0017 written and accepted —
  evidence: docs/adr/0017-...md

### Decisions made
- Use Redis (not Memcached) for session storage — rationale:
  ADR-0011 §"Why we abandoned sticky" — evidence: ADR-0017

### Still open / In-flight
- Per-IP isolation test — owner: me — next step: pytest
  tests/security/test_login_rate_limit.py::test_per_ip

### Blockers / Unresolved questions
- Bypass list for internal IPs — awaiting infra team

### Files touched (deduplicated)
- created: src/middleware/rate_limit.py,
           tests/security/test_login_rate_limit.py
- modified: src/routes/login.py, src/config.py
- deleted: (none)

### Verification log (facts only)
- pytest tests/security/ -v → 0
- /pr-preflight → PASS (with 1 warning)
```

### Backfill yesterday

> /EOD_Summary 2026-05-29

Same format, scoped to that date's checkpoint blocks. If no blocks
match, the section says "No checkpoints recorded for 2026-05-29."
— never fabricates.

---

## 15. /persona-roundtable

**Purpose:** Multi-perspective evidence-grounded review of a
change, scope, or decision. Up to 15 personas in parallel, then
cross-examination, then synthesis.

**Syntax:**

```
/persona-roundtable <topic|path|gitref|brief.md> [--brief] [--exclude N,M,...] [--only N,M,...]
```

`--exclude` and `--only` are mutually exclusive. Default
(no flag) = full set, then relevance-gated.

### Topic kinds

The orchestrator classifies the topic before doing anything else:

| Kind | Detection | Example |
|---|---|---|
| **brief** | `--brief` flag, or `.md` file whose H1 starts with `# Roundtable brief:` | `proposals/postgres-migration.md` |
| **gitref** | matches `A..B`, or starts with `HEAD`, `origin/`, `pull/` | `HEAD~5..HEAD` |
| **path** | exists on disk OR contains `/` or `*` | `src/auth/`, `*.py` |
| **freetext** | none of the above | `"Should we adopt pgvector?"` |

If the topic is a `.md` path AND `--brief` is not given AND the H1
doesn't match the brief signature, the orchestrator asks
explicitly which interpretation you want — it will not guess.

### Brief mode (the .md-as-instructions case)

A **brief** is a markdown file describing what to evaluate. The
personas read the brief as instructions and then apply their
lenses to the actual subject the brief points at — they do **not**
review the brief file itself.

Use this when the question is too rich for one chat line:
- Multi-paragraph context
- Several files to consider together
- Specific concerns worth pinning
- An out-of-scope list to preempt persona drift

#### Minimal brief

```markdown
# Roundtable brief: Should we migrate from MySQL to Postgres?

## Question
Evaluate whether migrating our primary OLTP DB from MySQL 8 to
Postgres 16 is worth the cost and risk over the next two
quarters. Decision needed by end of Q3.

## Context
- We currently run MySQL 8 on RDS (cited from infra/rds.tf:14).
- Volume: ~2TB, 4k QPS p99, 99.95% SLO.
- Files of interest:
  - infra/rds.tf
  - schema/migrations/
  - docs/perf/2026-Q1-review.md
- Related artifacts:
  - docs/adr/0008-chose-mysql.md (the decision being revisited)

## Specific concerns
- Operational complexity during the transition.
- Vendor / RDS pricing delta.
- Application-layer changes required (ORM, raw SQL).

## Out of scope
- NoSQL / NewSQL alternatives — this is MySQL→Postgres only.

## Suggested ordinals (advisory)
2, 3, 4, 11, 12
(CFO, CTO, Architect, DevOps, Data Engineer)
```

#### Run it

> /persona-roundtable proposals/postgres-migration.md

The H1 starts with `# Roundtable brief:`, so brief mode triggers
automatically. No flag needed.

The orchestrator:

1. Reads the brief in full.
2. Pulls the `## Question` into facts.md as the personas' charge.
3. Reads every path under `Files of interest` and `Related
   artifacts`, including excerpts in facts.md.
4. Surfaces `## Specific concerns` to each persona as priority
   focus areas.
5. Honors `## Out of scope` by adding it as a hard rule per
   persona prompt.
6. If `## Suggested ordinals` is present, prints a hint:
   ```
   Brief suggests ordinals [2, 3, 4, 11, 12]. Apply via --only
   or ignore. Spawning full set.
   ```
   Does NOT auto-apply. You'd run with `--only 2,3,4,11,12` if
   you want to honor the suggestion.

#### Combine with --only / --exclude

> /persona-roundtable proposals/postgres-migration.md --only 2,3,4,11,12

Forces only the brief's suggested ordinals.

> /persona-roundtable proposals/postgres-migration.md --exclude 1

Full set minus CEO.

#### Schema

| Section | Required | Purpose |
|---|---|---|
| `# Roundtable brief: ...` (H1) | Yes (auto-detect signal) | Triggers brief mode automatically |
| `## Question` | **Yes** | The personas' charge — what to evaluate |
| `## Context` | No | Background + `Files of interest:` + `Related artifacts:` |
| `## Specific concerns` | No | Priority focus areas |
| `## Out of scope` | No | Hard rule: personas won't address these |
| `## Suggested ordinals` | No | Informational hint shown to user |

If `## Question` is missing, the orchestrator aborts and asks
you to fix the brief.

#### When the topic is `.md` but isn't a brief

If you point at a `.md` that doesn't have the `# Roundtable
brief:` H1 (e.g., a README, a design doc you want personas to
critique as a doc), don't pass `--brief`:

> /persona-roundtable docs/api-design.md

The personas review the doc itself — its prose, structure,
accuracy, completeness. This is the original behavior.

If the orchestrator can't tell, it asks:

```
Topic is a .md file. Two interpretations:
  1. Treat as an artifact to review (current behavior).
  2. Treat as a brief — instructions for what to evaluate.
Pass --brief to choose option 2, or confirm option 1.
```

### Persona ordinal list

The ordinals are stable — adding new personas appends, never
renumbers.

| # | Persona | Short name(s) | Default-relevance trigger |
|---|---|---|---|
| 1 | CEO | `ceo` | always |
| 2 | CFO | `cfo` | always |
| 3 | CTO / CIO | `cto`, `cio` | always |
| 4 | Software Architect | `architect`, `arch` | new modules / deps / layers |
| 5 | Project Manager | `pm`, `project-manager` | always |
| 6 | Staff Software Engineer | `staff-eng`, `engineer`, `eng` | code in scope |
| 7 | Independent Code Reviewer | `reviewer`, `code-reviewer`, `independent` | code in scope |
| 8 | Security Engineer | `security`, `sec` | code in scope |
| 9 | QA Lead | `qa`, `qa-lead` | code in scope |
| 10 | ML/AI LLM Researcher | `llm`, `llm-researcher`, `researcher` | LLM prompt / agent / output |
| 11 | DevOps / SRE | `devops`, `sre`, `devops-sre` | infra / deploy / release-impacting |
| 12 | Data Engineer | `data`, `data-engineer`, `de` | DB / ETL / events / pipelines |
| 13 | UX / Copy | `ux`, `copy`, `ux-copy` | user-facing surface |
| 14 | Compliance / Privacy | `compliance`, `privacy` | user data |
| 15 | API Steward | `api`, `api-steward`, `steward` | public API / lib exports / CLI flags / config keys / events |

### Selection precedence

Applied in this order:

- **Step 1:** Start with the full set (1–15).
- **Step 2:** If `--only` is given, intersect with that list.
- **Step 3:** Else if `--exclude` is given, subtract that list.
- **Step 4:** Apply the relevance gate (right-most column above).
  Personas listed via `--only` are NOT relevance-gated — your
  explicit instruction wins.
- **Step 5:** Spawn the result.

### Audit before spawn

The orchestrator prints a spawn manifest before dispatching:

```
Roundtable spawn plan
- topic: <resolved topic>
- selection mode: full | only | exclude
- requested: <ordinals as listed by user, normalized>
- after relevance gate: <final ordinals + names>
- skipped (explain): <ordinal — reason>
```

If the resolved set is empty, the orchestrator aborts. The
synthesis report (`report.md`) also includes a **Spawn manifest**
section so any reader can audit which lenses were applied and a
**Coverage gaps** section listing the lenses that were excluded.

### Examples

#### Default — full set (relevance-gated)

> /persona-roundtable origin/main..HEAD

Spawns all 15 personas, then the relevance gate trims those whose
trigger condition isn't met by the diff. For a docs-only change
you might end up with just 1, 2, 3, 5 (CEO/CFO/CTO/PM) since
there's no code, infra, or DB to review.

#### Skip the C-suite for a pure code review

> /persona-roundtable HEAD~1..HEAD --exclude 1,2

```
Roundtable spawn plan
- topic: HEAD~1..HEAD
- selection mode: exclude
- requested: exclude [1, 2] (CEO, CFO)
- after relevance gate: [3, 4, 5, 6, 7, 8, 9, 11]
  (CTO, Architect, PM, StaffEng, Reviewer, Security, QA, DevOps)
- skipped: 10 (no LLM in diff), 12 (no DB), 13 (no UX), 14 (no
  user data), 15 (no public API)
```

#### Mixed ordinals + names

> /persona-roundtable src/payments/ --exclude ceo,cfo,2

Wait — `cfo` resolves to 2, which the user also listed. The
orchestrator de-duplicates: `--exclude 1,2` (CEO + CFO).

#### Only specific personas (forced — no relevance gate)

> /persona-roundtable docs/api.md --only 4,15

```
Roundtable spawn plan
- topic: docs/api.md
- selection mode: only
- requested: only [4, 15] (Architect, API Steward)
- after relevance gate: [4, 15]
  (forced by --only; relevance gate not applied)
- skipped: all others (excluded by --only)
```

You'll get **only** the Architect and API Steward — useful when
you're shipping a documentation update and want focused feedback,
not 15 lenses.

#### Security audit only

> /persona-roundtable HEAD~5..HEAD --only security,qa,reviewer

Forces ordinals 7, 8, 9 — the three code-quality lenses.

#### Strip all the executives

> /persona-roundtable . --exclude 1,2,3,4,5

Skips the C-suite + PM. You're left with just the technical
personas, then relevance-gated.

#### Single-name shorthand

> /persona-roundtable src/auth/ --only security

Just the Security Engineer.

### Error cases

**Both flags:**

> /persona-roundtable HEAD --exclude 1 --only 2

```
ERROR: --exclude and --only are mutually exclusive. Pick one.
```

**Unknown name:**

> /persona-roundtable HEAD --exclude finops

```
ERROR: 'finops' is not a known persona name. Valid names:
  ceo, cfo, cto, cio, architect, arch, pm, project-manager,
  staff-eng, engineer, eng, reviewer, code-reviewer, independent,
  security, sec, qa, qa-lead, llm, llm-researcher, researcher,
  devops, sre, devops-sre, data, data-engineer, de, ux, copy,
  ux-copy, compliance, privacy, api, api-steward, steward
Or use ordinals: 1..15
```

**Empty resolved set:**

> /persona-roundtable . --only ceo --exclude ceo

(Caught earlier — both flags = error.)

> /persona-roundtable . --exclude 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

```
ERROR: spawn set is empty after applying selection. Aborting.
```

### Reading the report

`report.md` is structured exactly:

1. **Spawn manifest** — selection mode + ordinals spawned
2. **Points of consensus** with personas + evidence
3. **Points of disagreement** with each side, evidence, what would resolve
4. **Unanimous risks** — high-confidence concerns
5. **Recommended next steps** with confidence + evidence
6. **Open questions for the human** — including any cross-exam
   question routed to an excluded persona
7. **Coverage gaps** — lenses that were excluded and what they
   would have looked at, so you know what wasn't reviewed

---

## 16. /llm-audit

**Purpose:** Standalone audit of an LLM prompt, agent definition,
or transcript. Powered by the `llm-researcher-persona` (v2 — full
statistical, agentic, and slice-aware rigor).

**Syntax:**

```
/llm-audit <prompt-or-transcript-path>
           [reference-set-path]
           [--tier quick|standard|deep]
```

### Audit-cost tier

The persona enforces evidence requirements that scale with the
tier you pick. A `quick` audit cannot pretend to be `deep` —
the persona's self-check enforces this, and the orchestrator
re-prompts the persona if the report's depth doesn't match the
stated tier.

| Tier | When to use | Inputs the orchestrator requires | Depth of report |
|---|---|---|---|
| **quick** | Pre-commit smell test before a small change ships. | Prompt + at least 1 representative output. Sampling params (temperature, top_p) if available. | Phase A correlational + Phase B HYPOTHESIS-tagged + 1–2 STEPs. No ablations required. |
| **standard** *(default)* | PR-grade audit. Default if no `--tier` flag. | Prompt + ≥10 outputs at temp=0 with the same params; reference set OR existing eval set; tool roster if agentic. | All phases. **Ablation evidence on top 3 drivers.** Slice analysis on existing eval if available. |
| **deep** | Pre-production launch; post-incident root-cause; before promoting a prompt change to a high-stakes path. | Standard + ≥150-prompt sized eval set; LLM-judge validation against ≥50 human-labeled gold-set; cost / latency telemetry. | All phases at full rigor. Reproducibility manifest. Per-slice CIs. Distribution-shift baseline established. |

### Tier resolution rules

| Input | Result |
|---|---|
| `--tier quick` / `--tier standard` / `--tier deep` | Use it |
| `--tier` with any other value | ERROR — list valid tiers, abort |
| `--tier` absent | Default to `standard` |

The orchestrator states the resolved tier at the top of chat
output AND in `report.md`. The persona's self-check rejects any
report whose stated depth doesn't match the resolved tier.

### Tier gating

Before spawning the persona, the orchestrator checks that the
inputs match the tier's requirements:

- `--tier quick` — minimal gating; runs against just a prompt + an output.
- `--tier standard` — refuses to spawn if you have only a single
  output (you'd be asking for a standard audit with quick-tier
  evidence). Asks you to either provide more outputs or downgrade
  to `quick`.
- `--tier deep` — refuses without a sized eval (≥150) and a human
  gold-set (≥50). Lists what's missing. Will downgrade only with
  your explicit confirmation and a stated reason in the report.

This means you can't accidentally get a "deep" audit that doesn't
have the evidence behind it.

### Examples

#### Default (standard tier)

> /llm-audit prompts/triage-agent.md transcripts/2026-Q2.jsonl

```
AUDIT TIER: standard (default)
Inputs OK: prompt, 12 outputs at temp=0, eval set
           (.agents/eval/triage.jsonl, n=87).
Spawning llm-researcher-persona...
```

The persona produces a report with all phases, ablation evidence
on the top 3 drivers, and slice analysis using whatever slices
the eval set defines.

#### Quick — pre-commit smell test

> /llm-audit prompts/triage-agent.md --tier quick

```
AUDIT TIER: quick
Inputs OK: prompt + 1 representative output.
Spawning llm-researcher-persona (depth: quick)...
```

Report is shorter:

- Phase A rows are `Correlational-only` / `Default-by-elimination`
  — no ablation runs.
- Phase B vectors are HYPOTHESIS-tagged with minimal-pair tests
  pending.
- 1–2 STEPs in the action plan with sample-size feasibility
  notes.

Use this in CI on every prompt change to catch regressions, then
run `--tier standard` weekly or before each release.

#### Deep — pre-production launch

> /llm-audit prompts/triage-agent.md eval/gold.jsonl --tier deep

```
AUDIT TIER: deep
Inputs check:
  - prompt: ✓
  - eval set ≥150: ✓ (n=312)
  - human gold-set ≥50: ✓ (eval/gold.jsonl, n=64, κ=0.78)
  - cost/latency telemetry: ✓ (.agents/eval/runs/*.jsonl)
  - tool roster: ✓ (5 tools resolved from agent.md)
Spawning llm-researcher-persona (depth: deep)...
```

The persona produces a full report with:

- Phase 0 reproducibility manifest (model_id, version, temp,
  top_p, seed, prompt sha256, tool roster, RAG corpus revision)
- Phase A with HIGH-confidence rows backed by ablation runs
- Phase A.1 if multi-turn / agentic — turn-by-turn causal path
- Phase B covering both refusal directions + adversarial surface
  + agentic surface
- Phase C with eval-set provenance manifest, per-slice baselines
  with 95% CIs, full metrics tuple `(quality, tokens_in,
  tokens_out, p50, p95, cost_per_call_usd)`
- Phase D with input-side distribution-shift monitoring and a
  `DRIFT.flag` gate

#### Tier downgrade with explicit confirmation

> /llm-audit prompts/agent.md --tier deep

```
AUDIT TIER requested: deep
Missing for deep tier:
  - sized eval set ≥150 prompts (have: 23)
  - human gold-set ≥50 (absent)

Options:
  (a) Provide the missing inputs and rerun.
  (b) Downgrade to standard (--tier standard).
  (c) Explicit override: rerun with --tier deep --acknowledge-missing
      "<reason>". The report will state the limitation prominently.
```

#### Invalid tier

> /llm-audit prompts/agent.md --tier flashy

```
ERROR: invalid tier 'flashy'.
Valid: quick, standard, deep.
```

### What the report contains, by tier

| Section | quick | standard | deep |
|---|---|---|---|
| Reproducibility manifest (Phase 0) | partial — what's available | yes | yes, with hashes |
| Phase A forensics | correlational | ablation on top 3 | ablation on all top concerns + LogProb where API allows |
| Phase A.1 (agentic) | only if multi-turn | yes if multi-turn | yes if multi-turn, with full causal trace |
| Phase B vectors | HYPOTHESIS-tagged | confirmed-by-eval where data exists | confirmed for all in-scope vectors |
| Phase C eval manifest (C.0) | reference only | yes | full provenance + contamination check |
| Phase C metrics tuple | quality only | quality + cost/latency | full tuple per slice |
| Slice analysis | n/a | yes | per-slice CIs + guardrails |
| LLM-judge integrity | n/a | declared if used | judge ≠ system, position-randomized, ≥50 gold validation, κ reported |
| Phase D drift monitoring | n/a | named | full thresholds + flag wiring |
| Alternative hypotheses per concern | optional | required | required |

### Verification (the orchestrator runs before showing you the report)

1. `report.md` states the tier and depth matches.
2. `manifest.json` has Phase 0 fields; unknowns are acknowledged.
3. Every Phase C STEP has all required fields including the full
   metrics tuple, slice analysis, and alternative hypotheses.
4. No banned word appears without a same-sentence citation.
5. Phase A HIGH-confidence rows have ablation or LogProb evidence
   (no token-overlap-only HIGHs).
6. Phase B covers both refusal directions when relevant.
7. Phase A.1 is present if the transcript is multi-turn / agentic.

If verification fails, the orchestrator sends a `SendMessage`
follow-up to the persona with the specific defects and demands a
corrected report. You don't see the broken version.

### Output (sample)

```
AUDIT TIER: standard
Report:    .agents/artifacts/llm-audit-2026-05-30/report.md
Plan:      .agents/artifacts/llm-audit-2026-05-30/plan.json
Manifest:  .agents/artifacts/llm-audit-2026-05-30/manifest.json

TOP CONCERNS:
1. Sycophancy bias — "as an expert, you'd agree that..." in system
   prompt at prompts/triage-agent.md:14
   Confidence: MEDIUM (signal across 5 outputs at temp=0;
                       ablation pending — see STEP 1)
   Alternatives considered:
     - Few-shot exemplars (rejected: removed in test, no change)
     - Format constraint (rejected: not relevant to verdict text)
2. Selection bias in few-shot — 8/10 exemplars are P1 verdicts.
   Confidence: HIGH (count is observable; output P1-rate
                     correlates 0.71 across 23 outputs)

ACTION PLAN STEP 1:
Change: remove "as an expert, you'd agree" from line 14.
Hypothesis: P3-verdict rate increases on ambiguous-evidence cases.
Eval set: .agents/eval/triage.jsonl (n=87, slices: severity,
          domain). MDE at this N: ~7pp.
Metrics tuple (baseline):
  - rubric_score: 2.10 ± 0.12 (n=87)
    per slice: severity-low 1.84, severity-high 2.31
  - tokens_in_avg: 312
  - tokens_out_avg: 184
  - p50_latency_ms: 880
  - p95_latency_ms: 2240
  - cost_per_call_usd: $0.0027
Target: rubric_score 2.30 aggregate, no slice below 2.00.
Falsifier: severity-high slice drops below 2.10, OR
           p95_latency increases >15%, OR
           refusal-rate (under-cautious side) drops below 95%.
Rollback: git revert <commit>.
Alternatives considered:
  - Reword to "evaluate" instead of removing (rejected: still
    framing-loaded per the rubric)
  - Add an explicit "INSUFFICIENT EVIDENCE" exemplar (logged for
    STEP 2)

Next:
  /llm-audit-apply <plan.json>          (apply STEP 1)
  /persona-roundtable <prompt-path>     (cross-functional review)
  manual Edit + re-run /llm-audit       (measure delta)
```

---

# 17. Persona reference

You typically use these inside `/persona-roundtable`, but each
persona file can also be invoked directly via the `Agent` tool if
you need a single lens.

**All 15 personas are file-backed and at v2 rigor** (≥348
lines each, audit-cost tier with `quick`/`standard`/`deep`,
evidence-regime constraints, codified boundary table mapping
every concern to its owner persona, `NEEDS-HUMAN-INPUT` label
for items that aren't inventable, alternative-hypotheses
requirement, expanded banned-phrases lists, multi-item
self-checks that reject reports failing the constraints).
There are no `general-purpose` embedded-prompt personas — the
roundtable dispatches every persona via its file-backed
`subagent_type`.

| Persona | Lines | Main question they answer |
|---|---|---|
| **ceo-persona** | 428 | Should the company be doing this at all? Existential-risk class? Which strategic bet does this advance and what gets starved? External signal to customers / competitors / talent / investors? |
| **cfo-persona** | 523 | Total cost of ownership across full lifecycle (direct + implementation + operating + switching + hidden, amortized 1y/3y/5y)? Unit economics + break-even? Lock-in quantified in person-hours and concentration percentage? Vendor consolidation? Regulatory financial exposure? |
| **cto-persona** | 412 | Production-readiness over time + tech-debt economics (servicing cost, principal, interest)? Platform / portfolio fit? Reliability budget? Velocity tax on adjacent work? |
| **architect-persona** | 471 | Component shape — boundaries, separation of concerns, style fit, build-vs-buy AND buy-vs-build? Coupling rubric, internal blast radius, reversibility classification, evolution stress test, cross-cutting drift? |
| **pm-persona** | 554 | Two regimes: **strategic** (WHAT we ship, WHY now, COMPETE — public-sources-only, internal data is `NEEDS-HUMAN-INPUT`) + **execution** (RAID with structured rows, reference-class estimation, DoD by change-class, commitment / acceptance trace). |
| **software-engineer-persona** | 521 | Diff-class taxonomy + 9-class defect taxonomy + executable reproducer per defect + maintainability rubrics (cyclomatic, dup, length) + testability/DI lens + security-shape flag-and-defer + reviewability + git-shape signals (churn, co-change). |
| **qa-persona** | 348 | Coverage strategy across the **test pyramid** (system-wide, not per-diff) + flakiness verdict + oracle / assertion quality + **negative-space lens** (what the suite cannot detect) + risk-based prioritization (blast radius × bug density). |
| **llm-researcher-persona** | 602 | Three-tier audit (quick/standard/deep) + reproducibility manifest + ablation evidence (not correlation) + slice analysis with CIs + LLM-judge integrity + agentic forensics + cost/latency tuples + distribution-shift monitoring. |
| **devops-sre-persona** | 391 | SLO arithmetic + rollback rigor (runtime + gates + practiced) + **toil instrument** + multi-environment drift + observability content quality + deploy-strategy decision + on-call burden + incident-readiness. |
| **data-engineer-persona** | 443 | Data-quality SLO + lineage (upstream + downstream) + correctness verification + idempotency / replay safety + partitioning + backfill cost + streaming-batch boundary + data contracts + technical retention enforcement. |
| **ux-copy-persona** | 393 | Error-message rubric + copy-quality rubric + empty-state rubric + **WCAG-anchored a11y** + content-design-system fit + missing strings + microcopy hygiene + i18n readiness. |
| **compliance-privacy-persona** | 421 | **13-framework taxonomy** (GDPR, CCPA, HIPAA, GLBA, PCI, SOC 2, ISO 27001, FedRAMP, FERPA, COPPA, DPDP, LGPD, sanctions) + DPIA / RoPA + data-subject rights + cross-border lawful-transfer mechanism + breach-notification readiness + sub-processor + retention min/max + audit-evidence durability. |
| **api-steward-persona** | 414 | Versioning posture + commitment level + **17-row breaking-change subclass taxonomy** with required mitigation per row + deprecation rigor (cited policy, future date, comms, alias) + contract-test matrix + client-diversity assessment + portfolio-drift scan. |
| **security-engineer-persona** | 448 | **Vulnerability surface** — authn/authz endpoint-by-endpoint + injection (per input → sink) + data exposure + crypto API misuse + multi-tenant isolation + dependency-vuln (CVE check via WebFetch) + secrets hygiene + STRIDE / OWASP-Top-10 coverage + trust-boundary check. |
| **independent-reviewer-persona** | 367 | **Second pair of eyes on Staff Engineer's verdict.** AGREEMENT-WITH-STAFF-ENG matrix (CONCUR / CONCUR-WITH-NUANCE / DISSENT per concern) + missed-by-staff section (the value-add) + inference-chain critique + rubric re-validation (independent counts) + handoff-gap detection. Padding forbidden — concurrences are one line each. |

The 15 v2 personas ship with a **codified boundary table** —
each lists every concern in the roundtable and which persona
owns it. When v2 personas run in the same roundtable, all
defer per the same table rather than rediscovering boundaries
at runtime. This eliminates the "three competing strategic
verdicts in one report" failure mode.

### Calling a single persona directly

When you don't need the whole roundtable:

> Use the architect-persona to review src/payments/. Build a small facts.md first, then dispatch.

Claude builds the evidence packet and spawns just that one
persona; you get its structured verdict without the full
roundtable ceremony.

---

# Workflows

## 18. Workflow: new feature

End-to-end flow combining most of the pack:

```mermaid
flowchart TD
    A["User: I want to add a rate limiter"] --> B["/scope src/auth/, tests/auth/"]
    B --> C["/spec rate limiter on /api/login"]
    C --> D{"Spec approved?"}
    D -- "no" --> C
    D -- "yes" --> E["/repro 'no rate limit currently exists' — failing test for the new behavior"]
    E --> F["Implement until test green<br/>(test-first hook stays silent because test already edited)"]
    F --> G["/persona-roundtable HEAD~1..HEAD"]
    G --> H{"Unanimous risks?"}
    H -- "yes" --> F
    H -- "no" --> I["/pr-preflight"]
    I --> J{"PASS?"}
    J -- "no" --> F
    J -- "yes" --> K["git push + create PR"]
    K --> L["/handoff rate-limiter (for tomorrow)"]
    L --> M["/EOD_Summary"]
```

### Step-by-step

1. **Set scope.**
   > /scope src/auth/, tests/auth/, docs/rate-limiting.md

2. **Write the spec.**
   > /spec rate limiter on /api/login (6 attempts/60s per IP)

   Iterate until the spec is right. **Do not let Claude code yet.**

3. **Write the failing test first.**
   > /repro Currently /api/login has no rate limit; brute-force is unblocked.

   The test fails (proves the bug exists).

4. **Implement.**
   > Now make the failing test pass without breaking anything else.

   `secrets-guard` will block any leaked credentials. `scope-guard`
   stays silent (you're inside scope). `test-first-enforcer` stays
   silent (test already edited). `blast-radius` warns if you touch
   widely-imported files.

5. **Multi-perspective review.**
   > /persona-roundtable HEAD~1..HEAD

   Read `report.md`. Address unanimous risks before proceeding.

6. **Pre-flight.**
   > /pr-preflight --strict

   PASS = ready to push.

7. **Push, open PR, then write the handoff.**
   > /handoff rate-limiter

8. **End the day.**
   > /retro
   > /EOD_Summary

---

## 19. Workflow: bug fix

```mermaid
flowchart TD
    A["Bug ticket: 'login fails for emoji passwords'"] --> B["/scope src/auth/, tests/auth/"]
    B --> C["/repro Login rejects valid passwords containing emoji"]
    C --> D{"Test fails?"}
    D -- "no" --> E["Bug not reproduced — investigate further<br/>(don't claim it's fixed)"]
    D -- "yes" --> F["Investigate root cause (cite file:line)"]
    F --> G["Apply fix"]
    G --> H["Re-run repro test → green"]
    H --> I["Run full suite"]
    I --> J{"All green?"}
    J -- "no" --> F
    J -- "yes" --> K["/pr-preflight"]
    K --> L["git commit -m 'fix(auth): handle emoji in passwords (closes #842)'"]
```

### Sample prompt sequence

> /scope src/auth/, tests/auth/
> /repro #842 — login rejects passwords containing emoji
> Now investigate the root cause — what's the encoding mismatch?
> Apply the fix
> Re-run the failing test from /repro plus the full auth suite
> /pr-preflight
> Commit with conventional-commit message referencing #842

---

## 20. Workflow: PR review

```mermaid
flowchart TD
    A["PR #1234 lands in your queue"] --> B["git fetch origin pull/1234/head:pr-1234"]
    B --> C["git checkout pr-1234"]
    C --> D["/persona-roundtable origin/main..HEAD"]
    D --> E["Read report.md → consensus, disagreements, unanimous risks"]
    E --> F{"Concerns to surface?"}
    F -- "yes" --> G["Comment on PR using cited evidence from report.md"]
    F -- "no" --> H["Approve"]
```

### Sample

> Check out PR 1234 locally and run a roundtable on it.
> Pick the 3 unanimous risks from report.md and write GitHub PR comments for each, citing file:line.

---

## 21. Workflow: prompt audit

```mermaid
flowchart TD
    A["LLM agent is misbehaving in prod"] --> B["/llm-audit prompts/agent.md transcripts/incident.jsonl"]
    B --> C["Read report.md (Phase A: forensics, Phase B: bias)"]
    C --> D["Pick STEP 1 from plan.json"]
    D --> E["Apply the prompt diff manually"]
    E --> F["Run the eval harness from Phase D"]
    F --> G{"Metric improved?<br/>Falsifier triggered?"}
    G -- "Improved" --> H["Promote prompt change"]
    G -- "Falsifier" --> I["Rollback per plan.json"]
```

---

## 22. Workflow: resumption

You haven't touched a project for two weeks.

```mermaid
flowchart TD
    A["Open project, start Claude session"] --> B["SessionStart hook fires:<br/>resolves Checkpoint.md + EOD_Summary.md paths"]
    B --> C["Read .agents/artifacts/handoffs/<topic>.md (latest section)"]
    C --> D["Run the 'exact next command'"]
    D --> E{"Test passes?"}
    E -- "yes" --> F["Continue from there"]
    E -- "no" --> G["State the failure, /repro if a new bug, otherwise debug"]
```

### Sample

> Read the latest handoff section from .agents/artifacts/handoffs/rate-limiter.md and brief me. What's the exact next command to run?

> (Claude reads, summarizes, prints the command.)

> Run it.

---

# 23. Configuration

| Env var | Default | Effect |
|---|---|---|
| `CLAUDE_PROJECT_DIR` | (set by Claude Code) | Project root used by all hooks. |
| `CLAUDE_SKIP_TEST_FIRST` | `0` | When `1`, disables `test-first-enforcer` for the session. |
| `CLAUDE_BLAST_RADIUS_THRESHOLD` | `20` | Call-site count above which `blast-radius` warns. |

Set these before launching Claude Code:

```bash
# Linux/macOS
export CLAUDE_BLAST_RADIUS_THRESHOLD=10
claude

# Windows PowerShell
$env:CLAUDE_BLAST_RADIUS_THRESHOLD=10
claude
```

---

# 24. Disabling hooks temporarily

### One-off bypass (in-message)

For `test-first-enforcer`, embed a marker in the file content:

```python
# [refactor]
def renamed_function(x): ...
```

For `secrets-guard`, write to an allowlisted path:
- `.env.example`
- `fixtures/secrets/`
- `tests/**/fixtures/`

Or use a placeholder:
- `${VAR}` / `os.environ["X"]` / `<YOUR_KEY>`

### Whole-session bypass

For test-first: `CLAUDE_SKIP_TEST_FIRST=1`.

For others: edit `.claude/settings.json` and remove the hook entry,
then restart Claude.

### Permanent disable

Delete the entry from `.claude/settings.json`. The hook script
file can stay on disk; it just won't be wired up.

---

# 25. Troubleshooting

### "secrets-guard blocked something I genuinely needed to write"

Three options:
1. Use a placeholder pattern (`os.environ["X"]`).
2. Move the literal to `.env.example` (allowlisted).
3. If it's a public test vector, write to `fixtures/secrets/`.

If you've found a false-positive that should be allowed, edit
`.claude/hooks/_secrets_scan.py` (the `ALLOW_PATH_RE` or
`PLACEHOLDER_RE`). Keep the changes minimal and re-run the
12-scenario smoke test before committing.

### "I never see the secrets-guard output in chat"

The hook only emits output when it BLOCKS. On allow, it's silent.
That's by design.

### "test-first nudges every time, even on tiny edits"

Either:
- Tag the edit with `[refactor]` / `no-test-needed`.
- Set `CLAUDE_SKIP_TEST_FIRST=1` for refactor-heavy sessions.
- Edit a real test file once at the start of the session — after
  that, `edit-recorder` will mark `tests_changed=True` and the
  nudge stops firing.

### "scope-guard didn't warn even though I edited outside scope"

Check that `/scope` actually wrote state:

```bash
cat .claude/state/<session_id>.json | python -m json.tool
```

If `"scope"` is missing or `items` is empty, the declaration
didn't take.

### "blast-radius gives counts that don't match my IDE"

The hook uses a heuristic regex (`(?:import|from|require|use)\s+...basename`).
It is intentionally a calibration tool, not authoritative. If
you need the exact count, run:

```bash
grep -rE '(import|from|require|use).*\butils\b' . \
  --include='*.py' --include='*.js' --include='*.ts' \
  | wc -l
```

### "Hooks aren't firing at all"

1. Check `.claude/settings.json` exists and is valid JSON:
   ```bash
   python -m json.tool .claude/settings.json
   ```
2. Check the shell scripts are executable (Linux/macOS):
   ```bash
   ls -la .claude/hooks/*.sh
   # Each should be -rwxr-xr-x
   ```
3. Check `python` is on `$PATH`:
   ```bash
   which python && python --version
   ```
4. Restart your Claude Code session — settings.json changes are
   only picked up at session start.

### "Windows hooks fail with a parser error"

Verify each `.ps1` parses:

```powershell
$files = Get-ChildItem .claude\hooks\*.ps1
foreach ($f in $files) {
    try {
        [void] [System.Management.Automation.PSParser]::Tokenize(
            (Get-Content -Raw $f.FullName), [ref] $null)
        "$($f.Name): OK"
    } catch {
        "$($f.Name): $_"
    }
}
```

### "I want to see WHY a hook decided what it did"

Run the hook directly and inspect the output:

```bash
# Linux/macOS — feed a fake payload
echo '{"tool_name":"Write","tool_input":{"file_path":"src/foo.py","content":"AWS_KEY=\"AKIAIOSFODNN7EXAMPLE\""}}' \
  | bash .claude/hooks/secrets-guard.sh
```

```powershell
# Windows
'{"tool_name":"Write","tool_input":{"file_path":"src/foo.py","content":"AWS_KEY=\"AKIAIOSFODNN7EXAMPLE\""}}' `
  | powershell -ExecutionPolicy Bypass -NoProfile -File .claude\hooks\secrets-guard.ps1
```

Empty output = ALLOW. JSON output with `"deny"` = block.
