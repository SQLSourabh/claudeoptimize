#!/usr/bin/env bash
# PreToolUse hook on Write|Edit.
# If the user has declared a scope (via /scope <items>), warn when an
# edit is about to land OUTSIDE that scope. Does NOT block — surfaces
# additionalContext so Claude pauses and confirms.

set -euo pipefail

if ! command -v python >/dev/null 2>&1; then exit 0; fi
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERDICT="$(python "$HOOK_DIR/_scope_guard.py")"

ACTION="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try: print(json.loads(sys.stdin.read() or "{}").get("action", "allow"))
except Exception: print("allow")
')"

if [[ "$ACTION" == "warn" ]]; then
  REASON="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try: print(json.loads(sys.stdin.read() or "{}").get("reason", ""))
except Exception: print("")
')"
  python -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'additionalContext': sys.argv[1]
    }
}))
" "$REASON"
fi

exit 0
