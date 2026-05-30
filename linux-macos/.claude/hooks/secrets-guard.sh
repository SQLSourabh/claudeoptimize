#!/usr/bin/env bash
# PreToolUse hook on Write|Edit|Bash.
# Delegates to _secrets_scan.py so stdin reaches the scanner.
# Returns the Claude Code hook contract:
#   - permissionDecision=deny  -> tool call blocked
#   - exit 0 with empty output -> allow

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Without python, we can't scan; conservatively allow and log.
if ! command -v python >/dev/null 2>&1; then
  echo "[secrets-guard] python not on PATH — hook is inactive" >&2
  exit 0
fi

VERDICT="$(python "$HOOK_DIR/_secrets_scan.py")"

# Parse action via python (avoids fragile shell JSON munging).
ACTION="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try:
    print(json.loads(sys.stdin.read() or "{}").get("action", "allow"))
except Exception:
    print("allow")
')"

if [[ "$ACTION" == "deny" ]]; then
  REASON="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try:
    print(json.loads(sys.stdin.read() or "{}").get("reason", "secrets-guard denied"))
except Exception:
    print("secrets-guard denied")
')"
  python -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}))
" "$REASON"
fi

exit 0
