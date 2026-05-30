---
description: Pre-flight every check before pushing or opening a PR
argument-hint: "[--strict] (treat warnings as failures)"
allowed-tools: Bash(*), Read, Grep, Glob
---

# /pr-preflight

Run every relevant pre-flight check on the current change set before
the user pushes or opens a PR. **Catches the embarrassing failures
before code leaves the laptop.**

Strict mode (`$ARGUMENTS` contains `--strict`): warnings are treated
as failures — the verdict is FAIL even on amber items.

## Phase 1 — Detect what to run (no fabrication)

Look in the project root for these signals and report which checks
are applicable:

| File / pattern | Check |
|---|---|
| `package.json` with `scripts.lint` | `npm run lint` |
| `package.json` with `scripts.typecheck` or `tsconfig.json` | `npm run typecheck` (or `tsc --noEmit`) |
| `package.json` with `scripts.test` | `npm test` |
| `pyproject.toml` / `setup.cfg` with pytest config | `pytest` |
| `pyproject.toml` with ruff config | `ruff check` |
| `pyproject.toml` with mypy config | `mypy` |
| `go.mod` | `go vet ./...`, `go test ./...` |
| `Cargo.toml` | `cargo clippy`, `cargo test` |
| `Makefile` with `test` target | `make test` |
| `.pre-commit-config.yaml` | `pre-commit run --all-files` |

If a project has multiple, run all that apply.

## Phase 2 — Run checks in parallel (when independent)

Run with timeout (300s default per check). For each:
- Show the exact command
- Capture exit code
- Capture last 30 lines of output on failure

## Phase 3 — Repository hygiene checks (always run)

Independent of language:

1. **Secrets scan on the diff.** Run the same regex set the
   secrets-guard hook uses, but against `git diff --cached` plus
   uncommitted changes. Block PR if any.
2. **Conventional commit check** (if last commit is yours):
   `git log -1 --pretty=%s` should match
   `^(feat|fix|docs|chore|refactor|test|build|ci|perf|revert)(\(.+\))?:\s+.+$`.
3. **Line-count budget.** `git diff --stat origin/HEAD..HEAD` —
   warn if any single file exceeds +500 lines. Big diffs are hard
   to review.
4. **TODO/FIXME budget.** Count new `TODO` and `FIXME` introduced
   by the diff. Warn if > 5.
5. **Test-changed ratio.** Count source-file edits vs test-file
   edits in the diff. Warn if there are source edits but zero test
   edits. (Same logic as the test-first hook, applied retroactively.)
6. **Generated files check.** If `node_modules`, `dist`, `build`,
   `.next` etc. appear in `git status`, FAIL — they should be in
   `.gitignore`.
7. **Branch sanity.** Refuse to recommend pushing to `main` /
   `master` directly. Suggest a feature branch.

## Phase 4 — Verdict

Produce a verdict report with this exact shape:

```
## /pr-preflight verdict — <date>

**Branch:** <name>
**Diff size:** <files changed> files, +<adds>/-<dels> lines

### Checks run (N)
| Check | Result | Time | Detail |
|---|---|---|---|
| ... |

### Failures (M)
- <command> → exit <code> — <one-line summary>
  - last 5 lines of output:
    ```
    ...
    ```

### Warnings (P)
- <warning> — recommendation

### VERDICT: PASS | FAIL | WARN

If FAIL, do NOT proceed to push. Required fixes:
1. ...
```

## Hard rules

- **Run, don't simulate.** Every `Result` cell is an actual exit code
  from a command run in this session — no inferences.
- **No silent skips.** If a check is detected as applicable but
  could not be run (timeout, missing tool), mark as `SKIPPED` with
  reason. SKIPPED counts as a warning.
- **Preserve the user's flow.** If everything passes, give a one-line
  green light at the end. If there are failures, the verdict block
  is enough — don't pad with summary prose.
