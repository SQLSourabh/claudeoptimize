#!/usr/bin/env bash
# Shared resolver for Checkpoint.md and EOD_Summary.md location.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#   resolve_managed_file "Checkpoint.md"
#   # Sets globals:
#   #   RESOLVED_PATH   — absolute path to the file we should use
#   #   RESOLVED_STATUS — one of: create | adopt | ambiguous-root | ambiguous-fallback
#   #   RESOLVED_NOTE   — human-readable message safe to put in additionalContext
#
# Resolution rules (Option A):
#   0 matches  -> create at $ROOT/<filename> (status: create)
#   1 match    -> adopt that path             (status: adopt)
#   2+ matches -> if $ROOT/<filename> is among them, use it (status: ambiguous-root)
#                 else pick shortest-path-first (lex tiebreaker) (status: ambiguous-fallback)
#                 In both 2+ cases, RESOLVED_NOTE lists every match.

# Directory names that are ALWAYS pruned during the scan. We never expect
# the user's canonical Checkpoint to live inside any of these.
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

resolve_managed_file() {
  local filename="$1"
  local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  # Build the prune expression dynamically so a new entry in __SKIP_DIRS
  # is honored without touching the find command.
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

  # Collect matches. Null-delimited to survive paths with spaces.
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
  local root_path="$root/$filename"

  if [[ $count -eq 0 ]]; then
    RESOLVED_PATH="$root_path"
    RESOLVED_STATUS="create"
    RESOLVED_NOTE="No existing $filename found in project tree; will create at project root."
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
    # Sort by length, then lexicographically. Pure shell, no external deps
    # beyond awk (POSIX-standard).
    picked="$(
      printf '%s\n' "${matches[@]}" \
        | awk '{print length, $0}' \
        | sort -n -k1,1 -k2 \
        | head -n 1 \
        | cut -d' ' -f2-
    )"
    status="ambiguous-fallback"
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
  RESOLVED_NOTE="WARNING: ${count} ${filename} files found in tree (${list}). Using ${picked_rel}. Consolidate to a single file to silence this warning."
  return 0
}
