#!/bin/bash
# ensure-analysis.sh - Ensure coupling data exists for a repository
# Usage: ensure-analysis.sh <repo-path> [output-dir]
#
# Validates the repo and checks for persisted coupling data files.
# Runs analyze-repo.sh if data files are missing.
# Outputs the absolute path to the data directory on stdout.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

if [ -z "$1" ]; then
  echo "Error: Repository path required" >&2
  echo "Usage: ensure-analysis.sh <repo-path> [output-dir]" >&2
  exit 1
fi

REPO_PATH="$(cd "$1" && pwd -P)" || { echo "Error: Directory does not exist: $1" >&2; exit 1; }
REPO_NAME="$(basename "$REPO_PATH")"
OUTPUT_DIR="${2:-$WORKSPACE_ROOT/analysis}"
DATA_DIR="$OUTPUT_DIR/$REPO_NAME"

# Validate git repository
git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "Error: Not a git repository: $1" >&2
  exit 1
}

# Check for required data files
if [ ! -f "$DATA_DIR/import_edges.txt" ] || [ ! -f "$DATA_DIR/cochange_pairs.txt" ]; then
  echo "Coupling data not found. Running analysis..." >&2
  "$SCRIPT_DIR/analyze-repo.sh" "$REPO_PATH" "$OUTPUT_DIR" >&2
fi

# Output the data directory path
echo "$DATA_DIR"
