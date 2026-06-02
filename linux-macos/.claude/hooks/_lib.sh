#!/usr/bin/env bash
# Shared resolver for Checkpoint.md and EOD_Summary.md location.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#   resolve_managed_file "Checkpoint.md"
#   # Sets globals:
#   #   RESOLVED_PATH   — absolute path to the file we should use
#   #   RESOLVED_STATUS — one of:
#   #     cached | create | adopt | ambiguous-root | ambiguous-fallback
#   #   RESOLVED_NOTE   — human-readable message safe to put in additionalContext
#
# Resolution rules (with project.json cache layer):
#   0. If .claude/state/project.json exists AND its version matches AND
#      the cached path still exists on disk → return it (status: cached).
#   1. 0 matches  -> create at $ROOT/<filename> (status: create)
#   2. 1 match    -> adopt that path             (status: adopt)
#   3. 2+ matches -> if $ROOT/<filename> is among them, use it
#                       (status: ambiguous-root)
#                    else pick shortest-path-first (lex tiebreaker)
#                       (status: ambiguous-fallback)
#                    Both 2+ cases: RESOLVED_NOTE lists every match.
#                    If the cache holds acknowledged=true for the
#                    chosen path, the warning is suppressed.
#   After 1/2/3, project.json is updated (write-through cache).

# Schema version for .claude/state/project.json. Bump on incompatible
# schema changes; the resolver will treat older caches as a miss and
# rewrite.
__PROJECT_JSON_VERSION=1

# Directory names that are ALWAYS pruned during the scan.
__SKIP_DIRS=(
  .git
  .hg
  .svn
  node_modules
  .venv
  venv
  env
  dist
  build
  out
  .next
  .nuxt
  target
  __pycache__
  .pytest_cache
  .mypy_cache
  .tox
  .gradle
  .idea
  .vscode
  .claude
  .agents
)

# Internal: produce a stable project.json key for a filename.
__cache_key_for() {
  case "$1" in
    Checkpoint.md)  echo "checkpoint" ;;
    EOD_Summary.md) echo "eod_summary" ;;
    *)              echo "$1" ;;
  esac
}

# Internal: read cache hit if any. Echoes the cached path (or empty).
# Returns 0 on hit, 1 on miss/stale.
__cache_lookup() {
  local key="$1"
  local cache_file="$2"
  command -v python >/dev/null 2>&1 || return 1
  [[ -f "$cache_file" ]] || return 1

  local cached_path
  cached_path="$(python - "$cache_file" "$key" "$__PROJECT_JSON_VERSION" <<'PYEOF'
import json, os, sys
cache_file, key, version_s = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(cache_file, "r", encoding="utf-8") as f:
        d = json.load(f)
    if str(d.get("version", "")) != version_s:
        sys.exit(1)
    entry = d.get(key) or {}
    p = entry.get("path", "")
    if p and os.path.exists(p):
        print(p)
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
  )" || return 1
  [[ -n "$cached_path" ]] || return 1
  echo "$cached_path"
}

# Internal: is the cached entry acknowledged?
__cache_acknowledged() {
  local key="$1"
  local cache_file="$2"
  command -v python >/dev/null 2>&1 || return 1
  [[ -f "$cache_file" ]] || return 1
  python - "$cache_file" "$key" >/dev/null 2>&1 <<'PYEOF'
import json, sys
cache_file, key = sys.argv[1], sys.argv[2]
try:
    with open(cache_file, "r", encoding="utf-8") as f:
        d = json.load(f)
    if (d.get(key) or {}).get("acknowledged") is True:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
}

# Internal: write/update a cache entry (path, decision, alternatives).
__cache_write() {
  local cache_file="$1"
  local key="$2"
  local path="$3"
  local decision="$4"
  local alternatives_csv="$5"  # may be empty
  local cache_dir
  cache_dir="$(dirname "$cache_file")"
  mkdir -p "$cache_dir" 2>/dev/null || true
  command -v python >/dev/null 2>&1 || return 1
  python - "$cache_file" "$key" "$path" "$decision" "$alternatives_csv" \
           "$__PROJECT_JSON_VERSION" <<'PYEOF'
import json, sys, time, pathlib
cache_file, key, path, decision, alt_csv, version_s = sys.argv[1:7]
p = pathlib.Path(cache_file)
data = {}
if p.exists():
    try:
        with open(cache_file, "r", encoding="utf-8") as f:
            data = json.load(f) or {}
    except Exception:
        data = {}
data["version"] = int(version_s)
existing = data.get(key) or {}
acknowledged = bool(existing.get("acknowledged", False))
# If decision changed (e.g., user resolved an ambiguity) keep
# acknowledged sticky only when path is unchanged and still ambiguous.
if existing.get("path") != path:
    acknowledged = False
data[key] = {
    "path": path,
    "resolved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "decision": decision,
    "ambiguous_alternatives": [a for a in alt_csv.split("|") if a],
    "acknowledged": acknowledged,
}
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PYEOF
}

resolve_managed_file() {
  local filename="$1"
  local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local root_path="$root/$filename"
  local cache_file="$root/.claude/state/project.json"
  local cache_key
  cache_key="$(__cache_key_for "$filename")"

  # --- Cache layer ---
  local cached_path
  if cached_path="$(__cache_lookup "$cache_key" "$cache_file")"; then
    RESOLVED_PATH="$cached_path"
    RESOLVED_STATUS="cached"
    local rel="${cached_path#$root/}"
    local display
    if [[ "$cached_path" == "$root_path" ]]; then
      display="project root"
    else
      display="$rel"
    fi
    RESOLVED_NOTE="Using cached path for $filename ($display) from .claude/state/project.json. Delete the cache or move the file to force a re-scan."
    return 0
  fi

  # --- Scan layer (full tree walk) ---
  local prune_args=()
  local first=1
  for d in "${__SKIP_DIRS[@]}"; do
    if [[ $first -eq 1 ]]; then
      prune_args+=( -name "$d" )
      first=0
    else
      prune_args+=( -o -name "$d" )
    fi
  done

  local matches=()
  while IFS= read -r -d '' p; do
    matches+=( "$p" )
  done < <(
    find "$root" \
      \( -type d \( "${prune_args[@]}" \) -prune \) \
      -o \( -type f -name "$filename" -print0 \) \
      2>/dev/null
  )

  local count=${#matches[@]}

  if [[ $count -eq 0 ]]; then
    RESOLVED_PATH="$root_path"
    RESOLVED_STATUS="create"
    RESOLVED_NOTE="No existing $filename found in project tree; will create at project root."
    __cache_write "$cache_file" "$cache_key" "$root_path" "create" ""
    return 0
  fi

  if [[ $count -eq 1 ]]; then
    RESOLVED_PATH="${matches[0]}"
    RESOLVED_STATUS="adopt"
    if [[ "$RESOLVED_PATH" == "$root_path" ]]; then
      RESOLVED_NOTE="Adopted existing $filename at project root."
    else
      local rel="${RESOLVED_PATH#$root/}"
      RESOLVED_NOTE="Adopted existing $filename at $rel (single match in tree)."
    fi
    __cache_write "$cache_file" "$cache_key" "$RESOLVED_PATH" "adopt" ""
    return 0
  fi

  # 2+ matches — deterministic pick.
  local picked=""
  local status=""
  for p in "${matches[@]}"; do
    if [[ "$p" == "$root_path" ]]; then
      picked="$p"
      status="ambiguous-root"
      break
    fi
  done
  if [[ -z "$picked" ]]; then
    picked="$(
      printf '%s\n' "${matches[@]}" \
        | awk '{print length, $0}' \
        | sort -n -k1,1 -k2 \
        | head -n 1 \
        | cut -d' ' -f2-
    )"
    status="ambiguous-fallback"
  fi

  # Build alternatives list (pipe-separated for the cache writer).
  local alt_pipe=""
  for p in "${matches[@]}"; do
    [[ "$p" == "$picked" ]] && continue
    if [[ -z "$alt_pipe" ]]; then alt_pipe="$p"; else alt_pipe="$alt_pipe|$p"; fi
  done

  __cache_write "$cache_file" "$cache_key" "$picked" "$status" "$alt_pipe"

  # Suppress warning if user has acknowledged this resolution.
  if __cache_acknowledged "$cache_key" "$cache_file"; then
    RESOLVED_PATH="$picked"
    RESOLVED_STATUS="$status"
    local picked_rel="${picked#$root/}"
    [[ "$picked" == "$root_path" ]] && picked_rel="project root"
    RESOLVED_NOTE="Using $filename at $picked_rel (ambiguity acknowledged in .claude/state/project.json)."
    return 0
  fi

  # Build a human-readable list of all matches for the warning.
  local list=""
  for p in "${matches[@]}"; do
    local rel="${p#$root/}"
    if [[ -z "$list" ]]; then
      list="$rel"
    else
      list="$list, $rel"
    fi
  done

  local picked_rel="${picked#$root/}"
  RESOLVED_PATH="$picked"
  RESOLVED_STATUS="$status"
  RESOLVED_NOTE="WARNING: ${count} ${filename} files found in tree (${list}). Using ${picked_rel}. Set acknowledged=true in .claude/state/project.json to silence this warning, or consolidate to a single file."
  return 0
}
