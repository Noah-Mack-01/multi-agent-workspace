---
name: create-worktree
description: Create a new git worktree for a branch in a specific repository and install dependencies
argument-hint: <repo-path> <branch-name> [worktree-base]
allowed-tools: Bash($CLAUDE_PROJECT_DIR/.claude/scripts/create-worktree.sh *)
---

Create a new git worktree by running:

```
$CLAUDE_PROJECT_DIR/.claude/scripts/create-worktree.sh $ARGUMENTS
```

The `<repo-path>` should point to a clone in `repositories/`. If the script fails, report the error and suggest fixes based on the output.
