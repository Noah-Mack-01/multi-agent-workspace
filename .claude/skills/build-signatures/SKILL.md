---
name: build-signatures
description: Build interface signatures for coupled files to enable parallel work
argument-hint: <repo-path>
allowed-tools: Bash($CLAUDE_PROJECT_DIR/.claude/scripts/ensure-analysis.sh *), Bash(git show *), Bash(git -C * rev-parse --short HEAD)
---

Build interface signatures for the repository at `$ARGUMENTS`.

All scripts must be called using their absolute path: `$CLAUDE_PROJECT_DIR/.claude/scripts/<script>`. The `analysis/` output directory is at `$CLAUDE_PROJECT_DIR/analysis/`.

**Step 1: Ensure coupling data exists**

Run: `$CLAUDE_PROJECT_DIR/.claude/scripts/ensure-analysis.sh $ARGUMENTS`

Capture the stdout output — it is the absolute path to the data directory containing structured coupling files.

**Step 2: Read coupling data**

Read these tab-delimited files from the data directory:
- `import_edges.txt` — `source<TAB>target` (static import dependencies between files)
- `cochange_pairs.txt` — `fileA<TAB>fileB<TAB>count` (files that change together in commits, sorted by count descending)
- `cross_group_coupling.txt` — `groupA<TAB>groupB<TAB>imports<TAB>cochanges<TAB>score` (aggregate coupling between directory groups)
- `file_groups.txt` — `file<TAB>group` (which group each file belongs to)

**Step 3: Identify top coupled pairs**

From `import_edges.txt` and `cochange_pairs.txt`, identify the file pairs with the strongest coupling. Score each pair as: `imports × 1.0 + cochanges × 0.5`. Focus on the top 15–20 pairs. These are the signature boundaries.

**Step 4: Read source code of coupled files**

For each unique file in the top coupled pairs, read its source code. Use `git show HEAD:<filepath>` run from the repo path (this works on both bare repos and worktrees). If a file cannot be read, note it and skip.

**Step 5: Identify boundary signatures**

For each coupled pair (A, B), examine the source code and determine:
- What does A export that B imports or references?
- What does B export that A imports or references?

For each boundary symbol, record:
- **Symbol name** (e.g., `createUser`, `ConfigType`)
- **Kind** (function, type, interface, class, constant, enum)
- **Direction** (A → B meaning A exports it and B consumes it, or B → A, or both)
- **Signature** (the full function signature, type definition, or constant declaration)

If a coupled pair shares no exported symbols (they only co-change together), flag it as "co-change coupled, no shared interface" and list it separately.

**Step 6: Group into work units**

Using the coupling graph from Step 3:
- Files connected by signature boundaries (from Step 5) should be placed in the same work unit, or in adjacent units with their interface contract explicitly documented.
- Files with no coupling to any other file are independent — each can be its own parallel work unit.
- If there are circular dependencies between work units, flag them and recommend which edge to break (prefer breaking the direction with fewer dependents).
- Label work units as WU-1, WU-2, etc., sorted by file count descending.
- Determine a phased execution order: Phase 1 = units with no incoming dependencies, Phase 2 = units depending only on Phase 1, etc.

**Step 7: Write output**

Get the repo's short commit hash: `git -C <repo-path> rev-parse --short HEAD`

Write two files to the data directory (same directory from Step 1):

**`signatures.md`** with these sections:
- Header: repo name, commit hash, number of coupled pairs analyzed, number of boundary signatures found
- **Boundaries**: For each coupled pair, a subsection with a table of boundary symbols (Symbol, Kind, Direction, Signature)
- **Co-Change Only**: Table of pairs with no shared interface (File A, File B, Co-changes)

**`parallel-plan.md`** with these sections:
- Header: repo name, commit hash, total work units count
- **Work Units**: For each unit — label, files list, "Exposes" table (symbols other units depend on), "Consumes" table (symbols this unit needs from others)
- **Dependency Graph**: Mermaid `graph LR` showing inter-unit dependencies labeled with symbol names
- **Execution Phases**: Numbered phases showing which units can run in parallel at each stage
- **Circular Dependencies**: Table of cycles with break recommendations (if any)

Report the output file locations and key findings: how many signature boundaries, how many parallel work units, and suggested execution phases.
