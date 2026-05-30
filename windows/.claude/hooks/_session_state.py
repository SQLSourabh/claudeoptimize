#!/usr/bin/env python
"""
Tiny shared state helper for hooks.

Stores per-session JSON at .claude/state/<session_id>.json:
  {
    "scope": {"declared_at": "...", "items": ["paths or patterns"]},
    "plan": {"declared_at": "...", "files": ["..."]},
    "edits": [{"ts": "...", "file": "...", "tool": "..."}, ...],
    "tests_changed": ["test files modified this session"]
  }

Usage:
  python _session_state.py get-scope <session_id>
  python _session_state.py set-scope <session_id> <json-array-of-items>
  python _session_state.py append-edit <session_id> <file> <tool>
  python _session_state.py list-edits <session_id>

The state directory survives across hook calls within a session but is
session-scoped — ROT-cleaning is done at SessionEnd.
"""
import json
import os
import sys
import time
from pathlib import Path


def _state_dir() -> Path:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    d = Path(root) / ".claude" / "state"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _path_for(session_id: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in session_id)[:64]
    return _state_dir() / f"{safe or 'unknown'}.json"


def _load(session_id: str) -> dict:
    p = _path_for(session_id)
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            return {}
    return {}


def _save(session_id: str, data: dict) -> None:
    _path_for(session_id).write_text(json.dumps(data, indent=2), encoding="utf-8")


def cmd_get_scope(session_id: str) -> int:
    print(json.dumps(_load(session_id).get("scope", {})))
    return 0


def cmd_set_scope(session_id: str, items_json: str) -> int:
    items = json.loads(items_json)
    data = _load(session_id)
    data["scope"] = {"declared_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                     "items": items}
    _save(session_id, data)
    print(json.dumps(data["scope"]))
    return 0


def cmd_set_plan(session_id: str, files_json: str) -> int:
    files = json.loads(files_json)
    data = _load(session_id)
    data["plan"] = {"declared_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "files": files}
    _save(session_id, data)
    print(json.dumps(data["plan"]))
    return 0


def cmd_get_plan(session_id: str) -> int:
    print(json.dumps(_load(session_id).get("plan", {})))
    return 0


def cmd_append_edit(session_id: str, file_path: str, tool: str) -> int:
    data = _load(session_id)
    data.setdefault("edits", []).append({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "file": file_path,
        "tool": tool,
    })
    if file_path and (
        "/test" in file_path.replace("\\", "/").lower()
        or file_path.endswith("_test.go")
        or file_path.lower().startswith("test")
        or "test_" in os.path.basename(file_path).lower()
        or file_path.endswith(".test.ts")
        or file_path.endswith(".test.js")
        or file_path.endswith(".spec.ts")
        or file_path.endswith(".spec.js")
    ):
        data.setdefault("tests_changed", [])
        if file_path not in data["tests_changed"]:
            data["tests_changed"].append(file_path)
    _save(session_id, data)
    print("ok")
    return 0


def cmd_list_edits(session_id: str) -> int:
    print(json.dumps(_load(session_id).get("edits", [])))
    return 0


def cmd_tests_changed_count(session_id: str) -> int:
    print(len(_load(session_id).get("tests_changed", [])))
    return 0


def cmd_clear(session_id: str) -> int:
    p = _path_for(session_id)
    if p.exists():
        p.unlink()
    print("ok")
    return 0


COMMANDS = {
    "get-scope": cmd_get_scope,
    "set-scope": cmd_set_scope,
    "set-plan":  cmd_set_plan,
    "get-plan":  cmd_get_plan,
    "append-edit": cmd_append_edit,
    "list-edits": cmd_list_edits,
    "tests-changed-count": cmd_tests_changed_count,
    "clear": cmd_clear,
}


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: _session_state.py <command> <session_id> [args...]", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    session_id = sys.argv[2]
    args = sys.argv[3:]
    fn = COMMANDS.get(cmd)
    if not fn:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2
    return fn(session_id, *args)


if __name__ == "__main__":
    sys.exit(main())
