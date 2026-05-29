#!/usr/bin/env bash
# PreCompact / Stop hook: appends a structured checkpoint stub to the
# resolved Checkpoint.md location. Re-scans the tree on every invocation
# so the hook stays in sync with whatever location SessionStart adopted
# (or the user moved to between hook calls).

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

resolve_managed_file "Checkpoint.md"
CHECKPOINT_PATH="$RESOLVED_PATH"
RESOLVE_NOTE="$RESOLVED_NOTE"
RESOLVE_STATUS="$RESOLVED_STATUS"

# If somehow no file exists yet (e.g., SessionStart was skipped), create
# it at the resolved (root) location so we never crash.
if [[ ! -f "$CHECKPOINT_PATH" ]]; then
  cat > "$CHECKPOINT_PATH" <<'EOF'
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions.

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
  SESSION_ID="$(printf '%s' "$PAYLOAD" | python -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
    print(d.get("session_id", ""))
except Exception:
    print("")
' 2>/dev/null || echo "")"
  TRANSCRIPT="$(printf '%s' "$PAYLOAD" | python -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
    print(d.get("transcript_path", ""))
except Exception:
    print("")
' 2>/dev/null || echo "")"
fi

{
  echo ""
  echo "## Checkpoint @ ${TS}"
  echo ""
  echo "- **Date:** ${DATE}"
  echo "- **Session ID:** \`${SESSION_ID:-unknown}\`"
  echo "- **Transcript:** \`${TRANSCRIPT:-unknown}\`"
  echo ""
  echo "### Goals for this session"
  echo "<!-- Claude: fill in 1-3 bullets describing what we set out to do -->"
  echo ""
  echo "### Decisions made"
  echo "<!-- Claude: list concrete decisions with rationale + file:line evidence -->"
  echo ""
  echo "### Completed / Resolved"
  echo "<!-- Claude: bullet list of finished items, each with verifying command or PR link -->"
  echo ""
  echo "### Open / In-flight"
  echo "<!-- Claude: bullet list of things still in progress -->"
  echo ""
  echo "### Blockers / Unresolved questions"
  echo "<!-- Claude: anything that needs human input or external info -->"
  echo ""
  echo "### Files touched"
  echo "<!-- Claude: paths grouped by created/modified/deleted -->"
  echo ""
  echo "### Verification evidence"
  echo "<!-- Claude: tests run, commands executed, exit codes — facts only -->"
  echo ""
  echo "---"
} >> "$CHECKPOINT_PATH"

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CP_REL="${CHECKPOINT_PATH#$ROOT/}"

__json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

CTX="A new checkpoint stub was appended at ${TS} to ${CP_REL} (${RESOLVE_STATUS}). ${RESOLVE_NOTE} BEFORE doing anything else, edit that file and replace each <!-- Claude: ... --> placeholder with factual content from this session. Use file:line citations for decisions, exit codes for verifications, and exact paths for files. Do NOT modify or remove any prior checkpoint blocks. Append-only is non-negotiable."

cat <<JSON
{
  "hookSpecificOutput": {
    "additionalContext": "$(__json_escape "$CTX")"
  }
}
JSON
