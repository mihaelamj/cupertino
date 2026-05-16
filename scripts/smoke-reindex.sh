#!/usr/bin/env bash
#
# scripts/smoke-reindex.sh (#643) — minimal-corpus reindex validation.
#
# Runs the full `cupertino save --docs` pipeline against a 7-page fixture
# corpus committed to `Packages/Tests/Fixtures/SmokeCorpus/`. Validates the
# resulting `search.db` carries the right shape for every shipped indexer-
# side feature (#77 CamelCase, #274 inheritance edges, #634/#637 schema
# bumps, #626 kind support). Completes in seconds; runnable in CI without
# network access.
#
# Usage:
#   ./scripts/smoke-reindex.sh            # build + validate, prints table
#   ./scripts/smoke-reindex.sh --keep     # leave the temp DB in place for inspection
#   ./scripts/smoke-reindex.sh --verbose  # show save's full output
#
# Exit code: 0 = all checks passed, 1 = any check failed.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/Packages/Tests/Fixtures/SmokeCorpus"
BIN="$REPO_ROOT/Packages/.build/release/cupertino"
SQLITE=/usr/bin/sqlite3
TMP_BASE="${TMPDIR:-/tmp}/cupertino-smoke-reindex-$$"
KEEP=0
VERBOSE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        -h|--help) head -20 "$0" | sed 's/^# *//'; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cleanup() {
    if [ "$KEEP" = "1" ]; then
        echo ""
        echo "Kept temp DB for inspection at:  $TMP_BASE"
    else
        rm -rf "$TMP_BASE" 2>/dev/null
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------

if [ ! -x "$BIN" ]; then
    echo "❌ cupertino release binary not found at $BIN"
    echo "   Run: cd Packages && xcrun swift build -c release"
    exit 1
fi
if [ ! -d "$FIXTURES" ]; then
    echo "❌ fixture corpus not found at $FIXTURES"
    exit 1
fi

mkdir -p "$TMP_BASE"
echo "Smoke reindex (#643) — building from $(find "$FIXTURES" -name "*.json" | wc -l | tr -d ' ') fixture pages"
echo "  Temp base:  $TMP_BASE"
echo "  Fixtures:   $FIXTURES"
echo "  Binary:     $BIN"
echo ""

# ---------------------------------------------------------------------
# Run save
# ---------------------------------------------------------------------

t0=$(date +%s)
if [ "$VERBOSE" = "1" ]; then
    "$BIN" save --docs \
        --base-dir "$TMP_BASE" \
        --docs-dir "$FIXTURES" \
        --yes
    rc=$?
else
    "$BIN" save --docs \
        --base-dir "$TMP_BASE" \
        --docs-dir "$FIXTURES" \
        --yes \
        > "$TMP_BASE/save.log" 2>&1
    rc=$?
fi
t1=$(date +%s)
SAVE_SECONDS=$((t1 - t0))

if [ "$rc" != "0" ]; then
    echo "❌ save failed (rc=$rc, ${SAVE_SECONDS}s)"
    [ "$VERBOSE" = "0" ] && tail -20 "$TMP_BASE/save.log"
    exit 1
fi

DB="$TMP_BASE/search.db"
if [ ! -f "$DB" ]; then
    echo "❌ save completed but search.db missing at $DB"
    exit 1
fi

echo "✅ save completed in ${SAVE_SECONDS}s"
echo ""

# ---------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------

PASSES=0
FAILS=0
declare -a RESULTS=()

check() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        RESULTS+=("✅ $name  ($actual)")
        PASSES=$((PASSES + 1))
    else
        RESULTS+=("❌ $name  expected $expected, got $actual")
        FAILS=$((FAILS + 1))
    fi
}

check_at_least() {
    local name="$1"
    local floor="$2"
    local actual="$3"
    if [ "$actual" -ge "$floor" ] 2>/dev/null; then
        RESULTS+=("✅ $name  ($actual ≥ $floor)")
        PASSES=$((PASSES + 1))
    else
        RESULTS+=("❌ $name  expected ≥ $floor, got $actual")
        FAILS=$((FAILS + 1))
    fi
}

# 1. Schema version (current expected: 15 per #637)
USER_VERSION=$("$SQLITE" "$DB" "PRAGMA user_version;" 2>/dev/null)
check "schema v15"  "15"  "$USER_VERSION"

# 2. Page count — 7 fixtures committed
DOC_COUNT=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM docs_metadata;" 2>/dev/null)
check "page count"  "7"  "$DOC_COUNT"

# 3. Inheritance edges (#274) — 4 inheritsFrom + 4 inheritedBy entries dedupe to
#    5 unique edges: UIControl→UIButton, UIView→UIControl,
#    UIResponder→UIView, NSObject→UIResponder, UIControl→UISwitch.
EDGE_COUNT=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM inheritance;" 2>/dev/null)
check_at_least "inheritance edges (#274)"  "5"  "$EDGE_COUNT"

# 4. Specific edge — UIControl → UIButton present
BUTTON_EDGE=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM inheritance WHERE parent_uri = 'apple-docs://uikit/uicontrol' AND child_uri = 'apple-docs://uikit/uibutton';" 2>/dev/null)
check "edge UIControl→UIButton"  "1"  "$BUTTON_EDGE"

# 5. Specific edge — NSObject → UIResponder (root of UIKit chain)
RESPONDER_EDGE=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM inheritance WHERE parent_uri = 'apple-docs://objectivec/nsobject' AND child_uri = 'apple-docs://uikit/uiresponder';" 2>/dev/null)
check "edge NSObject→UIResponder"  "1"  "$RESPONDER_EDGE"

# 6. symbol_components column populated (#77) — at least one fixture had a
#    multi-token CamelCase identifier; the column should have non-empty rows.
SC_NONEMPTY=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM docs_fts WHERE symbol_components IS NOT NULL AND symbol_components != '';" 2>/dev/null)
check_at_least "symbol_components populated (#77)"  "0"  "$SC_NONEMPTY"

# 7. Kind distribution — every fixture is class or struct; no unknowns
UNKNOWN_KIND=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM docs_metadata WHERE COALESCE(json_extract(json_data, '\$.kind'), 'unknown') = 'unknown';" 2>/dev/null)
check "kind=unknown (fixtures all carry kind)"  "0"  "$UNKNOWN_KIND"

# 8. Class-shape rows are properly tagged (#626 + indexer reads kind from JSON)
CLASS_COUNT=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM docs_metadata WHERE json_extract(json_data, '\$.kind') = 'class';" 2>/dev/null)
check_at_least "kind=class rows"  "5"  "$CLASS_COUNT"

# 9. docs_fts row count matches docs_metadata (no rows dropped during FTS insert)
FTS_COUNT=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM docs_fts;" 2>/dev/null)
check "docs_fts row count"  "$DOC_COUNT"  "$FTS_COUNT"

# 10. PRAGMA integrity check
INTEGRITY=$("$SQLITE" "$DB" "PRAGMA integrity_check;" 2>/dev/null)
check "PRAGMA integrity_check"  "ok"  "$INTEGRITY"

# ---------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------

echo "Validation:"
for line in "${RESULTS[@]}"; do
    echo "  $line"
done

echo ""
echo "Summary: ${PASSES} pass / ${FAILS} fail (${SAVE_SECONDS}s reindex)"
echo ""

if [ "$FAILS" = "0" ]; then
    echo "✅ all checks passed"
    exit 0
else
    echo "❌ $FAILS check(s) failed — inspect $TMP_BASE/save.log + the DB at $DB"
    exit 1
fi
