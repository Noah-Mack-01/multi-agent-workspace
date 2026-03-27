#!/bin/bash
# test-workflow.sh - Automated tests for all workflow scripts
# Usage: test-workflow.sh
#
# Creates temporary git repos, exercises every script, and reports results.
# Cleans up after itself.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

# Override WORKSPACE_ROOT so clone-repo.sh and others use the test directory
export WORKSPACE_ROOT="$TEST_DIR"

cleanup() {
  echo ""
  echo "Cleaning up $TEST_DIR..."
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

echo "=== Multi-Agent Worktree Workflow Tests ==="
echo "Test directory: $TEST_DIR"
echo ""

# ---------- Setup: create a "remote" repo and a "local" clone ----------

echo "--- Setup: Creating test repositories ---"

# Create bare remote repo
REMOTE_DIR="$TEST_DIR/remote.git"
git init --bare "$REMOTE_DIR" >/dev/null 2>&1

# Create local clone (simulates a repo in repositories/)
LOCAL_DIR="$TEST_DIR/local"
git clone "$REMOTE_DIR" "$LOCAL_DIR" >/dev/null 2>&1
cd "$LOCAL_DIR"

# Configure git for test commits
git config user.email "test@test.com"
git config user.name "Test User"

# Create initial commit on main
echo "initial" > README.md
git add README.md
git commit -m "Initial commit" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

echo "Setup complete."
echo ""

# ---------- Test 0: clone-repo.sh ----------

echo "--- Test 0: clone-repo.sh ---"

# Test: clone a repo by file:// URL
CLONE_URL="file://$REMOTE_DIR"
CLONE_OUTPUT=$("$SCRIPT_DIR/clone-repo.sh" "$CLONE_URL" 2>&1)
CLONE_EXIT=$?
if [ $CLONE_EXIT -eq 0 ]; then
  EXPECTED_PATH="$TEST_DIR/repositories/remote.git"
  if [ -d "$EXPECTED_PATH" ] && git -C "$EXPECTED_PATH" rev-parse --git-dir &>/dev/null; then
    pass "Bare-cloned repo to repositories/remote.git"
  else
    fail "Clone directory not found at $EXPECTED_PATH"
  fi
else
  fail "clone-repo.sh failed: $CLONE_OUTPUT"
fi

# Test: idempotent re-clone should fetch
CLONE_OUTPUT_2=$("$SCRIPT_DIR/clone-repo.sh" "$CLONE_URL" 2>&1)
if echo "$CLONE_OUTPUT_2" | grep -q "already exists"; then
  pass "Idempotent re-clone fetches instead of cloning"
else
  fail "Re-clone did not detect existing repo: $CLONE_OUTPUT_2"
fi

# Test: invalid URL should fail
if "$SCRIPT_DIR/clone-repo.sh" "not-a-url" >/dev/null 2>&1; then
  fail "Should have rejected invalid URL"
else
  pass "Correctly rejected invalid URL"
fi

echo ""

# ---------- Test 1: create-worktree.sh ----------

echo "--- Test 1: create-worktree.sh ---"

WORKTREES_DIR="$TEST_DIR/worktrees"

# Test: create worktree for new branch
if "$SCRIPT_DIR/create-worktree.sh" "$LOCAL_DIR" "feature/test-1" "$WORKTREES_DIR" >/dev/null 2>&1; then
  if [ -d "$WORKTREES_DIR/feature/test-1" ]; then
    pass "Created worktree directory"
  else
    fail "Worktree directory not found"
  fi

  # Verify branch exists
  BRANCH=$(cd "$WORKTREES_DIR/feature/test-1" && git branch --show-current)
  if [ "$BRANCH" = "feature/test-1" ]; then
    pass "Correct branch checked out"
  else
    fail "Expected branch 'feature/test-1', got '$BRANCH'"
  fi
else
  fail "create-worktree.sh exited with error"
fi

# Test: duplicate branch should fail
if "$SCRIPT_DIR/create-worktree.sh" "$LOCAL_DIR" "feature/test-1" "$WORKTREES_DIR" >/dev/null 2>&1; then
  fail "Should have failed for duplicate branch"
else
  pass "Correctly rejected duplicate branch"
fi

echo ""

# ---------- Test 2: list-worktrees.sh ----------

echo "--- Test 2: list-worktrees.sh ---"

OUTPUT=$("$SCRIPT_DIR/list-worktrees.sh" "$LOCAL_DIR" 2>&1)
if echo "$OUTPUT" | grep -q "feature/test-1"; then
  pass "Listed worktree with correct branch"
else
  fail "Did not list feature/test-1 worktree"
fi

echo ""

# ---------- Test 3: sync-main.sh (already synced) ----------

echo "--- Test 3: sync-main.sh (already synced) ---"

WT_PATH="$WORKTREES_DIR/feature/test-1"

OUTPUT=$("$SCRIPT_DIR/sync-main.sh" "$WT_PATH" 2>&1)
if echo "$OUTPUT" | grep -q "already synchronized"; then
  pass "Correctly detected branch is synced"
else
  fail "Did not detect synced state: $OUTPUT"
fi

echo ""

# ---------- Test 4: sync-main.sh (main ahead) ----------

echo "--- Test 4: sync-main.sh (main is ahead) ---"

# Make a commit on main in the local repo
cd "$LOCAL_DIR"
echo "new change on main" >> README.md
git add README.md
git commit -m "Advance main" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

# Now sync from the worktree
cd "$WT_PATH"
OUTPUT=$("$SCRIPT_DIR/sync-main.sh" "$WT_PATH" 2>&1)
if echo "$OUTPUT" | grep -q "Successfully integrated"; then
  pass "Merged main into feature branch"
else
  fail "Did not merge main: $OUTPUT"
fi

echo ""

# ---------- Test 5: verify-sync.sh (synced) ----------

echo "--- Test 5: verify-sync.sh (synced) ---"

OUTPUT=$("$SCRIPT_DIR/verify-sync.sh" "$WT_PATH" 2>&1)
if echo "$OUTPUT" | grep -q "safe to push"; then
  pass "Verified branch is synced"
else
  fail "Did not verify sync: $OUTPUT"
fi

echo ""

# ---------- Test 6: verify-sync.sh (not synced) ----------

echo "--- Test 6: verify-sync.sh (not synced) ---"

# Advance main again
cd "$LOCAL_DIR"
echo "another change" >> README.md
git add README.md
git commit -m "Advance main again" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

cd "$WT_PATH"
if "$SCRIPT_DIR/verify-sync.sh" "$WT_PATH" >/dev/null 2>&1; then
  fail "Should have detected out-of-sync state"
else
  pass "Correctly detected branch is not synced"
fi

echo ""

# ---------- Test 7: sync-main.sh (merge conflict) ----------

echo "--- Test 7: sync-main.sh (merge conflict) ---"

# Create conflicting change in worktree
cd "$WT_PATH"
echo "worktree version" > conflict.txt
git add conflict.txt
git commit -m "Add conflict file in worktree" >/dev/null 2>&1

# Create conflicting change on main
cd "$LOCAL_DIR"
echo "main version" > conflict.txt
git add conflict.txt
git commit -m "Add conflict file on main" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

cd "$WT_PATH"
if "$SCRIPT_DIR/sync-main.sh" "$WT_PATH" >/dev/null 2>&1; then
  fail "Should have detected merge conflict"
else
  pass "Correctly detected and aborted merge conflict"
fi

# Verify worktree is clean after abort (no conflict markers left)
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" = "0" ]; then
  pass "Worktree is clean after conflict abort"
else
  fail "Worktree is dirty after conflict abort ($DIRTY files)"
fi

echo ""

# ---------- Test 8: sync-main.sh (skip on main branch) ----------

echo "--- Test 8: sync-main.sh (skip on main branch) ---"

cd "$LOCAL_DIR"
OUTPUT=$("$SCRIPT_DIR/sync-main.sh" "$LOCAL_DIR" 2>&1)
if echo "$OUTPUT" | grep -q "skipping sync"; then
  pass "Skipped sync on main branch"
else
  fail "Did not skip sync on main: $OUTPUT"
fi

echo ""

# ---------- Test 9: remove-worktree.sh (dirty state) ----------

echo "--- Test 9: remove-worktree.sh (dirty state) ---"

cd "$WT_PATH"
echo "uncommitted" > dirty.txt
git add dirty.txt

cd "$TEST_DIR"
if "$SCRIPT_DIR/remove-worktree.sh" "$WT_PATH" >/dev/null 2>&1; then
  fail "Should have refused to remove dirty worktree"
else
  pass "Correctly refused to remove dirty worktree"
fi

echo ""

# ---------- Test 10: remove-worktree.sh (force) ----------

echo "--- Test 10: remove-worktree.sh (force remove) ---"

cd "$TEST_DIR"
if "$SCRIPT_DIR/remove-worktree.sh" "$WT_PATH" --force >/dev/null 2>&1; then
  if [ ! -d "$WT_PATH" ]; then
    pass "Force-removed dirty worktree"
  else
    fail "Worktree directory still exists after force remove"
  fi
else
  fail "Force remove failed"
fi

echo ""

# ---------- Test 11: remove-worktree.sh (clean state) ----------

echo "--- Test 11: remove-worktree.sh (clean remove) ---"

"$SCRIPT_DIR/create-worktree.sh" "$LOCAL_DIR" "feature/test-clean" "$WORKTREES_DIR" >/dev/null 2>&1
CLEAN_WT="$WORKTREES_DIR/feature/test-clean"

cd "$TEST_DIR"
if "$SCRIPT_DIR/remove-worktree.sh" "$CLEAN_WT" >/dev/null 2>&1; then
  if [ ! -d "$CLEAN_WT" ]; then
    pass "Cleanly removed worktree"
  else
    fail "Worktree directory still exists after clean remove"
  fi
else
  fail "Clean remove failed"
fi

echo ""

# ---------- Test 12: init-worktree.sh (no lockfile) ----------

echo "--- Test 12: init-worktree.sh (no lockfile - should warn) ---"

"$SCRIPT_DIR/create-worktree.sh" "$LOCAL_DIR" "feature/test-nolockfile" "$WORKTREES_DIR" >/dev/null 2>&1
NL_WT="$WORKTREES_DIR/feature/test-nolockfile"

OUTPUT=$("$SCRIPT_DIR/init-worktree.sh" "$NL_WT" 2>&1)
if echo "$OUTPUT" | grep -q "No supported lockfile"; then
  pass "Warned about missing lockfile"
else
  fail "Did not warn about missing lockfile: $OUTPUT"
fi

# Cleanup
cd "$TEST_DIR"
"$SCRIPT_DIR/remove-worktree.sh" "$NL_WT" >/dev/null 2>&1

echo ""

# ---------- Test 13: analyze-repo.sh (data persistence) ----------

echo "--- Test 13: analyze-repo.sh (data persistence) ---"

# Create a repo with source files and import edges for analysis
ANALYZE_REMOTE="$TEST_DIR/analyze-remote.git"
git init --bare "$ANALYZE_REMOTE" >/dev/null 2>&1

ANALYZE_LOCAL="$TEST_DIR/analyze-local"
git clone "$ANALYZE_REMOTE" "$ANALYZE_LOCAL" >/dev/null 2>&1
cd "$ANALYZE_LOCAL"
git config user.email "test@test.com"
git config user.name "Test User"

mkdir -p src
echo 'export function greet(name) { return "hello " + name; }' > src/greet.js
echo 'import { greet } from "./greet"; console.log(greet("world"));' > src/main.js
git add -A
git commit -m "Add source files" >/dev/null 2>&1

echo 'export function farewell(name) { return "bye " + name; }' > src/farewell.js
echo 'import { greet } from "./greet"; import { farewell } from "./farewell";' > src/main.js
git add -A
git commit -m "Add farewell" >/dev/null 2>&1

ANALYSIS_DIR="$TEST_DIR/analysis"

"$SCRIPT_DIR/analyze-repo.sh" "$ANALYZE_LOCAL" "$ANALYSIS_DIR" >/dev/null 2>&1
ANALYZE_EXIT=$?

REPO_NAME="$(basename "$ANALYZE_LOCAL")"
DATA_DIR="$ANALYSIS_DIR/$REPO_NAME"

if [ $ANALYZE_EXIT -eq 0 ]; then
  pass "analyze-repo.sh ran successfully"
else
  fail "analyze-repo.sh failed with exit code $ANALYZE_EXIT"
fi

# Verify markdown report exists (backward compatibility)
if [ -f "$ANALYSIS_DIR/$REPO_NAME.md" ]; then
  pass "Markdown report exists at analysis/<repo-name>.md"
else
  fail "Markdown report missing at $ANALYSIS_DIR/$REPO_NAME.md"
fi

# Verify data files are persisted
if [ -f "$DATA_DIR/import_edges.txt" ]; then
  pass "import_edges.txt persisted"
else
  fail "import_edges.txt not found in $DATA_DIR"
fi

if [ -f "$DATA_DIR/cochange_pairs.txt" ]; then
  pass "cochange_pairs.txt persisted"
else
  fail "cochange_pairs.txt not found in $DATA_DIR"
fi

if [ -f "$DATA_DIR/file_groups.txt" ]; then
  pass "file_groups.txt persisted"
else
  fail "file_groups.txt not found in $DATA_DIR"
fi

# Verify idempotency (run again, check files are overwritten not appended)
EDGES_SIZE_BEFORE=$(wc -c < "$DATA_DIR/import_edges.txt" | tr -d ' ')
"$SCRIPT_DIR/analyze-repo.sh" "$ANALYZE_LOCAL" "$ANALYSIS_DIR" >/dev/null 2>&1
EDGES_SIZE_AFTER=$(wc -c < "$DATA_DIR/import_edges.txt" | tr -d ' ')

if [ "$EDGES_SIZE_BEFORE" = "$EDGES_SIZE_AFTER" ]; then
  pass "Data files are overwritten (not appended) on re-run"
else
  fail "Data file size changed on re-run ($EDGES_SIZE_BEFORE -> $EDGES_SIZE_AFTER)"
fi

echo ""

# ---------- Test 14: ensure-analysis.sh ----------

echo "--- Test 14: ensure-analysis.sh ---"

# Test: with existing data, should NOT re-run analysis (just output path)
ENSURE_OUTPUT=$("$SCRIPT_DIR/ensure-analysis.sh" "$ANALYZE_LOCAL" "$ANALYSIS_DIR" 2>/dev/null)
if [ "$ENSURE_OUTPUT" = "$DATA_DIR" ]; then
  pass "Outputs correct data directory path"
else
  fail "Expected '$DATA_DIR', got '$ENSURE_OUTPUT'"
fi

# Test: with existing data, should not re-run analysis (check stderr is empty)
ENSURE_STDERR=$("$SCRIPT_DIR/ensure-analysis.sh" "$ANALYZE_LOCAL" "$ANALYSIS_DIR" 2>&1 >/dev/null)
if echo "$ENSURE_STDERR" | grep -q "Running analysis"; then
  fail "Re-ran analysis when data already exists"
else
  pass "Skipped analysis when data already exists"
fi

# Test: with missing data, should run analysis
rm -rf "$DATA_DIR"
ENSURE_STDERR=$("$SCRIPT_DIR/ensure-analysis.sh" "$ANALYZE_LOCAL" "$ANALYSIS_DIR" 2>&1 >/dev/null)
if echo "$ENSURE_STDERR" | grep -q "Running analysis"; then
  if [ -f "$DATA_DIR/import_edges.txt" ]; then
    pass "Ran analysis when data was missing and produced data files"
  else
    fail "Ran analysis but data files not produced"
  fi
else
  fail "Did not run analysis when data was missing"
fi

# Test: invalid repo path should fail
if "$SCRIPT_DIR/ensure-analysis.sh" "$TEST_DIR/nonexistent" >/dev/null 2>&1; then
  fail "Should have failed for nonexistent path"
else
  pass "Correctly failed for nonexistent path"
fi

# Test: non-repo path should fail
if "$SCRIPT_DIR/ensure-analysis.sh" "$TEST_DIR" >/dev/null 2>&1; then
  fail "Should have failed for non-repo path"
else
  pass "Correctly failed for non-repo path"
fi

echo ""

# ---------- Submodule Fixture Helper ----------

# create_submodule_fixture <workspace-dir>
# Creates:
#   <workspace-dir>/sub-remote.git    — bare submodule repo with one .ts file
#   <workspace-dir>/parent-remote.git — bare parent repo with .gitmodules + gitlink
# Sets globals: SUB_REMOTE_DIR, PARENT_REMOTE_DIR, SUB_HEAD_SHA
create_submodule_fixture() {
  local ws="$1"

  # --- Submodule repo ---
  SUB_REMOTE_DIR="$ws/sub-remote.git"
  local sub_work="$ws/sub-work"
  git init "$sub_work" >/dev/null 2>&1
  cd "$sub_work"
  git config user.email "test@test.com"
  git config user.name "Test User"
  mkdir -p src
  echo 'export function hello(): string { return "hi"; }' > src/index.ts
  git add .
  git commit -m "submodule initial" >/dev/null 2>&1
  git clone --bare "$sub_work" "$SUB_REMOTE_DIR" >/dev/null 2>&1
  SUB_HEAD_SHA=$(git -C "$SUB_REMOTE_DIR" rev-parse HEAD)

  # --- Parent repo ---
  PARENT_REMOTE_DIR="$ws/parent-remote.git"
  local parent_work="$ws/parent-work"
  git init "$parent_work" >/dev/null 2>&1
  cd "$parent_work"
  git config user.email "test@test.com"
  git config user.name "Test User"

  # Write .gitmodules
  cat > .gitmodules <<EOF
[submodule "sub-lib"]
	path = libs/sub
	url = file://$SUB_REMOTE_DIR
EOF

  # Add gitlink entry (manually stage the submodule pointer)
  mkdir -p libs/sub
  git -C "$parent_work" update-index --add --cacheinfo "160000,$SUB_HEAD_SHA,libs/sub"

  git add .gitmodules
  git commit -m "parent initial with submodule" >/dev/null 2>&1
  git clone --bare "$parent_work" "$PARENT_REMOTE_DIR" >/dev/null 2>&1

  cd "$ws"
}

# ---------- Test 15: clone-repo.sh submodule registration ----------

echo "--- Test 15: clone-repo.sh submodule registration ---"

SUB_WS="$TEST_DIR/submodule-tests"
mkdir -p "$SUB_WS"
create_submodule_fixture "$SUB_WS"

PARENT_URL="file://$PARENT_REMOTE_DIR"
CLONE_OUT=$("$SCRIPT_DIR/clone-repo.sh" "$PARENT_URL" 2>&1)
CLONE_EC=$?

if [ $CLONE_EC -eq 0 ]; then
  pass "clone-repo.sh succeeded with submodule parent"
else
  fail "clone-repo.sh failed: $CLONE_OUT"
fi

# Submodule bare repo should be registered
EXPECTED_SUB_BARE="$TEST_DIR/repositories/sub-remote.git"
if [ -d "$EXPECTED_SUB_BARE" ] && git -C "$EXPECTED_SUB_BARE" rev-parse --git-dir &>/dev/null; then
  pass "Submodule bare repo created at repositories/sub-remote.git"
else
  fail "Submodule bare repo not found at $EXPECTED_SUB_BARE"
fi

# Registry file should exist
PARENT_REGISTRY="$TEST_DIR/repositories/parent-remote.submodules"
if [ -f "$PARENT_REGISTRY" ]; then
  pass "Submodule registry file created"
else
  fail "Submodule registry file not found at $PARENT_REGISTRY"
fi

# Registry should contain correct sub-lib entry
if grep -q "sub-lib" "$PARENT_REGISTRY" && grep -q "libs/sub" "$PARENT_REGISTRY"; then
  pass "Registry contains correct submodule name and declared path"
else
  fail "Registry content unexpected: $(cat "$PARENT_REGISTRY" 2>/dev/null)"
fi

# Idempotent re-run should regenerate registry without error
RECLONE_OUT=$("$SCRIPT_DIR/clone-repo.sh" "$PARENT_URL" 2>&1)
if [ $? -eq 0 ] && [ -f "$PARENT_REGISTRY" ]; then
  pass "Idempotent re-clone regenerates registry"
else
  fail "Idempotent re-clone failed: $RECLONE_OUT"
fi

# Repo with no .gitmodules should produce no registry
NO_SUB_URL="file://$TEST_DIR/remote.git"
"$SCRIPT_DIR/clone-repo.sh" "$NO_SUB_URL" >/dev/null 2>&1 || true
NO_SUB_REGISTRY="$TEST_DIR/repositories/remote.submodules"
if [ ! -f "$NO_SUB_REGISTRY" ]; then
  pass "No registry file for repo without submodules"
else
  fail "Unexpected registry file created for repo without submodules"
fi

echo ""

# ---------- Test 16: create-worktree.sh submodule worktree ----------

echo "--- Test 16: create-worktree.sh submodule worktree ---"

PARENT_BARE="$TEST_DIR/repositories/parent-remote.git"
SUB_WT_DIR="$TEST_DIR/subworktrees"

if "$SCRIPT_DIR/create-worktree.sh" "$PARENT_BARE" "feature/sub-test" "$SUB_WT_DIR" >/dev/null 2>&1; then
  PARENT_WT="$SUB_WT_DIR/feature/sub-test"

  if [ -d "$PARENT_WT" ]; then
    pass "Parent worktree created"
  else
    fail "Parent worktree directory not found"
  fi

  SUB_WT="$PARENT_WT/libs/sub"
  if [ -d "$SUB_WT" ] && [ -n "$(ls -A "$SUB_WT" 2>/dev/null)" ]; then
    pass "Submodule worktree created inside parent worktree"
  else
    fail "Submodule worktree not found at $SUB_WT"
  fi

  ACTUAL_SHA=$(git -C "$SUB_WT" rev-parse HEAD 2>/dev/null || echo "")
  if [ "$ACTUAL_SHA" = "$SUB_HEAD_SHA" ]; then
    pass "Submodule worktree checked out at correct pointer SHA"
  else
    fail "Expected SHA $SUB_HEAD_SHA, got $ACTUAL_SHA"
  fi
else
  fail "create-worktree.sh failed for parent with submodule"
fi

echo ""

# ---------- Test 17: remove-worktree.sh removes submodule worktrees ----------

echo "--- Test 17: remove-worktree.sh removes submodule worktrees first ---"

PARENT_WT_17="$SUB_WT_DIR/feature/sub-test"
if [ -d "$PARENT_WT_17" ]; then
  SUB_BARE_17="$TEST_DIR/repositories/sub-remote.git"

  if "$SCRIPT_DIR/remove-worktree.sh" "$PARENT_WT_17" >/dev/null 2>&1; then
    if [ ! -d "$PARENT_WT_17" ]; then
      pass "Parent worktree directory removed"
    else
      fail "Parent worktree directory still exists"
    fi

    if ! git -C "$SUB_BARE_17" worktree list --porcelain 2>/dev/null | grep -qF "feature/sub-test"; then
      pass "Submodule worktree unregistered from bare repo"
    else
      fail "Submodule worktree still registered in bare repo"
    fi
  else
    fail "remove-worktree.sh failed for parent with submodule"
  fi
else
  fail "Prerequisite: parent worktree from test 16 not found"
fi

echo ""

# ---------- Test 18: analyze-repo.sh includes submodule files ----------

echo "--- Test 18: analyze-repo.sh includes submodule files ---"

# Create a fresh worktree with submodule initialized for analysis
ANALYZE_SUB_DIR="$TEST_DIR/analyze-subworktrees"
PARENT_BARE_18="$TEST_DIR/repositories/parent-remote.git"

if "$SCRIPT_DIR/create-worktree.sh" "$PARENT_BARE_18" "feature/analyze-sub" "$ANALYZE_SUB_DIR" >/dev/null 2>&1; then
  ANALYZE_WT="$ANALYZE_SUB_DIR/feature/analyze-sub"
  ANALYSIS_SUB_DIR="$TEST_DIR/analysis-sub"

  if "$SCRIPT_DIR/analyze-repo.sh" "$ANALYZE_WT" "$ANALYSIS_SUB_DIR" >/dev/null 2>&1; then
    DATA_SUB_DIR="$ANALYSIS_SUB_DIR/feature"  # basename of worktree is "feature" due to branch name
    # The repo name is derived from basename of the worktree path
    REPO_BASENAME=$(basename "$ANALYZE_WT")
    DATA_SUB_DIR="$ANALYSIS_SUB_DIR/$REPO_BASENAME"

    if [ -f "$DATA_SUB_DIR/file_groups.txt" ]; then
      pass "file_groups.txt produced for submodule-containing worktree"

      if grep -q "libs/sub" "$DATA_SUB_DIR/file_groups.txt"; then
        pass "Submodule files appear in file_groups.txt with submodule path prefix"
      else
        fail "Submodule files not found in file_groups.txt (content: $(cat "$DATA_SUB_DIR/file_groups.txt"))"
      fi
    else
      fail "file_groups.txt not produced at $DATA_SUB_DIR"
    fi
  else
    fail "analyze-repo.sh failed on submodule worktree"
  fi

  # Clean up this worktree
  "$SCRIPT_DIR/remove-worktree.sh" "$ANALYZE_WT" --force >/dev/null 2>&1 || true
else
  fail "create-worktree.sh failed creating worktree for analyze test"
fi

echo ""

# ---------- Summary ----------

echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
