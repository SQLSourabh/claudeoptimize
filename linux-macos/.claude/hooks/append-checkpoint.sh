#!/usr/bin/env bash
# PreCompact / Stop hook: appends a partial-but-true checkpoint block.
#
# Contract (per CLAUDE.md §2):
# - Header (timestamp, session_id, transcript_path) — populated here.
# - Files touched              — populated from session-state edits.
# - Verification evidence      — populated from transcript Bash events.
# - Slash commands invoked     — populated from transcript user msgs.
# - Goals / Decisions / Open / Blockers — placeholders, filled by /checkpoint.
# - checkpoint-meta footer     — block_id used by /checkpoint to relocate.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

resolve_managed_file "Checkpoint.md"
CHECKPOINT_PATH="$RESOLVED_PATH"
RESOLVE_NOTE="$RESOLVED_NOTE"
RESOLVE_STATUS="$RESOLVED_STATUS"

# Bootstrap if missing.
if [[ ! -f "$CHECKPOINT_PATH" ]]; then
  cat > "$CHECKPOINT_PATH" <<'EOF'
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions. The hook
populates deterministic facts (files touched, bash exit codes, slash
commands). Run `/checkpoint` to fill in the language-level sections
(goals, decisions, open, blockers).

---
EOF
fi

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DATE="$(date -u +"%Y-%m-%d")"

# Read hook payload from stdin (JSON). Extract session_id + transcript_path.
PAYLOAD="$(cat || true)"
SESSION_ID=""
TRANSCRIPT=""
if command -v python >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$PAYLOAD" | python -c 'import json,sys
try:    print(json.loads(sys.stdin.read() or "{}").get("session_id",""))
except: print("")' 2>/dev/null || echo "")"
  TRANSCRIPT="$(printf '%s' "$PAYLOAD" | python -c 'import json,sys
try:    print(json.loads(sys.stdin.read() or "{}").get("transcript_path",""))
except: print("")' 2>/dev/null || echo "")"
fi

# Build block in a tmp file.
BLOCK="$(mktemp)"
trap 'rm -f "$BLOCK"' EXIT

{
  echo ""
  echo "## Checkpoint @ ${TS}"
  echo ""
  echo "- **Date:** ${DATE}"
  echo "- **Session ID:** \`${SESSION_ID:-unknown}\`"
  echo "- **Transcript:** \`${TRANSCRIPT:-unknown}\`"
  echo ""
  echo "### Files touched (deterministic — from edit-recorder)"
} > "$BLOCK"

# Files touched: ask _session_state.py for the JSON list, render via reader.
if command -v python >/dev/null 2>&1 && [[ -n "$SESSION_ID" ]]; then
  EDITS_JSON="$(python "$HOOK_DIR/_session_state.py" list-edits "$SESSION_ID" 2>/dev/null || echo "[]")"
  python "$HOOK_DIR/_transcript_reader.py" "${TRANSCRIPT:-/dev/null}" \
    --markdown=files --edits-json="$EDITS_JSON" 2>/dev/null \
    >> "$BLOCK" \
    || echo "- (failed to render files-touched)" >> "$BLOCK"
else
  echo "- (session_id or python unavailable; cannot enumerate edits)" >> "$BLOCK"
fi

echo "" >> "$BLOCK"
echo "### Verification evidence (deterministic — from transcript Bash events)" >> "$BLOCK"

# Transcript-derived sections rendered directly by the reader.
HAVE_TRANSCRIPT=0
if command -v python >/dev/null 2>&1 && [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  HAVE_TRANSCRIPT=1
fi

if [[ $HAVE_TRANSCRIPT -eq 1 ]]; then
  python "$HOOK_DIR/_transcript_reader.py" "$TRANSCRIPT" --markdown=bash 2>/dev/null \
    >> "$BLOCK" \
    || echo "- (transcript read failed)" >> "$BLOCK"
else
  echo "- (transcript not available; no verification facts captured)" >> "$BLOCK"
fi

echo "" >> "$BLOCK"
echo "### Slash commands invoked (deterministic)" >> "$BLOCK"

if [[ $HAVE_TRANSCRIPT -eq 1 ]]; then
  python "$HOOK_DIR/_transcript_reader.py" "$TRANSCRIPT" --markdown=slash 2>/dev/null \
    >> "$BLOCK" \
    || echo "- (transcript read failed)" >> "$BLOCK"
else
  echo "- (transcript not available)" >> "$BLOCK"
fi

# Compute block_id.
BLOCK_ID=""
if [[ $HAVE_TRANSCRIPT -eq 1 ]]; then
  BLOCK_ID="$(python "$HOOK_DIR/_transcript_reader.py" "$TRANSCRIPT" --markdown=block-id 2>/dev/null \
              | tr -d '[:space:]' || echo "")"
fi
if [[ -z "$BLOCK_ID" ]] && command -v python >/dev/null 2>&1; then
  BLOCK_ID="$(python -c "import sys, hashlib; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])" \
              "${SESSION_ID:-unknown}|${TRANSCRIPT:-unknown}" 2>/dev/null || echo "")"
fi
[[ -z "$BLOCK_ID" ]] && BLOCK_ID="unknown"

{
  echo ""
  echo "### Goals for this session"
  echo "<!-- Claude: fill in via /checkpoint -->"
  echo ""
  echo "### Decisions made"
  echo "<!-- Claude: fill in via /checkpoint -->"
  echo ""
  echo "### Open / In-flight"
  echo "<!-- Claude: fill in via /checkpoint -->"
  echo ""
  echo "### Blockers / Unresolved questions"
  echo "<!-- Claude: fill in via /checkpoint -->"
  echo ""
  echo "<!-- checkpoint-meta: session_id=${SESSION_ID:-unknown} transcript=${TRANSCRIPT:-unknown} block_id=${BLOCK_ID:-unknown} -->"
  echo ""
  echo "---"
} >> "$BLOCK"

# Atomic append.
cat "$BLOCK" >> "$CHECKPOINT_PATH"

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CP_REL="${CHECKPOINT_PATH#$ROOT/}"

__json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

CTX="A new checkpoint block was appended at ${TS} to ${CP_REL} (${RESOLVE_STATUS}). ${RESOLVE_NOTE} The block contains DETERMINISTIC facts (files touched, bash exit codes, slash commands). The four narrative sections (Goals / Decisions / Open / Blockers) carry placeholders. Run /checkpoint to fill them in. Append-only: never modify or remove prior checkpoint blocks. block_id=${BLOCK_ID:-unknown}."

cat <<JSON
{
  "hookSpecificOutput": {
    "additionalContext": "$(__json_escape "$CTX")"
  }
}
JSON
