#!/usr/bin/env python
"""
Blast-radius reporter. Counts call sites that import the file being
edited. Heuristic only — designed to calibrate intuition, not to be
authoritative.

Threshold:
  - default: 20 sites
  - override with env var CLAUDE_BLAST_RADIUS_THRESHOLD=N

Skipped: directories like .git, node_modules, .venv, dist, build, etc.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path


SKIP_DIRS = {
    ".git", ".hg", ".svn", "node_modules", ".venv", "venv", "env",
    "dist", "build", "out", ".next", ".nuxt", "target", "__pycache__",
    ".pytest_cache", ".mypy_cache", ".tox", ".gradle", ".idea", ".vscode",
    ".claude", ".agents",
}

SOURCE_EXTS = (".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rb", ".rs",
               ".java", ".kt", ".swift", ".cs")


def _module_basename(path: str) -> str:
    """Return the bare module-ish name for the file (no extension)."""
    base = os.path.basename(path)
    name, _ext = os.path.splitext(base)
    return name


def _scan(root: Path, needle: str, target_path: str) -> list:
    """Return list of (file, line_no, line) where the needle appears in
    an import-like context. Pure Python — no rg/grep dependency.
    """
    if not needle or len(needle) < 3:
        return []

    target_abs = str(Path(target_path).resolve()) if target_path else ""

    pat = re.compile(
        rf"(?:import|from|require|use)\s+[^\n]*\b{re.escape(needle)}\b",
        re.IGNORECASE,
    )
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune in-place
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SOURCE_EXTS):
                continue
            p = Path(dirpath) / fn
            # Skip the file itself
            try:
                if str(p.resolve()) == target_abs:
                    continue
            except OSError:
                pass
            try:
                with open(p, "r", encoding="utf-8", errors="ignore") as f:
                    for i, line in enumerate(f, 1):
                        if pat.search(line):
                            hits.append((str(p.relative_to(root)), i, line.rstrip()))
                            if len(hits) >= 200:
                                return hits
            except OSError:
                continue
    return hits


def main() -> int:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        print(json.dumps({"action": "allow"})); return 0

    tool_input = data.get("tool_input") or {}
    file_path = (tool_input.get("file_path") or "").strip()
    if not file_path:
        print(json.dumps({"action": "allow"})); return 0

    if not file_path.endswith(SOURCE_EXTS):
        print(json.dumps({"action": "allow"})); return 0

    # Skip the scan entirely on file creation: nothing imports a
    # nonexistent file. Cheap heuristic: file doesn't exist yet.
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    full = (root / file_path) if not os.path.isabs(file_path) else Path(file_path)
    if not full.exists():
        print(json.dumps({"action": "allow"})); return 0

    threshold = int(os.environ.get("CLAUDE_BLAST_RADIUS_THRESHOLD", "20"))
    needle = _module_basename(file_path)

    try:
        hits = _scan(root, needle, str(full))
    except Exception:
        print(json.dumps({"action": "allow"})); return 0

    if len(hits) < threshold:
        print(json.dumps({"action": "allow"})); return 0

    sample = hits[:5]
    sample_lines = "\n".join(f"  - {f}:{ln}" for f, ln, _ in sample)
    reason = (
        f"BLAST RADIUS WARNING: {file_path} appears to be imported in "
        f"{len(hits)}+ places (threshold: {threshold}).\n"
        f"Sample call sites:\n{sample_lines}\n"
        f"Consider whether this change needs: a deprecation shim, "
        f"a backwards-compatible alias, or a coordinated update of "
        f"call sites. If the change is purely internal (no API or "
        f"contract change), this warning can be ignored."
    )
    print(json.dumps({"action": "warn", "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
