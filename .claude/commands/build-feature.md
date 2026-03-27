Pick up a ticket, implement it in a worktree, and open a PR.

**Usage:** `/build-feature <repo-url> <ticket-url> [--parallel]`

| Argument | Required | Description |
|----------|----------|-------------|
| `repo-url` | yes | GitHub HTTPS URL of the repository (e.g. `https://github.com/owner/repo`) |
| `ticket-url` | yes | URL of the ticket to implement — GitHub Issue, Linear, or Jira |
| `--parallel` | no | Dispatch multiple agents in parallel across file boundaries instead of a single agent. Best for large features with clearly independent modules. |

**Important:** All script paths must use `$CLAUDE_PROJECT_DIR` as the root. Do NOT use relative paths — you may be running from inside a worktree.

Given arguments `$ARGUMENTS` (format: `<repo-url> <ticket-url> [--parallel]`):

1. **Parse arguments**: Extract `<repo-url>`, `<ticket-url>`, and the optional `--parallel` flag from `$ARGUMENTS`. If either required argument is missing, stop and tell the user: "Usage: `/build-feature <repo-url> <ticket-url> [--parallel]` — `repo-url` and `ticket-url` are required. `repo-url` is the GitHub HTTPS clone URL; `ticket-url` is a GitHub Issue, Linear, or Jira ticket URL."

2. **Clone or fetch the repository**: Run `$CLAUDE_PROJECT_DIR/.claude/scripts/clone-repo.sh <repo-url>`
   - Capture the output to get the absolute repo path (last line of output).

3. **Fetch ticket details**: Parse the ticket URL to detect platform and fetch the ticket:
   - `github.com/<owner>/<repo>/issues/<number>` → Run `gh issue view <number> --repo <owner>/<repo>`
   - `linear.app/*/issue/<team>-<number>/*` → Extract the issue ID (e.g., `ENG-123`). Run `linear issue show <id>`
   - `*.atlassian.net/browse/<key>` → Extract the issue key (e.g., `PROJ-123`). Run `jira issue view <key>`
   - If the URL doesn't match any known pattern, stop and tell the user the format is not recognized.
   - Save the ticket title and description.

4. **Derive branch name** from the ticket, using a platform prefix so the source is unambiguous:
   - GitHub Issue → `feature/gh-<number>-<slug>` (e.g., `feature/gh-42-add-auth`)
   - Linear → `feature/linear-<team>-<number>-<slug>` (e.g., `feature/linear-ENG-123-user-login`)
   - Jira → `feature/jira-<key>-<slug>` (e.g., `feature/jira-PROJ-123-fix-thing`)
   - Slugify the ticket title: lowercase, replace spaces with hyphens, strip special characters, max 40 chars for the slug portion.

5. **Create worktree**: `$CLAUDE_PROJECT_DIR/.claude/scripts/create-worktree.sh <repo-path> <branch-name>`
   - Capture the worktree path from the output. Resolve it to an absolute path.

6. **Implement the feature**: Branch on whether `--parallel` was passed.

   **Default (single agent):** Spawn one general-purpose agent with this prompt:

   ```
   You are implementing a ticket in the repository at [worktree-path].

   ## Ticket
   **[ticket title]**
   [ticket description]

   ## Instructions
   1. Explore the codebase to understand the structure and relevant files
   2. Implement the changes required by the ticket
   3. Follow the existing code style and conventions
   4. Run the test suite when done:
      - bun.lockb → `bun test`
      - pnpm-lock.yaml → `pnpm test`
      - go.mod → `go test ./...`
      - package.json with test script → `npm test`
      - If no test suite detected, skip
   5. Fix any test failures introduced by your changes. If tests still fail after one attempt, report the remaining failures.
   6. Report: which files you changed and a summary of what you did
   ```

   Wait for the agent to complete before continuing.

   ---

   **`--parallel` mode:** Use the parallel plan to dispatch multiple agents across file boundaries.

   a. **Locate analysis files**: Use `basename` on the repo path to get the repo name. Look for these files at `$CLAUDE_PROJECT_DIR/analysis/<repo-name>/`:
      - `parallel-plan.md`
      - `signatures.md`

      If either is missing, run `/build-signatures` on the repo path from step 2, then re-read the files.

   b. **Read both files completely.** From `parallel-plan.md` extract work units and execution phases. From `signatures.md` extract full signature details for each boundary.

   c. **Dispatch agents by phase**: For each phase in `parallel-plan.md`, construct a prompt per work unit and launch all units in the phase simultaneously using multiple Task tool calls (`subagent_type: "general-purpose"`). Wait for all agents in a phase to complete before starting the next. After each phase, briefly summarize what each agent did.

      **Agent prompt template** (fill in per work unit):
      ```
      You are implementing part of a feature. Work ONLY in the worktree at [worktree-path].

      ## Ticket
      **[ticket title]**
      [ticket description]

      ## Your File Scope
      You may ONLY create or modify these files:
      [list files from the work unit]

      Do NOT modify files outside this list. If you need a change elsewhere, note it in your report but do not make it.

      ## Signatures You Must Honor
      [For each consumed signature: symbol, kind, source file, full signature text from signatures.md]
      (If none: "No external dependencies — this unit is independent.")

      ## Signatures You Must Implement
      [For each exposed signature: symbol, kind, file, required signature text from signatures.md]
      (If none: "No dependents — implement freely.")

      ## Instructions
      1. Read each file in your scope to understand the current state
      2. Implement the parts of the ticket that apply to your files
      3. Create files if they don't exist yet
      4. Maintain all exposed signatures exactly as specified
      5. Follow the existing code style
      6. Report: which files you modified/created and any issues encountered
      ```

   d. **Reconcile**: After all phases complete, for each signature boundary in `signatures.md`: verify the export exists with the correct name/kind, the consumer imports it correctly, and types align. Fix missing imports, wrong paths, and minor type mismatches. Flag anything that can't be auto-fixed as **requires manual attention**.

   e. **Run tests**:
      - `bun.lockb` → `bun test`
      - `pnpm-lock.yaml` → `pnpm test`
      - `go.mod` → `go test ./...`
      - `package.json` with test script → `npm test`
      - None detected → skip

      Fix failures and re-run once. Report remaining failures if still failing.

7. **Commit changes**:
   ```
   git -C <worktree-path> add -A
   git -C <worktree-path> commit -m "<ticket-id>: <ticket-title>"
   ```
   If the commit is blocked by the pre-commit sync hook due to merge conflicts, stop and report the conflicting files.

8. **Sync with main**: `$CLAUDE_PROJECT_DIR/.claude/scripts/sync-main.sh <worktree-path>`
   - If conflicts occur, stop and report them.

9. **Verify sync**: `$CLAUDE_PROJECT_DIR/.claude/scripts/verify-sync.sh <worktree-path>`
   - If verification fails, stop and report the issue.

10. **Push the branch**:
    ```
    git -C <worktree-path> push -u origin $(git -C <worktree-path> branch --show-current)
    ```

11. **Check for an existing PR**: `gh pr list --head $(git -C <worktree-path> branch --show-current) --repo <owner>/<repo>`
    - If a PR already exists, report the URL and skip to step 13.

12. **Create PR**: `gh pr create --fill --base main` from the worktree directory.
    - Capture the PR URL from the output.

13. **Final report**:
    ```
    ## Done

    **Ticket:** [title] ([ticket-url])
    **PR:** [pr-url]

    ### Changes
    [Agent's summary of files changed and what was done]

    ### Test Results
    [Pass/fail summary, or "no test suite detected"]

    ### Issues
    [Any failures or items requiring manual attention — or "None"]
    ```
