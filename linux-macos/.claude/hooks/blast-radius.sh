#!/usr/bin/env bash
# PreToolUse hook on Write|Edit for source files.
# Counts import-site references to the file being edited and warns when
# the count exceeds CLAUDE_BLAST_RADIUS_THRESHOLD (default 20).
# Surfaces additionalContext only — does not block.
#
# Implementation: a simple ripgrep-or-grep search across the project tree
# for the file's basename appearing in `import` / `require` / `from` lines.

set -euo pipefail

# Inactive without grep.
if ! command -v grep >/dev/null 2>&1; then exit 0; fi
if ! command -v python >/dev/null 2>&1; then exit 0; fi
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERDICT="$(python "$HOOK_DIR/_blast_radius.py")"

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
