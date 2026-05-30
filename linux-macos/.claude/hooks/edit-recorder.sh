#!/usr/bin/env bash
# PostToolUse hook on Write|Edit.
# Records the edit into per-session state for the scope, plan-drift, and
# test-first hooks to read. Read-only output (no decision).

set -euo pipefail

if ! command -v python >/dev/null 2>&1; then exit 0; fi
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD="$(cat || true)"

python - "$PAYLOAD" "$HOOK_DIR/_session_state.py" <<'PYEOF'
import json, subprocess, sys
payload_str  = sys.argv[1]
state_helper = sys.argv[2]

try:
    data = json.loads(payload_str or "{}")
except json.JSONDecodeError:
    sys.exit(0)

session_id = data.get("session_id") or "unknown"
tool_name  = data.get("tool_name", "")
tool_input = data.get("tool_input") or {}
file_path  = (tool_input.get("file_path") or "").strip()
if not file_path:
    sys.exit(0)

# Fire-and-forget; if the helper fails we don't want to break the tool.
try:
    subprocess.run(
        ["python", state_helper, "append-edit", session_id, file_path, tool_name],
        check=False, capture_output=True, timeout=5,
    )
except Exception:
    pass
PYEOF

exit 0
