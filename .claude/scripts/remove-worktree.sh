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
# --git-common-dir returns path to the shared .git dir; repo root is its parent
REPO_ROOT="$(cd "$WORKTREE_PATH" && cd "$REPO_COMMON/.." && pwd -P)"

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

echo "Removing worktree at $WORKTREE_PATH..."

# Remove from the parent repo context
if [ "$FORCE_FLAG" = "--force" ]; then
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH" --force
else
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH"
fi

# Prune stale worktree metadata
git -C "$REPO_ROOT" worktree prune

echo "Worktree removed: $WORKTREE_PATH (branch: $BRANCH)"
exit 0
