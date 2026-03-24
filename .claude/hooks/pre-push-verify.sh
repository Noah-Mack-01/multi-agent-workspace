#!/bin/bash
# pre-push-verify.sh - PreToolUse hook that verifies sync with main before git push
# Reads JSON from stdin, checks if the command is a git push,
# and runs verify-sync.sh to ensure the branch is up to date.

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$HOOK_DIR/../scripts"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git push commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push\b'; then
  exit 0
fi

# Determine working directory
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Skip if we're on main/master
CURRENT_BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  exit 0
fi

# Run verify-sync.sh
VERIFY_OUTPUT=$("$SCRIPT_DIR/verify-sync.sh" "$CWD" 2>&1)
VERIFY_EXIT=$?

if [ $VERIFY_EXIT -ne 0 ]; then
  # Not synced — block the push
  jq -n --arg reason "Branch is not synced with main. Run sync-main.sh first: $VERIFY_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

# Verified — allow the push
exit 0
