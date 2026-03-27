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

# ---------- Submodule Pointer Sync ----------

sync_submodule_pointers() {
  local worktree="$1"

  local common_dir
  common_dir=$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null) || return 0
  common_dir=$(cd "$worktree" && cd "$common_dir" && pwd -P)
  local parent_name
  parent_name=$(basename "$common_dir" .git)

  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local workspace_root="${WORKSPACE_ROOT:-$(cd "$script_dir/../.." && pwd)}"
  local registry="$workspace_root/repositories/$parent_name.submodules"

  [ -f "$registry" ] || return 0

  while IFS=$'\t' read -r sub_name sub_bare sub_path; do
    [[ "$sub_name" == \#* ]] && continue
    [ -z "$sub_name" ] && continue

    local sub_dir="$worktree/$sub_path"

    if [ ! -d "$sub_dir" ]; then
      echo "  Warning: submodule worktree '$sub_path' does not exist — skipping pointer sync."
      continue
    fi

    local new_sha
    new_sha=$(git -C "$worktree" ls-tree HEAD "$sub_path" 2>/dev/null | awk '{print $3}')
    if [ -z "$new_sha" ]; then
      echo "  Warning: could not read pointer SHA for submodule '$sub_path' — skipping."
      continue
    fi

    local current_sha
    current_sha=$(git -C "$sub_dir" rev-parse HEAD 2>/dev/null) || current_sha=""

    if [ "$new_sha" = "$current_sha" ]; then
      echo "  Submodule '$sub_path' already at $new_sha — no update needed."
      continue
    fi

    echo "  Updating submodule '$sub_path': $current_sha → $new_sha"

    # Ensure SHA is present locally; fetch if not
    if ! git -C "$sub_bare" cat-file -e "$new_sha" 2>/dev/null; then
      echo "  Fetching submodule '$sub_name' to resolve $new_sha..."
      if ! git -C "$sub_bare" fetch origin; then
        echo "Error: Could not fetch submodule '$sub_name'" >&2
        exit 1
      fi
      if ! git -C "$sub_bare" cat-file -e "$new_sha" 2>/dev/null; then
        echo "Error: SHA $new_sha for submodule '$sub_name' not found after fetch." >&2
        exit 1
      fi
    fi

    git -C "$sub_dir" checkout "$new_sha"
    echo "  Submodule '$sub_path' updated to $new_sha"
  done < "$registry"
}

sync_submodule_pointers "$WORKTREE_PATH"

exit 0
