---
name: analyze-module
description: Analyze a repository to map file coupling and identify parallelization boundaries
argument-hint: <repo-path>
allowed-tools: Bash($CLAUDE_PROJECT_DIR/.claude/scripts/analyze-repo.sh *)
---

Analyze the repository at `$ARGUMENTS` by running:

```
$CLAUDE_PROJECT_DIR/.claude/scripts/analyze-repo.sh $ARGUMENTS
```

Report the analysis location and summarize key findings: number of coupling groups, strongest cross-group coupling, and parallelization opportunities.
