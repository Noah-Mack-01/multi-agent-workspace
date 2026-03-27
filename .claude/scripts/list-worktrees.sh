#!/bin/bash
# list-worktrees.sh - List all worktrees with branch, path, and sync status
# Usage: list-worktrees.sh [repo-path]
#
# If repo-path is given, list worktrees for that specific repository.
# If no repo-path, iterate over all repos in repositories/ and list all worktrees.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_PATH="$1"

# print_submodule_worktrees <parent-worktree-path> <parent-repo-name>
# Prints indented submodule worktree entries under a parent worktree line.
print_submodule_worktrees() {
  local wt_path="$1"
  local parent_name="$2"
  local registry="$WORKSPACE_ROOT/repositories/$parent_name.submodules"

  [ -f "$registry" ] || return 0

  while IFS=$'\t' read -r sub_name sub_bare sub_path; do
    [[ "$sub_name" == \#* ]] && continue
    [ -z "$sub_name" ] && continue

    local sub_dir="$wt_path/$sub_path"
    if [ -d "$sub_dir" ] && [ -n "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
      local sha
      sha=$(git -C "$sub_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      echo "  └─ $sub_path    HEAD: $sha (detached)"
    else
      echo "  └─ $sub_path    (not initialized)"
    fi
  done < "$registry"
}

# List worktrees for a single repo
list_for_repo() {
  local repo="$1"

  # Detect main branch name
  local main_branch=""
  if git -C "$repo" rev-parse --verify main &>/dev/null; then
    main_branch="main"
  elif git -C "$repo" rev-parse --verify master &>/dev/null; then
    main_branch="master"
  fi

  # Parse porcelain output for structured data
  local wt_path="" branch="" commit="" bare=false

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "worktree "* ]]; then
      wt_path="${line#worktree }"
    elif [[ "$line" == "HEAD "* ]]; then
      commit="${line#HEAD }"
    elif [[ "$line" == "branch "* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ "$line" == "bare" ]]; then
      bare=true
    elif [[ -z "$line" ]]; then
      # End of entry, print it
      if [ -n "$wt_path" ]; then
        if [ "$bare" = true ]; then
          echo "Path:   $wt_path"
          echo "Branch: (bare)"
          echo "Commit: $commit"
          echo "Status: bare repository"
        else
          echo "Path:   $wt_path"
          echo "Branch: ${branch:-"(detached)"}"
          echo "Commit: ${commit:0:8}"

          # Check dirty state
          if [ -d "$wt_path" ]; then
            local dirty_count
            dirty_count=$(cd "$wt_path" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            if [ "$dirty_count" -gt 0 ]; then
              echo "Dirty:  yes ($dirty_count changed files)"
            else
              echo "Dirty:  no"
            fi
          else
            echo "Dirty:  (path not accessible)"
          fi

          # Check sync with main
          if [ -n "$main_branch" ] && [ -n "$branch" ] && [ "$branch" != "$main_branch" ]; then
            if [ -d "$wt_path" ]; then
              local merge_base main_head
              merge_base=$(cd "$wt_path" && git merge-base HEAD "$main_branch" 2>/dev/null || echo "")
              main_head=$(git -C "$repo" rev-parse "$main_branch" 2>/dev/null || echo "")
              if [ -n "$merge_base" ] && [ -n "$main_head" ]; then
                if [ "$merge_base" = "$main_head" ]; then
                  echo "Synced: yes (up to date with $main_branch)"
                else
                  echo "Synced: no (behind $main_branch)"
                fi
              else
                echo "Synced: unknown"
              fi
            fi
          elif [ "$branch" = "$main_branch" ]; then
            echo "Synced: n/a (is $main_branch)"
          fi

          # Show submodule worktrees
          local repo_name
          repo_name=$(basename "$repo" .git)
          print_submodule_worktrees "$wt_path" "$repo_name"
        fi
        echo "---"
      fi

      # Reset for next entry
      wt_path=""
      branch=""
      commit=""
      bare=false
    fi
  done < <(git -C "$repo" worktree list --porcelain; echo "")
}

if [ -n "$REPO_PATH" ]; then
  # Single repo mode
  if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Directory does not exist: $REPO_PATH"
    exit 1
  fi
  if ! git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
    echo "Error: Not a git repository: $REPO_PATH"
    exit 1
  fi
  echo "=== Worktrees for $(basename "$REPO_PATH") ==="
  echo ""
  list_for_repo "$REPO_PATH"
else
  # All-repos mode: iterate over repositories/
  REPOS_DIR="$WORKSPACE_ROOT/repositories"
  if [ ! -d "$REPOS_DIR" ]; then
    echo "No repositories directory found at $REPOS_DIR"
    exit 0
  fi

  found_any=false
  for repo_dir in "$REPOS_DIR"/*/; do
    [ ! -d "$repo_dir" ] && continue
    if git -C "$repo_dir" rev-parse --git-dir &>/dev/null; then
      found_any=true
      echo "=== Worktrees for $(basename "$repo_dir") ==="
      echo ""
      list_for_repo "$repo_dir"
      echo ""
    fi
  done

  if [ "$found_any" = false ]; then
    echo "No repositories found in $REPOS_DIR"
  fi
fi

exit 0
