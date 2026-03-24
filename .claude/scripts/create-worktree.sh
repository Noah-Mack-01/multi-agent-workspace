#!/bin/bash
# create-worktree.sh - Create a new git worktree and install dependencies
# Usage: create-worktree.sh <repo-path> <branch-name> [worktree-base]
#
# Creates a worktree at <worktree-base>/<branch-name> (default: $WORKSPACE_ROOT/worktrees/<branch-name>)
# Automatically runs init-worktree.sh to install dependencies after creation.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_PATH="$1"
BRANCH_NAME="$2"
BASE_DIR="${3:-$WORKSPACE_ROOT/worktrees}"

if [ -z "$REPO_PATH" ] || [ -z "$BRANCH_NAME" ]; then
  echo "Error: Repository path and branch name required"
  echo "Usage: create-worktree.sh <repo-path> <branch-name> [worktree-base]"
  exit 1
fi

# Resolve repo path to absolute
if [ ! -d "$REPO_PATH" ]; then
  echo "Error: Repository directory does not exist: $REPO_PATH"
  exit 1
fi
REPO_PATH="$(cd "$REPO_PATH" && pwd -P)"

# Verify it's a git repository
if ! git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
  echo "Error: Not a git repository: $REPO_PATH"
  exit 1
fi

# Resolve base directory to absolute path
BASE_DIR="$(mkdir -p "$BASE_DIR" && cd "$BASE_DIR" && pwd)"
WORKTREE_PATH="$BASE_DIR/$BRANCH_NAME"

# Check if branch already has a worktree
if git -C "$REPO_PATH" worktree list --porcelain | grep -q "branch refs/heads/$BRANCH_NAME$"; then
  echo "Error: Branch '$BRANCH_NAME' already has a worktree"
  echo "  Use: git -C $REPO_PATH worktree list  to see existing worktrees"
  exit 1
fi

# Check if worktree path already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "Error: Directory already exists: $WORKTREE_PATH"
  exit 1
fi

echo "Creating worktree for branch '$BRANCH_NAME' at $WORKTREE_PATH..."

# Create worktree with new branch if it doesn't exist, or checkout existing branch
if git -C "$REPO_PATH" rev-parse --verify "$BRANCH_NAME" &>/dev/null; then
  echo "Checking out existing branch: $BRANCH_NAME"
  git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
else
  echo "Creating new branch: $BRANCH_NAME"
  git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
fi

echo "Worktree created. Installing dependencies..."

# Run init-worktree.sh to install dependencies
if ! "$SCRIPT_DIR/init-worktree.sh" "$WORKTREE_PATH"; then
  echo "Warning: Dependency installation failed. Worktree is created but may not be ready."
  echo "  Re-run manually: $SCRIPT_DIR/init-worktree.sh $WORKTREE_PATH"
  exit 1
fi

echo ""
echo "Worktree ready: $WORKTREE_PATH"
echo "  Repository: $REPO_PATH"
echo "  Branch: $BRANCH_NAME"
echo "  To work in it: cd $WORKTREE_PATH"
exit 0
