#!/bin/bash
# analyze-repo.sh - Deterministic repository coupling analysis
# Usage: analyze-repo.sh <repo-path> [output-dir]
#
# Analyzes a git repository to produce a structured markdown report
# of file coupling, co-change history, and parallelization boundaries.
# Output: <output-dir>/<repo-name>.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configurable via environment
MAX_COMMITS="${ANALYZE_MAX_COMMITS:-500}"
MAX_FILES_PER_COMMIT="${ANALYZE_MAX_FILES_PER_COMMIT:-50}"
TOP_N="${ANALYZE_TOP_N:-50}"

# Globals set by functions
REPO_PATH=""
REPO_NAME=""
OUTPUT_DIR=""
OUTPUT_PATH=""
TMP_DIR=""
LANGUAGES=""
FRAMEWORKS=""
IS_MONOREPO=false
GO_MODULE=""
FILE_LIST=""
FILE_COUNT=0
IMPORT_EDGES=""
IMPORT_EDGE_COUNT=0
COCHANGE_PAIRS=""
COCHANGE_PAIR_COUNT=0
GROUP_MAP=""
GROUP_COUNT=0
CROSS_GROUP_COUPLING=""

# ---------- Helpers ----------

die() {
  echo "Error: $1" >&2
  exit 1
}

cleanup() {
  [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ---------- Argument Parsing ----------

parse_args() {
  if [ -z "$1" ]; then
    echo "Error: Repository path required"
    echo "Usage: analyze-repo.sh <repo-path> [output-dir]"
    exit 1
  fi

  REPO_PATH="$(cd "$1" && pwd -P)"
  REPO_NAME="$(basename "$REPO_PATH" .git)"
  OUTPUT_DIR="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)/analysis}"
  TMP_DIR=$(mktemp -d)
}

# ---------- Validation ----------

validate_repo() {
  [ -d "$REPO_PATH" ] || die "Directory does not exist: $REPO_PATH"
  git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository: $REPO_PATH"
  git -C "$REPO_PATH" rev-parse HEAD >/dev/null 2>&1 || die "Repository has no commits"
}

# ---------- Step 1: Language Detection ----------

detect_language() {
  LANGUAGES=""
  FRAMEWORKS=""
  IS_MONOREPO=false
  GO_MODULE=""

  # TypeScript
  if [ -f "$REPO_PATH/tsconfig.json" ]; then
    LANGUAGES="${LANGUAGES}TypeScript,"
  fi

  # JavaScript / framework detection
  if [ -f "$REPO_PATH/package.json" ]; then
    if [ -z "$LANGUAGES" ]; then LANGUAGES="${LANGUAGES}JavaScript,"; fi
    local deps=""
    deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$REPO_PATH/package.json" 2>/dev/null || true)
    if [ -n "$deps" ]; then
      echo "$deps" | grep -qx 'next' && FRAMEWORKS="${FRAMEWORKS}Next.js," || true
      echo "$deps" | grep -qx 'react' && FRAMEWORKS="${FRAMEWORKS}React," || true
      echo "$deps" | grep -qx 'express' && FRAMEWORKS="${FRAMEWORKS}Express," || true
      echo "$deps" | grep -qx '@angular/core' && FRAMEWORKS="${FRAMEWORKS}Angular," || true
      echo "$deps" | grep -qx 'vue' && FRAMEWORKS="${FRAMEWORKS}Vue," || true
      echo "$deps" | grep -qx 'svelte' && FRAMEWORKS="${FRAMEWORKS}Svelte," || true
    fi
  fi

  # Go
  if [ -f "$REPO_PATH/go.mod" ]; then
    LANGUAGES="${LANGUAGES}Go,"
    GO_MODULE=$(head -1 "$REPO_PATH/go.mod" | awk '{print $2}')
  fi

  # Monorepo detection
  if [ -d "$REPO_PATH/packages" ] || [ -d "$REPO_PATH/apps" ]; then
    IS_MONOREPO=true
  elif [ -f "$REPO_PATH/pnpm-workspace.yaml" ]; then
    IS_MONOREPO=true
  elif [ -f "$REPO_PATH/package.json" ] && jq -e '.workspaces' "$REPO_PATH/package.json" >/dev/null 2>&1; then
    IS_MONOREPO=true
  fi

  # Strip trailing commas
  LANGUAGES="${LANGUAGES%,}"
  FRAMEWORKS="${FRAMEWORKS%,}"
  if [ -z "$LANGUAGES" ]; then LANGUAGES="unknown"; fi
  if [ -z "$FRAMEWORKS" ]; then FRAMEWORKS="none"; fi
}

# ---------- Step 2: File Listing ----------

list_tracked_files() {
  git -C "$REPO_PATH" ls-files -- \
    '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' \
    '*.go' \
    ':!node_modules' ':!vendor' ':!dist' ':!build' ':!.next' ':!coverage' \
    ':!*.min.js' ':!*.min.css' ':!*.bundle.js' ':!*.chunk.js' \
    ':!*.generated.*' ':!*_generated.*' ':!*.pb.go' \
    2>/dev/null | sort > "$TMP_DIR/file_list.txt"

  FILE_LIST="$TMP_DIR/file_list.txt"
  FILE_COUNT=$(wc -l < "$FILE_LIST" | tr -d ' ')
}

# ---------- Step 3: Import Extraction ----------

resolve_relative_path() {
  local base_dir="$1"
  local rel_path="$2"
  local result="${base_dir}/${rel_path}"

  # Normalize ./ and ../
  # Remove leading ./
  result=$(echo "$result" | sed 's|/\./|/|g; s|^\./||')

  # Resolve ../ segments iteratively (up to 10 levels deep)
  local i=0
  while echo "$result" | grep -qE '[^/]+/\.\.' && [ $i -lt 10 ]; do
    result=$(echo "$result" | sed -E 's|[^/]+/\.\./||; s|[^/]+/\.\.$||')
    i=$((i + 1))
  done

  echo "$result"
}

find_actual_file() {
  local repo="$1"
  local base_path="$2"

  # Exact match
  [ -f "$repo/$base_path" ] && echo "$base_path" && return

  # Try extensions
  local ext
  for ext in .ts .tsx .js .jsx .mjs .cjs; do
    [ -f "$repo/${base_path}${ext}" ] && echo "${base_path}${ext}" && return
  done

  # Try index files
  for ext in .ts .tsx .js .jsx; do
    [ -f "$repo/${base_path}/index${ext}" ] && echo "${base_path}/index${ext}" && return
  done

  # Not found
  echo ""
}

extract_js_imports() {
  grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' "$FILE_LIST" > "$TMP_DIR/js_files.txt" 2>/dev/null || true
  [ ! -s "$TMP_DIR/js_files.txt" ] && return

  while IFS= read -r source_file; do
    local source_dir
    source_dir=$(dirname "$source_file")

    # Extract import paths: import ... from '...' and require('...')
    # Skip commented lines (// at start of line after optional whitespace)
    grep -E "(from ['\"]|require\(['\"])" "$REPO_PATH/$source_file" 2>/dev/null \
      | grep -v '^[[:space:]]*//' \
      | sed -n "
        s/.*from ['\"]\\([^'\"]*\\)['\"].*/\\1/p
        s/.*require(['\"]\\([^'\"]*\\)['\"].*/\\1/p
      " | while IFS= read -r import_path; do

      # Only keep relative imports
      case "$import_path" in
        ./*|../*) ;;
        *) continue ;;
      esac

      local resolved
      resolved=$(resolve_relative_path "$source_dir" "$import_path")

      local target
      target=$(find_actual_file "$REPO_PATH" "$resolved")

      if [ -n "$target" ]; then
        printf '%s\t%s\n' "$source_file" "$target"
      fi
    done
  done < "$TMP_DIR/js_files.txt"
}

extract_go_imports() {
  [ -z "$GO_MODULE" ] && return
  grep -E '\.go$' "$FILE_LIST" > "$TMP_DIR/go_files.txt" 2>/dev/null || true
  [ ! -s "$TMP_DIR/go_files.txt" ] && return

  while IFS= read -r source_file; do
    sed -n 's/.*"\(.*\)".*/\1/p' "$REPO_PATH/$source_file" 2>/dev/null \
      | while IFS= read -r import_str; do
      case "$import_str" in
        ${GO_MODULE}/*)
          local rel_path="${import_str#${GO_MODULE}/}"
          if [ -d "$REPO_PATH/$rel_path" ]; then
            printf '%s\t%s/\n' "$source_file" "$rel_path"
          fi
          ;;
      esac
    done
  done < "$TMP_DIR/go_files.txt"
}

extract_imports() {
  > "$TMP_DIR/import_edges_raw.txt"

  extract_js_imports >> "$TMP_DIR/import_edges_raw.txt"
  extract_go_imports >> "$TMP_DIR/import_edges_raw.txt"

  sort -u "$TMP_DIR/import_edges_raw.txt" > "$TMP_DIR/import_edges.txt"
  IMPORT_EDGES="$TMP_DIR/import_edges.txt"
  IMPORT_EDGE_COUNT=$(wc -l < "$IMPORT_EDGES" | tr -d ' ')
}

# ---------- Step 4: Co-Change Analysis ----------

extract_cochange() {
  local max_files="$MAX_FILES_PER_COMMIT"

  git -C "$REPO_PATH" log \
    --no-merges \
    --name-only \
    --pretty=format:'---COMMIT---' \
    -n "$MAX_COMMITS" \
    -- . ':!node_modules' ':!vendor' ':!dist' ':!build' \
    2>/dev/null \
  | awk -v max_files="$max_files" '
    /^---COMMIT---/ {
      if (n > 1 && n <= max_files) {
        # Sort files for deterministic pair ordering (insertion sort)
        for (i = 1; i < n; i++) {
          key = files[i]
          j = i - 1
          while (j >= 0 && files[j] > key) {
            files[j+1] = files[j]
            j--
          }
          files[j+1] = key
        }
        for (i = 0; i < n; i++) {
          for (j = i + 1; j < n; j++) {
            print files[i] "\t" files[j]
          }
        }
      }
      n = 0
      next
    }
    /^[[:space:]]*$/ { next }
    {
      files[n++] = $0
    }
    END {
      if (n > 1 && n <= max_files) {
        for (i = 1; i < n; i++) {
          key = files[i]
          j = i - 1
          while (j >= 0 && files[j] > key) {
            files[j+1] = files[j]
            j--
          }
          files[j+1] = key
        }
        for (i = 0; i < n; i++) {
          for (j = i + 1; j < n; j++) {
            print files[i] "\t" files[j]
          }
        }
      }
    }
  ' \
  | sort \
  | uniq -c \
  | sort -rn \
  | awk '{printf "%s\t%s\t%s\n", $2, $3, $1}' \
  > "$TMP_DIR/cochange_pairs.txt"

  COCHANGE_PAIRS="$TMP_DIR/cochange_pairs.txt"
  COCHANGE_PAIR_COUNT=$(wc -l < "$COCHANGE_PAIRS" | tr -d ' ')
}

# ---------- Step 5: Group Computation ----------

compute_groups() {
  awk -F/ -v is_monorepo="$IS_MONOREPO" '
  {
    if (is_monorepo == "true" && \
        ($1 == "packages" || $1 == "apps" || $1 == "libs" || \
         $1 == "services" || $1 == "modules")) {
      if (NF >= 3) {
        group = $1 "/" $2
      } else {
        group = $1
      }
    } else if (NF == 1) {
      group = "(root)"
    } else {
      group = $1
    }
    print $0 "\t" group
  }' "$FILE_LIST" | sort > "$TMP_DIR/file_groups.txt"

  GROUP_MAP="$TMP_DIR/file_groups.txt"

  # Unique groups with file counts
  awk -F'\t' '{print $2}' "$GROUP_MAP" \
    | sort \
    | uniq -c \
    | sort -rn \
    | awk '{print $2 "\t" $1}' \
    > "$TMP_DIR/group_sizes.txt"

  GROUP_COUNT=$(wc -l < "$TMP_DIR/group_sizes.txt" | tr -d ' ')
}

# ---------- Step 6: Cross-Group Coupling ----------

compute_cross_group_coupling() {
  # Import-based cross-group coupling
  awk -F'\t' '
    NR == FNR { group[$1] = $2; next }
    {
      sg = group[$1]; tg = group[$2]
      if (sg == "" || tg == "") next
      if (sg == tg) next
      key = (sg < tg) ? sg "\t" tg : tg "\t" sg
      count[key]++
    }
    END {
      for (k in count) print k "\t" count[k] "\timport"
    }
  ' "$GROUP_MAP" "$IMPORT_EDGES" > "$TMP_DIR/group_import_coupling.txt" 2>/dev/null || true

  # Co-change-based cross-group coupling
  awk -F'\t' '
    NR == FNR { group[$1] = $2; next }
    {
      sg = group[$1]; tg = group[$2]
      if (sg == "" || tg == "") next
      if (sg == tg) next
      key = (sg < tg) ? sg "\t" tg : tg "\t" sg
      count[key] += $3
    }
    END {
      for (k in count) print k "\t" count[k] "\tcochange"
    }
  ' "$GROUP_MAP" "$COCHANGE_PAIRS" > "$TMP_DIR/group_cochange_coupling.txt" 2>/dev/null || true

  # Merge into weighted score
  awk -F'\t' '
    {
      key = $1 "\t" $2
      if ($4 == "import") imports[key] = $3
      else if ($4 == "cochange") cochange[key] = $3
      seen[key] = 1
    }
    END {
      for (k in seen) {
        i = (k in imports) ? imports[k] : 0
        c = (k in cochange) ? cochange[k] : 0
        score = i + (c * 0.5)
        printf "%s\t%d\t%d\t%.1f\n", k, i, c, score
      }
    }
  ' "$TMP_DIR/group_import_coupling.txt" "$TMP_DIR/group_cochange_coupling.txt" \
    2>/dev/null \
  | sort -t'	' -k4 -rn \
  > "$TMP_DIR/cross_group_coupling.txt" || true

  CROSS_GROUP_COUPLING="$TMP_DIR/cross_group_coupling.txt"
}

# ---------- Step 7: Report Generation ----------

generate_report() {
  local head_commit
  head_commit=$(git -C "$REPO_PATH" rev-parse --short HEAD)
  local timestamp
  timestamp=$(git -C "$REPO_PATH" log -1 --format='%aI' HEAD)

  mkdir -p "$OUTPUT_DIR"
  OUTPUT_PATH="$OUTPUT_DIR/$REPO_NAME.md"

  {
    echo "# Repository Analysis: $REPO_NAME"
    echo ""
    echo "> Generated: $timestamp"
    echo "> Repository: $REPO_PATH"
    echo "> Commit: $head_commit"
    echo ""

    # Summary
    echo "## Summary"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Languages | $LANGUAGES |"
    echo "| Frameworks | $FRAMEWORKS |"
    echo "| Structure | $([ "$IS_MONOREPO" = true ] && echo "Monorepo" || echo "Standard") |"
    echo "| Source files | $FILE_COUNT |"
    echo "| Coupling groups | $GROUP_COUNT |"
    echo "| Import edges | $IMPORT_EDGE_COUNT |"
    echo "| Co-change pairs | $COCHANGE_PAIR_COUNT |"
    echo "| Commits analyzed | $MAX_COMMITS |"
    echo ""

    # Coupling Groups
    echo "## Coupling Groups"
    echo ""
    echo "| Group | Files |"
    echo "|-------|-------|"
    awk -F'\t' '{printf "| %s | %s |\n", $1, $2}' "$TMP_DIR/group_sizes.txt"
    echo ""

    # Top Import Edges
    echo "## Top Import Edges"
    echo ""
    if [ "$IMPORT_EDGE_COUNT" -gt 0 ]; then
      echo "| Source | Target |"
      echo "|--------|--------|"
      head -n "$TOP_N" "$IMPORT_EDGES" | awk -F'\t' '{printf "| `%s` | `%s` |\n", $1, $2}'
    else
      echo "No import edges detected."
    fi
    echo ""

    # Top Co-Change Pairs
    echo "## Top Co-Change Pairs"
    echo ""
    if [ "$COCHANGE_PAIR_COUNT" -gt 0 ]; then
      echo "| File A | File B | Co-changes |"
      echo "|--------|--------|------------|"
      head -n "$TOP_N" "$COCHANGE_PAIRS" | awk -F'\t' '{printf "| `%s` | `%s` | %s |\n", $1, $2, $3}'
    else
      echo "No co-change pairs detected."
    fi
    echo ""

    # Cross-Group Coupling
    echo "## Cross-Group Coupling"
    echo ""
    if [ -s "$CROSS_GROUP_COUPLING" ]; then
      echo "| Group A | Group B | Import Edges | Co-changes | Score |"
      echo "|---------|---------|-------------|------------|-------|"
      awk -F'\t' '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}' "$CROSS_GROUP_COUPLING"
    else
      echo "No cross-group coupling detected."
    fi
    echo ""

  } > "$OUTPUT_PATH"
}

# ---------- Step 8: Persist Coupling Data ----------

persist_data() {
  local data_dir="$OUTPUT_DIR/$REPO_NAME"
  mkdir -p "$data_dir"
  cp "$TMP_DIR/import_edges.txt" "$data_dir/" 2>/dev/null || true
  cp "$TMP_DIR/cochange_pairs.txt" "$data_dir/" 2>/dev/null || true
  cp "$TMP_DIR/cross_group_coupling.txt" "$data_dir/" 2>/dev/null || true
  cp "$TMP_DIR/file_groups.txt" "$data_dir/" 2>/dev/null || true
}

# ---------- Main ----------

main() {
  parse_args "$@"
  validate_repo

  echo "Analyzing repository: $REPO_PATH"
  echo "  Max commits: $MAX_COMMITS"
  echo ""

  echo "Detecting languages..."
  detect_language

  echo "Listing source files..."
  list_tracked_files
  echo "  Found $FILE_COUNT source files"

  echo "Extracting import edges..."
  extract_imports
  echo "  Found $IMPORT_EDGE_COUNT import edges"

  echo "Analyzing co-change history..."
  extract_cochange
  echo "  Found $COCHANGE_PAIR_COUNT co-change pairs"

  echo "Computing coupling groups..."
  compute_groups
  echo "  Found $GROUP_COUNT groups"

  echo "Computing cross-group coupling..."
  compute_cross_group_coupling

  echo "Generating report..."
  generate_report

  echo "Persisting coupling data..."
  persist_data

  echo ""
  echo "Analysis complete: $OUTPUT_PATH"
  exit 0
}

main "$@"
