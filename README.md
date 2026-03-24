# Multi-Agent Worktree Workspace

A portable `.claude/` configuration that enables multiple AI agents to work concurrently on different branches of a repository using git worktrees. Repos are bare-cloned as shared object stores, and each agent gets an isolated worktree — no merge conflicts between parallel workers.

## Architecture

```
multi-agent-workspace/
├── .claude/
│   ├── scripts/         # Shell scripts (the actual logic)
│   ├── skills/          # Single-script wrappers invoked via /skill-name
│   ├── commands/        # Multi-step procedures invoked via /command-name
│   ├── hooks/           # PreToolUse hooks (fire automatically)
│   └── settings.json    # Permissions + hook configuration
├── repositories/        # Bare-cloned repos (object stores, no working tree)
├── worktrees/           # Isolated branch checkouts (where work happens)
├── analysis/            # Repo coupling analysis output
└── CLAUDE.md            # Agent workflow instructions
```

Repos in `repositories/` are bare clones (`.git` only). Worktrees in `worktrees/` are lightweight checkouts that share the same git objects. Multiple worktrees can exist simultaneously on different branches.

## Quick Start

```bash
# Pick up a ticket — clones the repo and creates a worktree
/pick-ticket https://github.com/owner/repo https://github.com/owner/repo/issues/42

# Analyze the repo for parallelization opportunities
/analyze-module repositories/repo.git

# Build interface signatures and a parallel work plan
/build-signatures repositories/repo.git

# Implement the feature with parallel agents
/parallel-build worktrees/feature/42-add-auth https://github.com/owner/repo/issues/42

# Commit, push, and submit a PR
cd worktrees/feature/42-add-auth
git add -A && git commit -m "feat: implement feature"
/submit-pr worktrees/feature/42-add-auth

# Clean up
/remove-worktree worktrees/feature/42-add-auth
```

## Scripts

All scripts live in `.claude/scripts/`. They are self-contained shell scripts with no external dependencies beyond git and jq.

| Script | Usage | Purpose |
|--------|-------|---------|
| `clone-repo.sh` | `<github-url>` | Bare-clone a repo to `repositories/<name>.git/`. Idempotent — fetches if already cloned. |
| `create-worktree.sh` | `<repo-path> <branch-name> [worktree-base]` | Create a worktree and install dependencies. |
| `remove-worktree.sh` | `<worktree-path> [--force]` | Remove a worktree. Blocks if dirty unless `--force`. |
| `list-worktrees.sh` | `[repo-path]` | List worktrees with branch, dirty state, and sync status. Lists all repos if no path given. |
| `init-worktree.sh` | `<worktree-path>` | Install dependencies (detects bun/pnpm/go from lockfiles). Called automatically by `create-worktree.sh`. |
| `sync-main.sh` | `<worktree-path>` | Fetch and merge main into the branch. Called automatically by pre-commit hook. |
| `verify-sync.sh` | `<worktree-path>` | Check if branch is up to date with main. Called automatically by pre-push hook. |
| `analyze-repo.sh` | `<repo-path> [output-dir]` | Generate a deterministic coupling analysis of the repo. Output goes to `analysis/`. Persists structured data files to `analysis/<repo-name>/`. |
| `ensure-analysis.sh` | `<repo-path> [output-dir]` | Validate repo and ensure coupling data exists. Runs `analyze-repo.sh` if data files are missing. Outputs the data directory path. |
| `test-workflow.sh` | _(no args)_ | Run the full test suite. |

## Skills

Skills wrap a single script and are invoked as `/skill-name <args>`.

| Skill | Wraps | Arguments |
|-------|-------|-----------|
| `/create-worktree` | `create-worktree.sh` | `<repo-path> <branch-name> [worktree-base]` |
| `/remove-worktree` | `remove-worktree.sh` | `<worktree-path> [--force]` |
| `/list-worktrees` | `list-worktrees.sh` | `[repo-path]` |
| `/analyze-module` | `analyze-repo.sh` | `<repo-path>` |
| `/build-signatures` | `ensure-analysis.sh` + Claude reasoning | `<repo-path>` |

## Commands

Commands are multi-step procedures invoked as `/command-name <args>`.

| Command | Arguments | What it does |
|---------|-----------|-------------|
| `/pick-ticket` | `<repo-url> <ticket-url>` | Clone repo (if needed) → fetch ticket details (GitHub/Linear/Jira) → derive branch name → create worktree |
| `/parallel-build` | `<worktree-path> <ticket-url>` | Read ticket + parallel plan → spawn agents per work unit in phased order → run tests → report results |
| `/submit-pr` | `<worktree-path>` | Sync with main → verify sync → push → create PR via `gh` |

## Hooks

Hooks fire automatically before tool execution. No manual invocation needed.

| Hook | Triggers on | Action |
|------|------------|--------|
| `pre-commit-sync.sh` | `git commit` | Syncs branch with main. Blocks commit if merge conflicts. |
| `pre-push-verify.sh` | `git push` | Verifies branch is up to date with main. Blocks push if not. |

## Permissions

Configured in `.claude/settings.json`:

**Allowed:** `git`, `bun`, `pnpm`, `gh`, `linear`, `jira`, and all scripts in `.claude/scripts/`.

**Denied:** `git push --force`, `git push -f`, `git reset --hard`, `git clean -f`, `rm -rf`.

## Testing

```bash
.claude/scripts/test-workflow.sh
```

Creates temporary repos in `/tmp`, exercises all scripts (clone, create, list, sync, verify, remove, init, analyze, ensure-analysis), and cleans up. Currently 29 tests.

## Workflows

### Manual (single agent)

```
 ┌──────────────┐
 │  /pick-ticket │  clone repo + fetch ticket + create worktree
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  Work in      │  edit files, run tests in worktrees/<branch>/
 │  worktree     │
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  git commit   │  hook auto-syncs with main, blocks on conflicts
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  git push     │  hook verifies sync, blocks if behind
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  /submit-pr   │  sync + verify + push + create PR
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  /remove-     │  clean up worktree after merge
 │  worktree     │
 └──────────────┘
```

### Parallel (multi-agent)

```
 ┌──────────────┐
 │  /pick-ticket │  clone repo + fetch ticket + create worktree
 └──────┬───────┘
        ▼
 ┌────────────────┐
 │ /analyze-module │  map file coupling + parallelization boundaries
 └──────┬─────────┘
        ▼
 ┌──────────────────┐
 │ /build-signatures │  define interface contracts between coupled files
 └──────┬───────────┘  → signatures.md + parallel-plan.md
        ▼
 ┌──────────────────┐
 │ /parallel-build   │  spawn agents per work unit in phased order
 │                    │  Phase 1: independent units run concurrently
 │                    │  Phase 2: dependent units run after Phase 1
 │                    │  ...then run tests
 └──────┬───────────┘
        ▼
 ┌──────────────┐
 │  git commit   │  hook auto-syncs with main
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  /submit-pr   │  sync + verify + push + create PR
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  /remove-     │  clean up worktree after merge
 │  worktree     │
 └──────────────┘
```

## Portability

This entire workspace is a `.claude/` configuration directory. To use it on a different machine:

1. Clone this repo
2. Ensure `git`, `jq`, `gh` are installed
3. Run `/pick-ticket` with a repo URL and ticket URL

No language runtimes, databases, or external services are required for the orchestration layer itself. Language-specific tooling (bun, pnpm, go) is only needed when `init-worktree.sh` detects a lockfile in the target repo.
