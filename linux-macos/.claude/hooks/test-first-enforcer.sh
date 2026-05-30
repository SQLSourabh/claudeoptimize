#!/usr/bin/env bash
# PreToolUse hook on Write|Edit (NOT Bash, NOT Read).
# When you edit a SOURCE file (not test, not docs, not config), the hook
# warns Claude (additionalContext) if NO test file has been changed in
# the current session. The hook does NOT block by default — it nudges.
#
# Bypass: include "no-test-needed" or "[skip test-first]" anywhere in the
# user's prompt or in the file content (e.g., for refactors / doc changes).
# Or, set env var CLAUDE_SKIP_TEST_FIRST=1 for the session.

set -euo pipefail

# Inactive without python.
if ! command -v python >/dev/null 2>&1; then exit 0; fi
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bypass via env var.
if [[ "${CLAUDE_SKIP_TEST_FIRST:-}" == "1" ]]; then exit 0; fi

VERDICT="$(python "$HOOK_DIR/_test_first.py")"

ACTION="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try:    print(json.loads(sys.stdin.read() or "{}").get("action", "allow"))
except Exception: print("allow")
')"

if [[ "$ACTION" == "warn" ]]; then
  REASON="$(printf '%s' "$VERDICT" | python -c '
import json, sys
try:    print(json.loads(sys.stdin.read() or "{}").get("reason", ""))
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
