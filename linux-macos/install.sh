#!/usr/bin/env bash
# Installer for the Claude Code optimization pack (Linux / macOS).
#
# Usage:
#   bash install.sh                  # install into current directory
#   bash install.sh /path/to/project # install into a specific project
#
# Idempotent: re-running will not overwrite an existing CLAUDE.md or
# settings.json. Existing files are backed up with a .bak suffix
# before any merge.

set -euo pipefail

TARGET="${1:-$(pwd)}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: target directory does not exist: $TARGET" >&2
  exit 1
fi

echo "Installing Claude optimization pack:"
echo "  source: $SRC"
echo "  target: $TARGET"
echo ""

# 1. .claude/ directory tree
mkdir -p "$TARGET/.claude/hooks" "$TARGET/.claude/commands" "$TARGET/.claude/agents"

# 2. Copy hooks (always overwrite — these are versioned).
#    Glob-copy *.sh + *.py so adding new hooks in the source pack
#    doesn't require updating this installer. Helper python scripts
#    (_secrets_scan.py, _session_state.py, etc.) are platform-
#    agnostic and ship to both Linux/macOS and Windows trees.
shopt -s nullglob
HOOK_FILES=( "$SRC/.claude/hooks/"*.sh "$SRC/.claude/hooks/"*.py )
shopt -u nullglob
if [[ ${#HOOK_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no hook files found at $SRC/.claude/hooks/" >&2
  exit 1
fi
for f in "${HOOK_FILES[@]}"; do
  cp "$f" "$TARGET/.claude/hooks/"
done
chmod +x "$TARGET/.claude/hooks/"*.sh
# Python helpers don't need +x (they're invoked via `python <script>`),
# but +x is harmless and useful when users run them directly.
chmod +x "$TARGET/.claude/hooks/"*.py 2>/dev/null || true
echo "Copied ${#HOOK_FILES[@]} hook files."

# 3. Copy commands (always overwrite)
cp "$SRC/.claude/commands/"*.md "$TARGET/.claude/commands/"

# 4. Copy agents (always overwrite)
cp "$SRC/.claude/agents/"*.md "$TARGET/.claude/agents/"

# 5. CLAUDE.md — never clobber. If present, write CLAUDE.optimization.md
#    next to it and tell the user to merge.
if [[ -f "$TARGET/CLAUDE.md" ]]; then
  cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.optimization.md"
  echo "NOTE: $TARGET/CLAUDE.md already exists."
  echo "      Wrote pack rules to CLAUDE.optimization.md — merge manually."
else
  cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md"
fi

# 6. settings.json — merge hooks block if file exists, else write fresh.
SETTINGS="$TARGET/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  if command -v python >/dev/null 2>&1; then
    python - "$SETTINGS" "$SRC/.claude/settings.json" <<'PYEOF'
import json, sys, pathlib
existing_path, new_path = sys.argv[1], sys.argv[2]
existing = json.loads(pathlib.Path(existing_path).read_text() or "{}")
new = json.loads(pathlib.Path(new_path).read_text())
existing.setdefault("hooks", {})
for event, entries in new.get("hooks", {}).items():
    existing["hooks"].setdefault(event, [])
    for entry in entries:
        if entry not in existing["hooks"][event]:
            existing["hooks"][event].append(entry)
pathlib.Path(existing_path).write_text(json.dumps(existing, indent=2) + "\n")
PYEOF
    echo "Merged hooks into existing $SETTINGS (backup: $SETTINGS.bak)"
  else
    echo "WARNING: python not found. Cannot merge settings.json."
    echo "         Existing file backed up to $SETTINGS.bak."
    echo "         Manually merge hooks from $SRC/.claude/settings.json"
  fi
else
  cp "$SRC/.claude/settings.json" "$SETTINGS"
fi

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  1. Start a new Claude Code session in $TARGET"
echo "  2. Checkpoint.md and EOD_Summary.md will be created automatically"
echo "  3. Try /persona-roundtable, /llm-audit, or /EOD_Summary"
