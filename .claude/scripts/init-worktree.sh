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
  echo "Skipping dependency installation."
  exit 0
fi

echo "Dependencies installed successfully in $WORKTREE_PATH"
exit 0
