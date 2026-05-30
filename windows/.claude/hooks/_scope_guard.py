#!/usr/bin/env python
"""
Scope-creep detector. Stdin: PreToolUse JSON.
If session has a declared scope (set via /scope), warn when the file_path
falls outside it. Scope items can be:
  - exact paths      ("src/auth.py")
  - directory prefixes ("src/auth/")
  - glob-style suffixes ("*.py")  -- treated as fnmatch
"""
import fnmatch
import json
import os
import sys
from pathlib import Path


def _state_path(session_id: str) -> Path:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in session_id)[:64]
    return Path(root) / ".claude" / "state" / f"{safe or 'unknown'}.json"


def in_scope(file_path: str, items: list) -> bool:
    fp = file_path.replace("\\", "/")
    for item in items:
        it = item.replace("\\", "/").strip()
        if not it:
            continue
        # Glob form
        if any(c in it for c in "*?["):
            if fnmatch.fnmatchcase(fp, it):
                return True
            # Also match by basename to allow patterns like *.py
            if fnmatch.fnmatchcase(os.path.basename(fp), it):
                return True
            continue
        # Directory prefix
        if it.endswith("/"):
            if fp.startswith(it):
                return True
            continue
        # Exact path or containing-dir match
        if fp == it or fp.startswith(it + "/"):
            return True
    return False


def main() -> int:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        print(json.dumps({"action": "allow"})); return 0

    session_id = data.get("session_id") or "unknown"
    tool_input = data.get("tool_input") or {}
    file_path  = (tool_input.get("file_path") or "").strip()
    if not file_path:
        print(json.dumps({"action": "allow"})); return 0

    sp = _state_path(session_id)
    if not sp.exists():
        print(json.dumps({"action": "allow"})); return 0

    try:
        sd = json.loads(sp.read_text(encoding="utf-8") or "{}")
    except json.JSONDecodeError:
        print(json.dumps({"action": "allow"})); return 0

    scope = sd.get("scope") or {}
    items = scope.get("items") or []
    if not items:
        print(json.dumps({"action": "allow"})); return 0

    if in_scope(file_path, items):
        print(json.dumps({"action": "allow"})); return 0

    reason = (
        f"SCOPE WARNING: about to edit {file_path}, which is OUTSIDE the "
        f"declared session scope ({', '.join(items)}).\n"
        f"Either: (a) confirm this edit is necessary and explain why in "
        f"your next message, or (b) update the scope via /scope to add "
        f"this file/pattern. Proceeding without acknowledgment risks "
        f"silent scope creep."
    )
    print(json.dumps({"action": "warn", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
