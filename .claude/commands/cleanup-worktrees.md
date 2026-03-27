Scan all open worktrees, check whether their tickets are closed, and remove the ones that are done.

**Usage:** `/cleanup-worktrees`

No arguments. Operates across all repositories in `$CLAUDE_PROJECT_DIR/repositories/`.

**Important:** All script paths must use `$CLAUDE_PROJECT_DIR` as the root. Do NOT use relative paths.

1. **List all worktrees**: Run `$CLAUDE_PROJECT_DIR/.claude/scripts/list-worktrees.sh`
   - Collect every worktree that is NOT on `main` or `master`.

2. **Parse each branch name** to extract the platform and ticket ID using the naming convention `feature/<platform>-<id>-<slug>`:

   | Branch prefix | Platform | How to extract ID |
   |---------------|----------|-------------------|
   | `feature/gh-<number>-` | GitHub | number (e.g. `42`) |
   | `feature/linear-<team>-<number>-` | Linear | team+number (e.g. `ENG-123`) |
   | `feature/jira-<key>-` | Jira | key (e.g. `PROJ-123`) |

   If the branch name doesn't match any pattern, mark the worktree as **unparseable** — do not attempt to fetch ticket status.

3. **For each parseable worktree, fetch ticket status**:
   - **GitHub**: Get the remote URL via `git -C <worktree-path> remote get-url origin` to determine `<owner>/<repo>`. Run `gh issue view <number> --repo <owner>/<repo> --json state,title`. Closed if `state` is `CLOSED`.
   - **Linear**: Run `linear issue show <team>-<number>`. Closed if status is `Done`, `Cancelled`, or `Completed`.
   - **Jira**: Run `jira issue view <key> --json`. Closed if status is `Done`, `Closed`, or `Resolved`.

   If the CLI call fails (auth error, not found), mark the worktree as **unresolvable** rather than erroring out.

4. **Classify each worktree**:
   - `CLOSED` — ticket is done/cancelled/merged; safe to remove
   - `OPEN` — ticket is still active; keep
   - `UNPARSEABLE` — branch name didn't match any platform pattern
   - `UNRESOLVABLE` — CLI call failed

5. **Show summary table** and ask for confirmation before removing anything:

   ```
   Worktree Cleanup Summary
   ────────────────────────────────────────────────────────────────
   CLOSED (safe to remove):
     worktrees/feature/gh-42-add-auth        gh#42  "Add auth"
     worktrees/feature/linear-ENG-123-login  ENG-123  "User login"

   OPEN (keeping):
     worktrees/feature/gh-67-fix-cache       gh#67  "Fix cache bug"

   UNPARSEABLE (skipping):
     worktrees/feature/old-experiment

   UNRESOLVABLE (skipping):
     worktrees/feature/jira-PROJ-99-thing    (jira CLI returned error)
   ────────────────────────────────────────────────────────────────
   Remove 2 closed worktrees? (yes / no / list to choose individually)
   ```

6. **Remove based on response**:
   - `yes` — remove all CLOSED worktrees
   - `no` — exit without removing anything
   - `list` — prompt the user to confirm each CLOSED worktree individually

   For each removal: `$CLAUDE_PROJECT_DIR/.claude/scripts/remove-worktree.sh <worktree-path>`
   - If a worktree has uncommitted changes, skip it and flag it as **requires manual attention** regardless of ticket status.

7. **Final report**:
   ```
   Cleanup complete.
   Removed: [list of removed worktree paths]
   Skipped (dirty): [list, if any]
   Skipped (open/unparseable/unresolvable): [list]
   ```
