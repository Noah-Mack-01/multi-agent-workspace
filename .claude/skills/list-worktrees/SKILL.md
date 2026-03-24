---
name: list-worktrees
description: List git worktrees with branch, status, and sync information for one or all repositories
argument-hint: [repo-path]
allowed-tools: Bash($CLAUDE_PROJECT_DIR/.claude/scripts/list-worktrees.sh *)
---

List active worktrees by running:

```
$CLAUDE_PROJECT_DIR/.claude/scripts/list-worktrees.sh $ARGUMENTS
```

If no repo-path is provided, all repositories in the workspace are listed. Present the output clearly, highlighting any worktrees that are out of sync with main or have uncommitted changes.
