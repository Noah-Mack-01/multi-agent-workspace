# Multi-Agent Worktree Workspace

## Worktree Workflow

When working on a feature or ticket, follow this sequence:

1. **Clone repository** (if needed) to `repositories/<repo-name>/`
2. **Create worktree** for your branch, pointing to the repository clone
3. **Work** in the worktree (make changes, run tests)
4. **Commit** your changes (sync with main runs automatically via hook)
5. **Push** to remote (sync verification runs automatically via hook)
6. **Create PR** linking to the originating ticket
7. **Cleanup** the worktree when done

## Hooks

Hooks in `.claude/hooks/` fire automatically on tool use. You do not need to call them manually.

- **pre-commit-sync.sh** — Runs `sync-main.sh` before every `git commit`. If the branch is behind main, it merges automatically. If there are merge conflicts, the commit is blocked and you must resolve them first.
- **pre-push-verify.sh** — Runs `verify-sync.sh` before every `git push`. If the branch is not up to date with main, the push is blocked.

## Available Scripts

All scripts are in `.claude/scripts/`. The sync and verify scripts are called automatically by hooks — you only need to call them manually for error recovery.

### Clone a repository
```bash
.claude/scripts/clone-repo.sh <github-url>
```
Bare-clones a repository to `repositories/<repo-name>.git/` (no working tree — just the object store for worktrees). Idempotent: if already cloned, fetches latest instead. Outputs the absolute path to the bare repo.

### Create a worktree
```bash
.claude/scripts/create-worktree.sh <repo-path> <branch-name> [worktree-base]
```
Creates a worktree at `worktrees/<branch-name>` (or custom worktree-base), checks out the branch from the specified repository, and installs dependencies automatically. The `<repo-path>` should point to a clone in `repositories/`.

### Install dependencies (standalone)
```bash
.claude/scripts/init-worktree.sh <worktree-path>
```
Detects the package manager from lockfiles and installs dependencies. Called automatically by `create-worktree.sh`. Run manually if you need to reinstall.

- `bun.lockb` → `bun install`
- `pnpm-lock.yaml` → `pnpm install`
- `go.mod` → `go mod download`

### Sync branch with main
```bash
.claude/scripts/sync-main.sh <worktree-path>
```
Fetches latest main/master and merges into the current branch. Called automatically by the pre-commit hook. Run manually only to resolve conflicts.

### Verify sync before pushing
```bash
.claude/scripts/verify-sync.sh <worktree-path>
```
Checks if the branch is up to date with main/master. Called automatically by the pre-push hook. Run manually only to diagnose sync issues.

### List all worktrees
```bash
.claude/scripts/list-worktrees.sh [repo-path]
```
Shows all active worktrees with their branch, commit, dirty state, and sync status with main. If `repo-path` is given, lists worktrees for that repo only. If omitted, lists worktrees across all repos in `repositories/`.

### Remove a worktree
```bash
.claude/scripts/remove-worktree.sh <worktree-path> [--force]
```
Safely removes a worktree. Refuses to remove if there are uncommitted changes unless `--force` is passed.

## Rules

- **One worktree per branch.** Git enforces this — you cannot checkout the same branch in two worktrees.
- **Never force push.** Use `--force-with-lease` if you must, but prefer avoiding it entirely.
- **Never hard reset.** These are denied in the Claude settings.
- **Clean up after yourself.** Remove worktrees when PRs are merged or work is abandoned.

## CLI Tools for Tickets

### GitHub Issues
```bash
gh issue list                          # List open issues
gh issue view <number>                 # View issue details
gh issue list --label "bug"            # Filter by label
gh issue list --assignee "@me"         # Your assigned issues
```

### GitHub Pull Requests
```bash
gh pr create --title "Title" --body "Description" --base main
gh pr create --fill                    # Auto-fill from commits
gh pr view <number>                    # View PR details
gh pr list                             # List open PRs
gh pr edit <number> --title "New title"
gh pr merge <number> --squash          # Merge with squash
```

### Linear
```bash
linear issue list                      # List issues
linear issue show <id>                 # Show issue details
linear issue start <id>                # Start working on issue
```

### Jira
```bash
jira issue list                        # List issues
jira issue view <key>                  # View issue (e.g., PROJ-123)
jira issue move <key> "In Progress"    # Transition issue status
```

## Full Workflow Example

```bash
# 1. Pick a ticket (or use /pick-ticket <repo-url> <ticket-url>)
gh issue view 42 --repo owner/repo

# 2. Clone the repo (idempotent)
REPO_PATH=$(.claude/scripts/clone-repo.sh https://github.com/owner/repo)

# 3. Create worktree for it
.claude/scripts/create-worktree.sh "$REPO_PATH" feature/issue-42

# 4. Work in the worktree
cd worktrees/feature/issue-42
# ... make changes, run tests ...

# 5. Commit (hook auto-syncs with main, blocks if conflicts)
git add -A
git commit -m "Implement feature for #42"

# 6. Push (hook auto-verifies sync, blocks if out of date)
git push -u origin feature/issue-42

# 7. Create PR (or use /submit-pr worktrees/feature/issue-42)
gh pr create --title "Implement feature for #42" --body "Closes #42" --base main

# 8. Clean up after merge
cd ../..
.claude/scripts/remove-worktree.sh worktrees/feature/issue-42
```

## Error Recovery

### Merge conflict during sync
If the pre-commit hook blocks due to conflicts:
1. `git status` in the worktree to see conflicting files
2. Edit and resolve each conflict
3. `git add <resolved-files>`
4. `git commit` to complete the merge
5. Re-run `.claude/scripts/sync-main.sh <worktree-path>` to confirm sync is clean

### Dependency installation failure
If `init-worktree.sh` fails:
1. Check that the package manager binary is installed (`bun --version`, `pnpm --version`, `go version`)
2. Check lockfile integrity in the worktree
3. Try running the install command manually with verbose output
4. Re-run `.claude/scripts/init-worktree.sh <worktree-path>`

### Stale worktrees
If `list-worktrees.sh` shows worktrees for merged/abandoned branches:
1. `.claude/scripts/remove-worktree.sh <path>` for each stale worktree
2. `git worktree prune` to clean up metadata
3. `git branch -d <branch>` to delete merged local branches

### Authentication failures
- **GitHub:** Run `gh auth status` to check, `gh auth login` to fix
- **Linear:** Check API token configuration
- **Jira:** Verify `JIRA_API_TOKEN` environment variable is set
