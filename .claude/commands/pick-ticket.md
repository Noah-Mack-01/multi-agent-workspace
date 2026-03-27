Pick up a ticket by URL and create a worktree for it in the specified repository.

**Usage:** `/pick-ticket <repo-url> <ticket-url>`

| Argument | Required | Description |
|----------|----------|-------------|
| `repo-url` | yes | GitHub HTTPS URL of the repository (e.g. `https://github.com/owner/repo`) |
| `ticket-url` | yes | URL of the ticket to work on — GitHub Issue, Linear, or Jira (see step 3 for accepted formats) |

**Important:** All script paths must use `$CLAUDE_PROJECT_DIR` as the root. Do NOT use relative paths — you may be running from inside a worktree.

Given arguments `$ARGUMENTS` (format: `<repo-url> <ticket-url>`):

1. **Parse arguments**: Split into `<repo-url>` (first argument) and `<ticket-url>` (second argument). If either is missing, stop and tell the user: "Usage: `/pick-ticket <repo-url> <ticket-url>` — both arguments are required. `repo-url` is the GitHub HTTPS clone URL; `ticket-url` is a GitHub Issue, Linear, or Jira ticket URL."

2. **Clone or fetch the repository**: Run `$CLAUDE_PROJECT_DIR/.claude/scripts/clone-repo.sh <repo-url>`
   - Capture the output to get the absolute repo path (last line of output).

3. **Parse the ticket URL to detect platform and extract identifier**:
   - `github.com/<owner>/<repo>/issues/<number>` -> GitHub Issue. Run `gh issue view <number> --repo <owner>/<repo>`
   - `linear.app/*/issue/<team>-<number>/*` -> Linear. Extract the issue ID (e.g., `ENG-123`). Run `linear issue show <id>`
   - `*.atlassian.net/browse/<key>` -> Jira. Extract the issue key (e.g., `PROJ-123`). Run `jira issue view <key>`
   - If the URL doesn't match any known pattern, tell the user the format is not recognized and ask them to provide a GitHub, Linear, or Jira ticket URL.

4. **Derive branch name** from the ticket, using a platform prefix so the source is unambiguous:
   - GitHub Issue → `feature/gh-<number>-<slug>` (e.g., `feature/gh-42-add-auth`)
   - Linear → `feature/linear-<team>-<number>-<slug>` (e.g., `feature/linear-ENG-123-user-login`)
   - Jira → `feature/jira-<key>-<slug>` (e.g., `feature/jira-PROJ-123-fix-thing`)
   - Slugify the ticket title: lowercase, replace spaces with hyphens, strip special characters, max 40 chars for the slug portion.

5. **Create worktree**: `$CLAUDE_PROJECT_DIR/.claude/scripts/create-worktree.sh <repo-path> <branch-name>`

6. **Report** the ticket summary, repository name, and worktree path so work can begin.
