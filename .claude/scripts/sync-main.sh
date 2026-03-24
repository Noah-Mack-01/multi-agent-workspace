#!/bin/bash
# sync-main.sh - Sync current branch with main/master before committing
# Usage: sync-main.sh <worktree-path>

set -e

WORKTREE_PATH="$1"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Error: Worktree path required"
  echo "Usage: sync-main.sh <worktree-path>"
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
  echo "On $CURRENT_BRANCH branch, skipping sync"
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

echo "Syncing $CURRENT_BRANCH with $MAIN_BRANCH..."

# Fetch latest main from origin
if ! git fetch origin "$MAIN_BRANCH:$MAIN_BRANCH" 2>/dev/null; then
  echo "Warning: Could not fetch $MAIN_BRANCH from origin. Using local $MAIN_BRANCH."
fi

# Check if main has new commits not in current branch
MERGE_BASE=$(git merge-base HEAD "$MAIN_BRANCH")
MAIN_HEAD=$(git rev-parse "$MAIN_BRANCH")

if [ "$MERGE_BASE" = "$MAIN_HEAD" ]; then
  echo "Branch is already synchronized with $MAIN_BRANCH"
  exit 0
fi

echo "$MAIN_BRANCH has new commits. Attempting to merge..."

# Attempt merge
if git merge "$MAIN_BRANCH" --no-edit; then
  echo "Successfully integrated $MAIN_BRANCH changes into $CURRENT_BRANCH"
else
  echo "Error: Merge conflict detected. Resolve conflicts manually:"
  echo "  1. Review conflicting files with: git status"
  echo "  2. Fix conflicts in each file"
  echo "  3. Stage resolved files: git add <resolved-files>"
  echo "  4. Complete the merge: git commit"
  echo "  5. Re-run: sync-main.sh $WORKTREE_PATH"
  git merge --abort 2>/dev/null || true
  exit 1
fi

exit 0
