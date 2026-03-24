#!/bin/bash
# pre-commit-sync.sh - PreToolUse hook that syncs with main before git commit
# Reads JSON from stdin, checks if the command is a git commit,
# and runs sync-main.sh to ensure the branch is up to date.

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$HOOK_DIR/../scripts"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
  exit 0
fi

# Determine working directory from the command or fall back to cwd
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Skip if we're on main/master (sync-main.sh handles this, but avoid noise)
CURRENT_BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  exit 0
fi

# Run sync-main.sh
SYNC_OUTPUT=$("$SCRIPT_DIR/sync-main.sh" "$CWD" 2>&1)
SYNC_EXIT=$?

if [ $SYNC_EXIT -ne 0 ]; then
  # Sync failed (likely merge conflicts) — block the commit
  jq -n --arg reason "sync-main.sh failed. Resolve conflicts before committing: $SYNC_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

# Sync succeeded — allow the commit, inject context so Claude knows what happened
jq -n --arg ctx "$SYNC_OUTPUT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'
exit 0
