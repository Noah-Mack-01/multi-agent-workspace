#!/bin/bash
# clone-repo.sh - Bare-clone a git repository into the workspace repositories directory
# Usage: clone-repo.sh <github-url>
#
# Bare-clones to repositories/<repo-name>.git/ under the workspace root.
# The bare repo serves as a shared object store for worktrees (no working tree).
# Idempotent: if already cloned, runs git fetch --all instead.
# Outputs the absolute path to the bare repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_URL="$1"

# ---------- Submodule Helpers ----------

# parse_gitmodules <bare-repo-path>
# Reads .gitmodules from the bare repo's HEAD and outputs lines of:
#   <name>\t<url>\t<declared-path>
# Outputs nothing (exit 0) if .gitmodules is absent.
parse_gitmodules() {
  local bare_repo="$1"
  local raw
  raw=$(git -C "$bare_repo" show HEAD:.gitmodules 2>/dev/null) || return 0
  [ -z "$raw" ] && return 0

  local name="" url="" path=""
  while IFS= read -r line; do
    case "$line" in
      *'[submodule '*)
        # Flush previous entry
        if [ -n "$name" ] && [ -n "$url" ] && [ -n "$path" ]; then
          printf '%s\t%s\t%s\n' "$name" "$url" "$path"
        fi
        name=$(echo "$line" | sed 's/.*\[submodule "\(.*\)"\].*/\1/')
        url=""
        path=""
        ;;
      *'url '*)
        url=$(echo "$line" | sed 's/.*url *= *\(.*\)/\1/' | tr -d '[:space:]')
        ;;
      *'path '*)
        path=$(echo "$line" | sed 's/.*path *= *\(.*\)/\1/' | tr -d '[:space:]')
        ;;
    esac
  done <<< "$raw"

  # Flush last entry
  if [ -n "$name" ] && [ -n "$url" ] && [ -n "$path" ]; then
    printf '%s\t%s\t%s\n' "$name" "$url" "$path"
  fi
}

# resolve_submodule_url <parent-remote-url> <submodule-url>
# Resolves a relative submodule URL (e.g. ../other-repo) against the parent
# remote URL. Absolute URLs are returned unchanged.
resolve_submodule_url() {
  local parent_url="$1"
  local sub_url="$2"

  case "$sub_url" in
    ../*|./*) ;;
    *) echo "$sub_url"; return 0 ;;
  esac

  # Strip trailing slash and last path component from parent URL to get base
  local base
  base=$(echo "$parent_url" | sed 's|/[^/]*$||')

  local rel="$sub_url"
  while [[ "$rel" == ../* ]]; do
    base=$(echo "$base" | sed 's|/[^/]*$||')
    rel="${rel#../}"
  done
  rel="${rel#./}"

  echo "$base/$rel"
}

if [ -z "$REPO_URL" ]; then
  echo "Error: GitHub URL required"
  echo "Usage: clone-repo.sh <github-url>"
  exit 1
fi

# Validate URL format (git@..., https://..., or file://...)
if ! echo "$REPO_URL" | grep -qE '^(https?://|git@|file://)'; then
  echo "Error: Invalid git URL: $REPO_URL"
  echo "  Expected: https://github.com/<owner>/<repo> or git@github.com:<owner>/<repo>.git"
  exit 1
fi

# Derive repo name from URL
REPO_NAME=$(basename "$REPO_URL" .git)

if [ -z "$REPO_NAME" ]; then
  echo "Error: Could not derive repository name from URL: $REPO_URL"
  exit 1
fi

REPO_DIR="$WORKSPACE_ROOT/repositories/$REPO_NAME.git"

if [ -d "$REPO_DIR" ] && git -C "$REPO_DIR" rev-parse --git-dir &>/dev/null; then
  # Already cloned — fetch latest
  echo "Repository already exists at $REPO_DIR. Fetching latest..."
  git -C "$REPO_DIR" fetch --all
else
  # Bare clone — no working tree, just the object store
  echo "Cloning $REPO_URL to $REPO_DIR (bare)..."
  mkdir -p "$WORKSPACE_ROOT/repositories"
  git clone --bare "$REPO_URL" "$REPO_DIR"
fi

# ---------- Submodule Registration ----------

register_submodules() {
  local parent_bare="$1"
  local parent_url="$2"
  local parent_name
  parent_name=$(basename "$parent_bare" .git)
  local registry="$WORKSPACE_ROOT/repositories/$parent_name.submodules"

  local submodules
  submodules=$(parse_gitmodules "$parent_bare") || true
  if [ -z "$submodules" ]; then
    # No submodules — remove stale registry if present
    rm -f "$registry"
    return 0
  fi

  # Truncate and rewrite registry
  printf '# name\tbare-repo-path\tdeclared-path-in-parent\n' > "$registry"

  while IFS=$'\t' read -r sub_name sub_url sub_path; do
    [ -z "$sub_name" ] && continue

    # Resolve relative URLs
    local resolved_url
    resolved_url=$(resolve_submodule_url "$parent_url" "$sub_url")

    local sub_repo_name
    sub_repo_name=$(basename "$resolved_url" .git)
    local sub_bare="$WORKSPACE_ROOT/repositories/$sub_repo_name.git"

    echo "  Registering submodule '$sub_name' ($resolved_url)..." >&2

    # Check for nested submodules (one-level limit)
    if [ -d "$sub_bare" ] && git -C "$sub_bare" rev-parse --git-dir &>/dev/null; then
      echo "  Submodule '$sub_name' already registered at $sub_bare. Fetching..." >&2
      git -C "$sub_bare" fetch --all >&2 || true
    else
      mkdir -p "$WORKSPACE_ROOT/repositories"
      if ! git clone --bare "$resolved_url" "$sub_bare" >&2; then
        echo "Error: Could not clone submodule '$sub_name' from $resolved_url" >&2
        exit 1
      fi
    fi

    # Warn if the submodule itself has submodules (do not recurse)
    if git -C "$sub_bare" show HEAD:.gitmodules &>/dev/null 2>&1; then
      echo "  Warning: submodule '$sub_name' contains nested submodules — nested submodules are not supported and will be skipped." >&2
    fi

    printf '%s\t%s\t%s\n' "$sub_name" "$sub_bare" "$sub_path" >> "$registry"
  done <<< "$submodules"

  echo "  Submodule registry written: $registry" >&2
}

register_submodules "$REPO_DIR" "$REPO_URL"

echo "$REPO_DIR"
exit 0
