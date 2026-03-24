Implement a feature in parallel using the work plan from `/build-signatures`.

**Important:** All script paths and analysis file paths must use `$CLAUDE_PROJECT_DIR` as the root. Do NOT use relative paths — you may be running from inside a worktree.

Given arguments `$ARGUMENTS` (format: `<worktree-path> <ticket-url>`):

1. **Parse arguments**: Split into `<worktree-path>` (first argument) and `<ticket-url>` (second argument). If either is missing, tell the user both are required. Resolve `<worktree-path>` to an absolute path.

2. **Fetch ticket details**: Parse the ticket URL to detect the platform and fetch the ticket:
   - `github.com/<owner>/<repo>/issues/<number>` → Run `gh issue view <number> --repo <owner>/<repo>`
   - `linear.app/*/issue/<team>-<number>/*` → Extract the issue ID. Run `linear issue show <id>`
   - `*.atlassian.net/browse/<key>` → Extract the issue key. Run `jira issue view <key>`
   - If the URL doesn't match any pattern, tell the user the format is not recognized.
   - Save the ticket title and description for use in agent prompts.

3. **Locate analysis files**: Determine the repo name from the worktree:
   ```
   git -C <worktree-path> rev-parse --show-toplevel
   ```
   Use `basename` on the result to get the repo name. Look for these files at `$CLAUDE_PROJECT_DIR/analysis/<repo-name>/`:
   - `parallel-plan.md`
   - `signatures.md`

   If either file is missing, run `/build-signatures` on the repository first (determine the repo path from the worktree's git config), then re-read the files.

4. **Read the parallel plan and signatures**: Read both files completely.
   - From `parallel-plan.md`, extract: the list of work units (with their file lists, exposed signatures, and consumed signatures) and the execution phases.
   - From `signatures.md`, extract: the full signature details for each boundary (symbol name, kind, direction, full signature text).

5. **Dispatch agents by phase**: For each execution phase listed in `parallel-plan.md`:

   Construct a prompt for each work unit in the phase using this template:

   ---
   **Agent prompt template** (fill in the bracketed sections per work unit):

   ```
   You are implementing part of a feature. Work ONLY in the worktree at [worktree-path].

   ## Ticket
   **[ticket title]**
   [ticket description]

   ## Your File Scope
   You may ONLY create or modify these files:
   [list each file from the work unit's "Files" section]

   Do NOT modify any files outside this list. If you need a change in another file, note it in your report but do not make the change.

   ## Signatures You Must Honor
   These interfaces are provided by other work units. Program against them as-is — do NOT change these signatures. They will exist when the code integrates.

   [For each entry in the work unit's "Consumes" table, include the full signature from signatures.md:
   - Symbol: [name]
   - Kind: [function/type/interface/class/constant]
   - From: [source file]
   - Signature: [full signature text from signatures.md]]

   (If the work unit consumes nothing, write: "No external dependencies — this unit is independent.")

   ## Signatures You Must Implement
   Other work units depend on these interfaces from your files. You MUST implement or maintain them exactly as specified.

   [For each entry in the work unit's "Exposes" table, include the full signature from signatures.md:
   - Symbol: [name]
   - Kind: [function/type/interface/class/constant]
   - In file: [file path]
   - Required signature: [full signature text from signatures.md]]

   (If the work unit exposes nothing, write: "No dependents — implement freely.")

   ## Instructions
   1. Read each file in your scope to understand the current state
   2. Implement the parts of the ticket that apply to your files
   3. If a file doesn't exist yet, create it
   4. Maintain all exposed signatures exactly as specified
   5. Write clean, working code — follow the existing style in the codebase
   6. When done, report: which files you modified/created and any issues encountered
   ```
   ---

   Launch ALL work units in the current phase simultaneously — use multiple Task tool calls in a single message with `subagent_type: "general-purpose"`. This gives true parallel execution.

   **Wait for all agents in the phase to complete before starting the next phase.** This is critical — later phases depend on interfaces written by earlier phases.

   After each phase completes, briefly summarize what each agent did before proceeding to the next phase.

   If the plan has no explicit phases section, treat all work units as a single phase (fully parallel).

6. **Run tests**: After all phases complete, detect and run the test suite from the worktree:
   - If `bun.lockb` exists → `bun test`
   - If `pnpm-lock.yaml` exists → `pnpm test`
   - If `go.mod` exists → `go test ./...`
   - If `package.json` exists with a `test` script → `npm test`
   - If none detected → skip, note "no test suite detected"

7. **Report results**: Summarize the parallel build:

   ```
   ## Parallel Build Complete

   **Ticket:** [title] ([url])
   **Worktree:** [path]
   **Phases completed:** [N]
   **Agents spawned:** [total count]

   ### Per-Agent Summary
   | Work Unit | Files Modified | Status |
   |-----------|---------------|--------|
   | WU-1      | [list]        | [status] |
   | WU-2      | [list]        | [status] |

   ### Issues
   [Any contract violations, agent errors, or files modified by multiple agents]

   ### Test Results
   [Test output or "no test suite detected"]
   ```

   If any agent reported issues with signatures it couldn't implement, flag these as **contract violations** requiring manual attention.