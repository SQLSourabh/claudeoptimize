---
description: Record an Architecture Decision (ADR) — numbered, immutable, append-only
argument-hint: "<title>"
allowed-tools: Read, Write, Glob, Bash(git:*)
---

# /adr

Record an Architecture Decision Record (ADR) titled: **$ARGUMENTS**

ADRs capture *why* a decision was made, in enough detail that someone
six months later can understand the context. They are **immutable** —
once written, they are not edited. To change a decision, write a new
ADR that supersedes the old one.

## Step 1 — Find the next ADR number

`Glob` `docs/adr/NNNN-*.md` (or `.agents/artifacts/adr/NNNN-*.md` if
the repo doesn't have a docs dir yet — pick whichever already exists,
default to `docs/adr/`). Take the highest number, add 1, zero-pad to
4 digits.

## Step 2 — Write the ADR

Path: `docs/adr/<NNNN>-<kebab-slug>.md`

```
# ADR <NNNN>: <Title>

- **Status:** Accepted
- **Date:** <YYYY-MM-DD>
- **Deciders:** <human + any AI personas consulted>
- **Supersedes:** ADR-NNNN (if applicable)
- **Superseded by:** (leave blank — only edited by a future ADR's
  /adr command)

## Context

What is the issue we're seeing that motivates this decision? Cite
the prompting evidence: a bug, a slow query, a security finding,
a design discussion. Use file:line citations where applicable.

## Decision

The change we're making. Stated as ONE sentence at the top, then
elaborated below. Example:
> "We will store session tokens in Redis with a 24-hour TTL instead
> of in the user table."

## Options considered

For each option (minimum 2), record:
- Name
- One-paragraph description
- Pros (cited if possible)
- Cons (cited if possible)
- Why rejected / accepted

## Consequences

What becomes easier? What becomes harder? What new risks does this
introduce? What follow-up work is created (and is it tracked)?

## Verification

The command/test/observation that confirms the decision is in effect
after implementation. Without this, the ADR is unfalsifiable.
```

## Step 3 — Update the ADR index

Append to `docs/adr/README.md` (create if missing) under a section
titled `## Index`:

```
- [ADR-<NNNN>: <Title>](./<NNNN>-<slug>.md) — <date> — <one-line summary>
```

The README must be append-only: never edit prior entries.

## Hard rules

- **Immutability.** Never modify an existing ADR file. To revise a
  decision, write a new ADR and set `Superseded by:` on the old one
  via a single targeted Edit (the only allowed mutation, and only on
  that field).
- **No vague decisions.** "We'll use the right tool for the job" is
  invalid. "We will use Postgres for OLTP and ClickHouse for
  analytics, because <cited reason>" is valid.
- **Two options minimum.** A decision with no alternatives wasn't a
  decision; it was a default. List at least one rejected option.
- **Cite, don't claim.** "X is faster than Y" needs a benchmark or a
  link. Otherwise label as OPINION and surface in the consequences.

After writing, print only: ADR path, NNNN, supersedes (if any), and
"Run `git add docs/adr/<NNNN>-<slug>.md docs/adr/README.md`" so the
user can stage it.
