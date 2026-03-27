#!/bin/bash
# init-worktree.sh - Install dependencies in a worktree for fail-fast behavior
# Usage: init-worktree.sh <worktree-path>

set -e

WORKTREE_PATH="$1"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Error: Worktree path required"
  echo "Usage: init-worktree.sh <worktree-path>"
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: Directory does not exist: $WORKTREE_PATH"
  exit 1
fi

cd "$WORKTREE_PATH"

echo "Installing dependencies in $WORKTREE_PATH..."

# Detect package manager from lockfiles and install
if [ -f "bun.lockb" ]; then
  echo "Detected Bun (bun.lockb)"
  if ! command -v bun &>/dev/null; then
    echo "Error: bun is not installed. Install it: https://bun.sh"
    exit 1
  fi
  if ! bun install; then
    echo "Error: Dependency installation failed with Bun"
    exit 1
  fi
elif [ -f "pnpm-lock.yaml" ]; then
  echo "Detected PNPM (pnpm-lock.yaml)"
  if ! command -v pnpm &>/dev/null; then
    echo "Error: pnpm is not installed. Install it: https://pnpm.io/installation"
    exit 1
  fi
  if ! pnpm install; then
    echo "Error: Dependency installation failed with PNPM"
    exit 1
  fi
elif [ -f "go.mod" ]; then
  echo "Detected Go (go.mod)"
  if ! command -v go &>/dev/null; then
    echo "Error: go is not installed. Install it: https://go.dev/dl/"
    exit 1
  fi
  if ! go mod download; then
    echo "Error: Go module download failed"
    exit 1
  fi
else
  echo "Warning: No supported lockfile detected (bun.lockb, pnpm-lock.yaml, go.mod)"
  echo "Skipping parent dependency installation."
fi

echo "Dependencies installed successfully in $WORKTREE_PATH"

# ---------- Submodule Dependency Installation ----------

install_submodule_deps() {
  local worktree="$1"

  # Derive parent repo name from git common dir
  local common_dir
  common_dir=$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null) || return 0
  # Resolve to absolute path
  common_dir=$(cd "$worktree" && cd "$common_dir" && pwd -P)
  local parent_name
  parent_name=$(basename "$common_dir" .git)

  # Locate workspace root (two levels up from scripts/ dir, derived from common_dir)
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local workspace_root="${WORKSPACE_ROOT:-$(cd "$script_dir/../.." && pwd)}"
  local registry="$workspace_root/repositories/$parent_name.submodules"

  [ -f "$registry" ] || return 0

  local any_failure=0

  while IFS=$'\t' read -r sub_name sub_bare sub_path; do
    [[ "$sub_name" == \#* ]] && continue
    [ -z "$sub_name" ] && continue

    local sub_dir="$worktree/$sub_path"

    if [ ! -d "$sub_dir" ] || [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
      echo "Warning: submodule '$sub_path' is not initialized — skipping dependency installation."
      continue
    fi

    echo "Installing dependencies for submodule '$sub_path'..."
    cd "$sub_dir"

    if [ -f "bun.lockb" ]; then
      echo "  Detected Bun (bun.lockb)"
      command -v bun &>/dev/null || { echo "Error: bun not installed"; any_failure=1; cd "$worktree"; continue; }
      bun install || { echo "Error: bun install failed in $sub_path"; any_failure=1; }
    elif [ -f "pnpm-lock.yaml" ]; then
      echo "  Detected PNPM (pnpm-lock.yaml)"
      command -v pnpm &>/dev/null || { echo "Error: pnpm not installed"; any_failure=1; cd "$worktree"; continue; }
      pnpm install || { echo "Error: pnpm install failed in $sub_path"; any_failure=1; }
    elif [ -f "go.mod" ]; then
      echo "  Detected Go (go.mod)"
      command -v go &>/dev/null || { echo "Error: go not installed"; any_failure=1; cd "$worktree"; continue; }
      go mod download || { echo "Error: go mod download failed in $sub_path"; any_failure=1; }
    else
      echo "  No supported lockfile in '$sub_path' — skipping."
    fi

    cd "$worktree"
  done < "$registry"

  return $any_failure
}

if ! install_submodule_deps "$WORKTREE_PATH"; then
  echo "Warning: one or more submodule dependency installations failed."
  exit 1
fi

exit 0
