---
name: remove-worktree
description: Safely remove a git worktree with dirty-state protection
argument-hint: <worktree-path> [--force]
allowed-tools: Bash($CLAUDE_PROJECT_DIR/.claude/scripts/remove-worktree.sh *)
---

Remove a git worktree by running:

```
$CLAUDE_PROJECT_DIR/.claude/scripts/remove-worktree.sh $ARGUMENTS
```

If the worktree has uncommitted changes, the script will refuse to remove it unless `--force` is passed. Report the result to the user.
