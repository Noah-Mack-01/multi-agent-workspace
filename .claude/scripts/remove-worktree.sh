#!/bin/bash
# remove-worktree.sh - Safely remove a git worktree with dirty-state checks
# Usage: remove-worktree.sh <worktree-path> [--force]

set -e

WORKTREE_PATH="$1"
FORCE_FLAG="$2"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Error: Worktree path required"
  echo "Usage: remove-worktree.sh <worktree-path> [--force]"
  exit 1
fi

# Resolve to real absolute path (handles macOS /private/var symlinks)
if [ -d "$WORKTREE_PATH" ]; then
  WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd -P)"
fi

# Verify the directory exists
if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: Directory does not exist: $WORKTREE_PATH"
  exit 1
fi

# Determine the parent repo from the worktree using git-common-dir
# This works for both worktrees (.git file) and the main checkout (.git directory)
REPO_COMMON=$(cd "$WORKTREE_PATH" && git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -z "$REPO_COMMON" ]; then
  echo "Error: Could not determine parent repository for: $WORKTREE_PATH"
  exit 1
fi
# Resolve common dir to absolute path
REPO_COMMON="$(cd "$WORKTREE_PATH" && cd "$REPO_COMMON" && pwd -P)"
# For bare repos, the common dir IS the repo root; for non-bare, go up one level from .git/
IS_BARE=$(git -C "$REPO_COMMON" rev-parse --is-bare-repository 2>/dev/null || echo "false")
if [ "$IS_BARE" = "true" ]; then
  REPO_ROOT="$REPO_COMMON"
else
  REPO_ROOT="$(dirname "$REPO_COMMON")"
fi

# Verify the worktree is registered in the parent repo
if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "worktree $WORKTREE_PATH$"; then
  echo "Error: $WORKTREE_PATH is not a registered worktree of $REPO_ROOT"
  echo "  Use: git -C $REPO_ROOT worktree list  to see existing worktrees"
  exit 1
fi

# Check for uncommitted changes
DIRTY=$(cd "$WORKTREE_PATH" && git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  if [ "$FORCE_FLAG" = "--force" ]; then
    echo "Warning: Worktree has uncommitted changes. Removing anyway (--force)."
  else
    echo "Error: Worktree has uncommitted changes:"
    (cd "$WORKTREE_PATH" && git status --short)
    echo ""
    echo "  Commit or stash changes first, or use --force to remove anyway:"
    echo "  .claude/scripts/remove-worktree.sh $WORKTREE_PATH --force"
    exit 1
  fi
fi

# Get branch name before removal for reporting
BRANCH=$(cd "$WORKTREE_PATH" 2>/dev/null && git branch --show-current 2>/dev/null || echo "unknown")

# ---------- Submodule Worktree Removal ----------

SUBMODULES_REMOVED=false

remove_submodule_worktrees() {
  local worktree="$1"
  local force_flag="$2"

  local parent_name
  parent_name=$(basename "$REPO_ROOT" .git)

  SCRIPT_DIR_RS="$(cd "$(dirname "$0")" && pwd)"
  local workspace_root="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR_RS/../.." && pwd)}"
  local registry="$workspace_root/repositories/$parent_name.submodules"

  [ -f "$registry" ] || return 0

  while IFS=$'\t' read -r sub_name sub_bare sub_path; do
    [[ "$sub_name" == \#* ]] && continue
    [ -z "$sub_name" ] && continue

    local sub_dir="$worktree/$sub_path"

    # Check if this path is a registered worktree in the submodule's bare repo
    if ! git -C "$sub_bare" worktree list --porcelain 2>/dev/null | grep -qF "worktree $sub_dir"; then
      continue
    fi

    echo "  Removing submodule worktree '$sub_path'..."
    if [ "$force_flag" = "--force" ]; then
      git -C "$sub_bare" worktree remove "$sub_dir" --force
    else
      git -C "$sub_bare" worktree remove "$sub_dir"
    fi
    git -C "$sub_bare" worktree prune
    echo "  Submodule worktree removed: $sub_dir"
    SUBMODULES_REMOVED=true
  done < "$registry"
}

remove_submodule_worktrees "$WORKTREE_PATH" "$FORCE_FLAG"

echo "Removing worktree at $WORKTREE_PATH..."

# After removing submodule worktrees, git sees missing gitlinks as modifications.
# Force-remove the parent in that case since the state is expected and intentional.
EFFECTIVE_FORCE="$FORCE_FLAG"
if [ "$SUBMODULES_REMOVED" = true ]; then
  EFFECTIVE_FORCE="--force"
fi

if [ "$EFFECTIVE_FORCE" = "--force" ]; then
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH" --force
else
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH"
fi

# Prune stale worktree metadata
git -C "$REPO_ROOT" worktree prune

echo "Worktree removed: $WORKTREE_PATH (branch: $BRANCH)"
exit 0
