#!/bin/bash
# verify-sync.sh - Verify branch is synchronized with main/master before pushing
# Usage: verify-sync.sh <worktree-path>

set -e

WORKTREE_PATH="$1"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Error: Worktree path required"
  echo "Usage: verify-sync.sh <worktree-path>"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: Directory does not exist: $WORKTREE_PATH"
  exit 1
fi

cd "$WORKTREE_PATH"

CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
  echo "Error: Not on any branch (detached HEAD state)"
  exit 1
fi

# Skip if on main/master
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "On $CURRENT_BRANCH branch, skipping verification"
  exit 0
fi

# Detect main branch name
MAIN_BRANCH=""
if git rev-parse --verify main &>/dev/null; then
  MAIN_BRANCH="main"
elif git rev-parse --verify master &>/dev/null; then
  MAIN_BRANCH="master"
else
  echo "Error: Neither main nor master branch found"
  exit 1
fi

echo "Verifying $CURRENT_BRANCH is synchronized with $MAIN_BRANCH..."

# Fetch latest main from origin
if ! git fetch origin "$MAIN_BRANCH:$MAIN_BRANCH" 2>/dev/null; then
  echo "Warning: Could not fetch $MAIN_BRANCH from origin. Using local $MAIN_BRANCH."
fi

# Check if main has new commits not in current branch
MERGE_BASE=$(git merge-base HEAD "$MAIN_BRANCH")
MAIN_HEAD=$(git rev-parse "$MAIN_BRANCH")

if [ "$MERGE_BASE" != "$MAIN_HEAD" ]; then
  echo "Error: Branch is not synchronized with $MAIN_BRANCH."
  echo "  Run sync-main.sh first to integrate changes:"
  echo "  ./scripts/sync-main.sh $WORKTREE_PATH"
  exit 1
fi

echo "Branch is synchronized with $MAIN_BRANCH, safe to push"
exit 0