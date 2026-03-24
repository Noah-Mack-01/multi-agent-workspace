#!/bin/bash
# clone-repo.sh - Bare-clone a git repository into the workspace repositories directory
# Usage: clone-repo.sh <github-url>
#
# Bare-clones to repositories/<repo-name>.git/ under the workspace root.
# The bare repo serves as a shared object store for worktrees (no working tree).
# Idempotent: if already cloned, runs git fetch --all instead.
# Outputs the absolute path to the bare repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_URL="$1"

if [ -z "$REPO_URL" ]; then
  echo "Error: GitHub URL required"
  echo "Usage: clone-repo.sh <github-url>"
  exit 1
fi

# Validate URL format (git@..., https://..., or file://...)
if ! echo "$REPO_URL" | grep -qE '^(https?://|git@|file://)'; then
  echo "Error: Invalid git URL: $REPO_URL"
  echo "  Expected: https://github.com/<owner>/<repo> or git@github.com:<owner>/<repo>.git"
  exit 1
fi

# Derive repo name from URL
REPO_NAME=$(basename "$REPO_URL" .git)

if [ -z "$REPO_NAME" ]; then
  echo "Error: Could not derive repository name from URL: $REPO_URL"
  exit 1
fi

REPO_DIR="$WORKSPACE_ROOT/repositories/$REPO_NAME.git"

if [ -d "$REPO_DIR" ] && git -C "$REPO_DIR" rev-parse --git-dir &>/dev/null; then
  # Already cloned — fetch latest
  echo "Repository already exists at $REPO_DIR. Fetching latest..."
  git -C "$REPO_DIR" fetch --all
else
  # Bare clone — no working tree, just the object store
  echo "Cloning $REPO_URL to $REPO_DIR (bare)..."
  mkdir -p "$WORKSPACE_ROOT/repositories"
  git clone --bare "$REPO_URL" "$REPO_DIR"
fi

echo "$REPO_DIR"
exit 0
