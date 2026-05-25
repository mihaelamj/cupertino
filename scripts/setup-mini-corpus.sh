#!/usr/bin/env bash
#
# scripts/setup-mini-corpus.sh: build a small but representative test
# corpus by symlinking ~10% of the real cupertino corpus from
# ~/.cupertino/ into an output directory.
#
# Sister of:
#   smoke-reindex.sh : throwaway temp DB + invariant checks on the 7-page
#                      synthetic fixture (Packages/Tests/Fixtures/SmokeCorpus/).
#                      Validates the indexer mechanics in ~1s.
#   make-mini-db.sh  : persistent DB on the same 7-page synthetic fixture
#                      for repeated local MCP / CLI probes.
#   setup-mini-corpus.sh (this script) : real Apple corpus at ~10%
#                      sampled, ~42K docs, ~5 min indexing.
#                      Validates the indexer pipeline END-TO-END (all
#                      strategies + enrichment passes) against a corpus
#                      shaped like the real one, including the leaf
#                      directory-symlinks for the optional sources that
#                      trigger the #779 ENOTDIR class of bug.
#
# Usage:
#   scripts/setup-mini-corpus.sh [OUTPUT_DIR]
#
# Default OUTPUT_DIR: /Volumes/Code/DeveloperExt/public/cupertino-mini-corpus
#
# Pre-flight requires ~/.cupertino/ to be populated. Run `cupertino setup`
# or have an existing brew install with the bundled corpus.
#
# What it builds:
#
#   <OUTPUT_DIR>/
#   ├── apple-constraints.json -> ~/.cupertino-dev/apple-constraints.json
#   ├── docs/                                          REAL DIR
#   │   ├── swiftui/                                   REAL DIR
#   │   │   ├── doc1.json -> ~/.cupertino/docs/swiftui/doc1.json    (file symlink)
#   │   │   ├── ...                                                  (~10% of files)
#   │   ├── foundation/                                (same shape)
#   │   └── ...                                        (all 402 frameworks at ~10%)
#   ├── swift-evolution -> ~/.cupertino/swift-evolution    LEAF dir-symlink
#   ├── swift-org       -> ~/.cupertino/swift-org          LEAF dir-symlink
#   ├── archive         -> ~/.cupertino/archive            LEAF dir-symlink
#   └── hig             -> ~/.cupertino/hig                LEAF dir-symlink
#
# Why this shape:
#
#   - docs/<framework>/ as real dirs with file-level symlinks: the
#     apple-docs phase indexes only the sampled files (~42K total at
#     10%) instead of the full ~415K corpus. Keeps the validation run
#     to ~5 minutes instead of 11 hours.
#
#   - The four optional dirs as LEAF dir-symlinks: this is the exact
#     #779 bug-trigger shape. The dev layout (~/.cupertino-dev/) has
#     these four as leaf-symlinks into ~/.cupertino/; the real
#     production reproduction is this exact arrangement. Pre-#779-fix,
#     `cupertino save` throws ENOTDIR on swift-evolution (the first
#     optional in the strategy order). Post-#779-fix, all four index
#     their content and the three enrichment passes complete.
#
# Validation:
#
#   After running this script, validate with:
#     cupertino save --source apple-docs --docs-dir <OUTPUT_DIR>/docs \
#                          --base-dir <OUTPUT_DIR> --yes
#
#   Pre-#779-fix : expect failure on swift-evolution after the apple-docs phase.
#   Post-#779-fix: expect success with all four optional sources indexed
#                  and the three enrichment passes (registerFrameworkSynonyms,
#                  applyAppleStaticConstraints, propagateConstraintsFromParents)
#                  complete.
#
# Idempotent: re-running fully resets the output dir. Only symlinks are
# written; zero file duplication; the output dir size is just inode entries.

set -euo pipefail

OUTPUT_DIR="${1:-/Volumes/Code/DeveloperExt/public/cupertino-mini-corpus}"
BREW_DIR="$HOME/.cupertino"
DEV_DIR="$HOME/.cupertino-dev"
SAMPLE_PER_MILLE=100   # 10.0% expressed as parts-per-1000 (integer math)
MIN_FILES_PER_FW=3     # floor: tiny frameworks still get at least this many

bail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

# ----- pre-flight -----

[[ -d "$BREW_DIR/docs" ]] || bail "$BREW_DIR/docs not found; run 'cupertino setup' first"

DOC_FRAMEWORK_COUNT=$(find "$BREW_DIR/docs" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
[[ $DOC_FRAMEWORK_COUNT -ge 10 ]] || bail "$BREW_DIR/docs has only $DOC_FRAMEWORK_COUNT framework subdirs; expected 300+"

echo "=== mini-corpus setup ==="
echo "  output:          $OUTPUT_DIR"
echo "  source (brew):   $BREW_DIR ($DOC_FRAMEWORK_COUNT framework subdirs detected)"
echo "  sample ratio:    ${SAMPLE_PER_MILLE} per 1000 (= 10%)"
echo "  min files/fw:    $MIN_FILES_PER_FW"
echo

# Reset output dir (fully; always start fresh per skill rotation rule)
if [[ -e "$OUTPUT_DIR" ]]; then
    echo "  resetting existing $OUTPUT_DIR ..."
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR/docs"

# ----- 1. apple-docs: per-framework file-level symlinks -----

echo "=== apple-docs (per-framework file-level symlinks, ${SAMPLE_PER_MILLE}/1000 of each) ==="
TOTAL_DOCS=0
FRAMEWORK_COUNT=0
EMPTY_FRAMEWORKS=0

for fw_dir in "$BREW_DIR/docs"/*/; do
    fw_name=$(basename "$fw_dir")

    # Skip hidden dirs / dot-files
    [[ "$fw_name" == .* ]] && continue

    # Collect all .json files (recursive in case any framework nests).
    # Plain `while read` loop instead of bash-4 `mapfile`; macOS ships bash 3.2.
    files=()
    while IFS= read -r line; do
        files+=("$line")
    done < <(find "$fw_dir" -type f -name "*.json" | sort)
    total=${#files[@]}
    if [[ $total -eq 0 ]]; then
        EMPTY_FRAMEWORKS=$((EMPTY_FRAMEWORKS + 1))
        continue
    fi

    # sample = round(total * SAMPLE_PER_MILLE / 1000), floor MIN_FILES_PER_FW, cap total
    sample=$(( (total * SAMPLE_PER_MILLE + 500) / 1000 ))
    [[ $sample -lt $MIN_FILES_PER_FW ]] && sample=$MIN_FILES_PER_FW
    [[ $sample -gt $total ]] && sample=$total

    # Evenly distributed pick: every (total/sample)-th file from the sorted list.
    # Deterministic + diverse + no shuf dependency (BSD shuf isn't on macOS).
    step=$(( total / sample ))
    [[ $step -lt 1 ]] && step=1

    mkdir -p "$OUTPUT_DIR/docs/$fw_name"
    picked=0
    for (( i = 0; i < total && picked < sample; i += step )); do
        src="${files[$i]}"
        rel="${src#$fw_dir}"
        dst="$OUTPUT_DIR/docs/$fw_name/$rel"
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        picked=$((picked + 1))
    done

    TOTAL_DOCS=$((TOTAL_DOCS + picked))
    FRAMEWORK_COUNT=$((FRAMEWORK_COUNT + 1))
done

echo "  $TOTAL_DOCS docs symlinked across $FRAMEWORK_COUNT frameworks"
[[ $EMPTY_FRAMEWORKS -gt 0 ]] && echo "  $EMPTY_FRAMEWORKS framework dirs were empty (skipped)"
echo

# ----- 2. Four optional dirs as LEAF dir-symlinks (TRIGGERS #779) -----

echo "=== four optional dirs (LEAF dir-symlinks; this is the #779 trigger shape) ==="
for src_name in swift-evolution swift-org archive hig; do
    src_path="$BREW_DIR/$src_name"
    if [[ -d "$src_path" ]]; then
        ln -s "$src_path" "$OUTPUT_DIR/$src_name"
        n=$(find "$src_path" -maxdepth 1 -type f | wc -l | tr -d ' ')
        echo "  $src_name -> $src_path ($n top-level files visible)"
    else
        echo "  $src_name: source missing, skipping"
    fi
done
echo

# ----- 3. apple-constraints.json -----

if [[ -f "$DEV_DIR/apple-constraints.json" ]]; then
    ln -s "$DEV_DIR/apple-constraints.json" "$OUTPUT_DIR/apple-constraints.json"
    constraints_size=$(stat -f '%z' "$DEV_DIR/apple-constraints.json")
    echo "=== apple-constraints.json symlinked from $DEV_DIR ($constraints_size bytes) ==="
else
    echo "WARN: $DEV_DIR/apple-constraints.json missing; iter-3 constraints lookup will be skipped"
fi
echo

# ----- summary -----

echo "=== mini-corpus ready ==="
echo "  $OUTPUT_DIR"
echo
echo "Validate end-to-end:"
echo "  cupertino save --source apple-docs --docs-dir $OUTPUT_DIR/docs --base-dir $OUTPUT_DIR --yes"
echo
echo "Expected:"
echo "  Pre-#779-fix  : Error 'The file \"swift-evolution\" couldn'\''t be opened.' after apple-docs phase."
echo "  Post-#779-fix : success, all four optional sources indexed,"
echo "                  three enrichment passes complete."
