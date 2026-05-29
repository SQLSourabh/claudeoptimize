#!/usr/bin/env bash
# SessionStart hook: ensures Checkpoint.md and EOD_Summary.md are present
# somewhere in the project tree. Adopts an existing file if found;
# creates a new one at the project root only when none exists.
# Idempotent — never overwrites.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

# --- Checkpoint.md ---
resolve_managed_file "Checkpoint.md"
CHECKPOINT_PATH="$RESOLVED_PATH"
CHECKPOINT_NOTE="$RESOLVED_NOTE"
CHECKPOINT_STATUS="$RESOLVED_STATUS"

if [[ "$CHECKPOINT_STATUS" == "create" ]]; then
  cat > "$CHECKPOINT_PATH" <<'EOF'
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions.

---
EOF
fi

# --- EOD_Summary.md ---
resolve_managed_file "EOD_Summary.md"
EOD_PATH="$RESOLVED_PATH"
EOD_NOTE="$RESOLVED_NOTE"
EOD_STATUS="$RESOLVED_STATUS"

if [[ "$EOD_STATUS" == "create" ]]; then
  cat > "$EOD_PATH" <<'EOF'
# End-of-Day Summary

Populated by the `/EOD_Summary` command. Each day's section is appended,
never overwritten.

---
EOF
fi

# Surface resolved paths + any warnings to Claude.
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CP_REL="${CHECKPOINT_PATH#$ROOT/}"
EOD_REL="${EOD_PATH#$ROOT/}"

# JSON-escape the note strings (the only chars that matter for our content
# are backslash and double-quote; ISO-safe otherwise).
__json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

CTX="Checkpoint resolution: ${CP_REL} (${CHECKPOINT_STATUS}). ${CHECKPOINT_NOTE} EOD resolution: ${EOD_REL} (${EOD_STATUS}). ${EOD_NOTE} Append-only contract: NEVER overwrite either file. If you need to reference them in this session, use the absolute paths logged here, not assumptions about project root."

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$(__json_escape "$CTX")"
  }
}
JSON
