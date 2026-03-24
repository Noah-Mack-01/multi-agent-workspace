Complete the PR submission workflow for the worktree at `$ARGUMENTS`.

**Important:** All script paths must use `$CLAUDE_PROJECT_DIR` as the root. Do NOT use relative paths — you may be running from inside a worktree.

1. **Sync with main**: `$CLAUDE_PROJECT_DIR/.claude/scripts/sync-main.sh $ARGUMENTS`
   - If conflicts occur, stop and report them. Do not continue.

2. **Verify sync**: `$CLAUDE_PROJECT_DIR/.claude/scripts/verify-sync.sh $ARGUMENTS`
   - If verification fails, stop and report the issue.

3. **Push the branch**:
   ```
   git -C $ARGUMENTS push -u origin $(git -C $ARGUMENTS branch --show-current)
   ```

4. **Check for existing PR**: `git -C $ARGUMENTS` then `gh pr list --head $(git -C $ARGUMENTS branch --show-current)`
   - If a PR already exists, report it and ask if the user wants to update it.

5. **Create PR**: From the worktree directory, run `gh pr create --fill --base main`
   - Use `--fill` to auto-populate from commit messages.
   - Ask the user if they want to customize the title or body before creating.

Report the PR URL when complete.
