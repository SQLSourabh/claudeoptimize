#!/usr/bin/env python
"""
Stdin: PreToolUse JSON.
Stdout: {"action": "allow"} or {"action": "warn", "reason": "..."}.
Reads session state from ./.claude/state/<session_id>.json to know
whether any test files have been touched this session.
"""
import json
import os
import re
import sys
from pathlib import Path


SOURCE_EXTS = (".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rb", ".rs",
               ".java", ".kt", ".swift", ".cs", ".cpp", ".c", ".php")

TEST_PATH_RE = re.compile(
    r"(^|[\\/])test[s]?[\\/]"
    r"|(^|[\\/])__tests__[\\/]"
    r"|[\\/]_test\.go$"
    r"|_test\.go$"
    r"|test_[^\\/]*$"
    r"|[\\/]test_[^\\/]*$"
    r"|\.test\.[jt]sx?$"
    r"|\.spec\.[jt]sx?$",
    re.IGNORECASE,
)

SKIPPABLE_PATH_RE = re.compile(
    r"\.md$|\.rst$|\.txt$|\.json$|\.ya?ml$|\.toml$|\.cfg$|\.ini$"
    r"|(^|[\\/])(README|CHANGELOG|LICENSE|CONTRIBUTING)"
    r"|(^|[\\/])docs[\\/]"
    r"|(^|[\\/])examples?[\\/]"
    r"|(^|[\\/])scripts?[\\/]"
    r"|(^|[\\/])migrations?[\\/]"
    r"|\.lock$"
    r"|\.gitattributes$|\.gitignore$",
    re.IGNORECASE,
)

BYPASS_TOKEN_RE = re.compile(
    r"no-test-needed|\[skip test-first\]|\[skip-test-first\]|\[refactor\]",
    re.IGNORECASE,
)


def _state_path(session_id: str) -> Path:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in session_id)[:64]
    return Path(root) / ".claude" / "state" / f"{safe or 'unknown'}.json"


def main() -> int:
    raw = sys.stdin.read()
    try:
        data = json.loads(raw or "{}")
    except json.JSONDecodeError:
        print(json.dumps({"action": "allow"})); return 0

    session_id = data.get("session_id") or "unknown"
    tool_input = data.get("tool_input") or {}
    file_path = (tool_input.get("file_path") or "").strip()
    content = (tool_input.get("content") or tool_input.get("new_string") or "")

    if not file_path:
        print(json.dumps({"action": "allow"})); return 0

    # Skip non-source files.
    if SKIPPABLE_PATH_RE.search(file_path):
        print(json.dumps({"action": "allow"})); return 0
    if not file_path.endswith(SOURCE_EXTS):
        print(json.dumps({"action": "allow"})); return 0

    # If this IS a test file being written, that's good — record + allow.
    if TEST_PATH_RE.search(file_path):
        print(json.dumps({"action": "allow"})); return 0

    # Bypass via in-content marker.
    if BYPASS_TOKEN_RE.search(content):
        print(json.dumps({"action": "allow"})); return 0

    # Check state for any test edits this session.
    sp = _state_path(session_id)
    tests_changed = []
    if sp.exists():
        try:
            sd = json.loads(sp.read_text(encoding="utf-8") or "{}")
            tests_changed = sd.get("tests_changed", [])
        except json.JSONDecodeError:
            pass

    if tests_changed:
        print(json.dumps({"action": "allow"})); return 0

    reason = (
        f"NUDGE from test-first-enforcer: about to edit a source file "
        f"({file_path}), but no test file has been edited yet this "
        f"session. Best practice for new behavior is: write the failing "
        f"test FIRST, see it fail, then implement.\n"
        f"\nIf this edit is for a refactor / docs / configuration / "
        f"obvious bugfix, include `no-test-needed` or `[refactor]` in "
        f"the file content (a comment is fine), or set env var "
        f"CLAUDE_SKIP_TEST_FIRST=1 for the session.\n"
        f"\nProceeding without a test is allowed — this is a nudge, not "
        f"a block. But please justify briefly in your next message why a "
        f"test isn't required."
    )
    print(json.dumps({"action": "warn", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
