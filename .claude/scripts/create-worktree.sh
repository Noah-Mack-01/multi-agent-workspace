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

# ---------- Submodule Worktrees ----------

init_submodule_worktrees() {
  local parent_worktree="$1"
  local parent_name
  parent_name=$(basename "$REPO_PATH" .git)
  local registry="$WORKSPACE_ROOT/repositories/$parent_name.submodules"

  [ -f "$registry" ] || return 0

  while IFS=$'\t' read -r sub_name sub_bare sub_path; do
    # Skip comment lines
    [[ "$sub_name" == \#* ]] && continue
    [ -z "$sub_name" ] && continue

    local target="$parent_worktree/$sub_path"

    # Guard: already exists and non-empty
    if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
      echo "  Warning: submodule path '$sub_path' already exists and is non-empty — skipping."
      continue
    fi

    # Resolve the gitlink SHA from the parent worktree
    local sha
    sha=$(git -C "$parent_worktree" ls-tree HEAD "$sub_path" 2>/dev/null | awk '{print $3}')
    if [ -z "$sha" ]; then
      echo "  Warning: could not resolve pointer SHA for submodule '$sub_path' — skipping."
      continue
    fi

    echo "  Initializing submodule worktree '$sub_path' at $sha..."

    # Ensure the SHA is present in the bare repo; fetch if not
    if ! git -C "$sub_bare" cat-file -e "$sha" 2>/dev/null; then
      echo "  SHA $sha not found locally — fetching submodule '$sub_name'..."
      if ! git -C "$sub_bare" fetch origin >&2; then
        echo "Error: Could not fetch submodule '$sub_name' to resolve SHA $sha" >&2
        exit 1
      fi
      if ! git -C "$sub_bare" cat-file -e "$sha" 2>/dev/null; then
        echo "Error: SHA $sha for submodule '$sub_name' not found even after fetch." >&2
        exit 1
      fi
    fi

    mkdir -p "$(dirname "$target")"
    git -C "$sub_bare" worktree add --detach "$target" "$sha"
  done < "$registry"
}

echo "Worktree created. Initializing submodule worktrees..."
init_submodule_worktrees "$WORKTREE_PATH"

echo "Installing dependencies..."

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
