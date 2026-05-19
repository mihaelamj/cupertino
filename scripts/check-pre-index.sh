#!/usr/bin/env bash
#
# scripts/check-pre-index.sh: pre-index validation gate (#794).
#
# Two gates that MUST pass before kicking off an 11h+ real save against the
# production corpus. Catches the two silent-failure classes the post-#779 arc
# left behind:
#
#   Gate 1 (cleanup): #789 removed the search.db `packages` +
#   `package_dependencies` tables and the SwiftPackagesStrategy that fed
#   them. This gate verifies that removal stuck end-to-end: no residue
#   tables in `sqlite_master`, no swift-packages emission in the save log,
#   no orphan readers in source.
#
#   Gate 2 (symbolgraph value-add): cupertino-symbolgraphs v0.1.1 +
#   #759 iter-3 produce an `apple-constraints.json` catalog that
#   populates `doc_symbols.generic_constraints` via the
#   `applyAppleStaticConstraints` enrichment pass. This gate verifies the
#   apple-constraints.json file is present and non-trivial, the iter-3
#   pass actually fires (log line present), and `generic_constraints`
#   coverage is at least 30% of generic-bearing rows. Without this gate
#   the symbolgraph corpus work could silently no-op and the produced
#   bundle would ship without the constraint-form `T: Collection`
#   matches that `search_generics` advertises.
#
# Sister of:
#   smoke-reindex.sh      : 1s throwaway DB on the 7-page synthetic fixture
#   make-mini-db.sh       : persistent DB on the same synthetic fixture
#   setup-mini-corpus.sh  : build the 10% real-corpus symlink fixture
#   check-pre-index.sh    : this script; runs a save against the fixture
#                           and asserts the two gates above
#
# Usage:
#   scripts/check-pre-index.sh                 # default: 10% mini-corpus
#   scripts/check-pre-index.sh /tmp/my-corpus  # custom corpus dir
#
# Pre-requirements:
#   - 10% mini-corpus already built at the default path
#     (run scripts/setup-mini-corpus.sh first)
#   - Release-built dev binary at Packages/.build/release/cupertino
#     (run `cd Packages && make build-release` first)
#
# Exit codes:
#   0  all gates passed
#   1  one or more gates failed (specific gate + remediation hint printed)
#
# Wall time: ~11 minutes (one full save against the 10% fixture; same cost
# as the existing mini-corpus validation; 1/60th the cost of a real 11h+
# save).

set -euo pipefail

# --skip-save reuses the existing search.db from a prior run instead of
# re-running cupertino save. Useful when iterating on the gate logic and the
# 11-min save cost is wasteful. Same DB, same log, same assertions; you just
# need to have run the script once already to produce them.
SKIP_SAVE=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --skip-save) SKIP_SAVE=1 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

CORPUS="${1:-/Volumes/Code/DeveloperExt/public/cupertino-mini-corpus}"
CUPERTINO_REPO="${CUPERTINO_REPO:-/Volumes/Code/DeveloperExt/public/cupertino}"
BINARY="$CUPERTINO_REPO/Packages/.build/release/cupertino"
if [[ "$SKIP_SAVE" -eq 1 ]]; then
    # Reuse the most recent save log from a prior run; bail if none.
    # macOS mktemp puts files under /var/folders/X/Y/T/<name> (3 path components
    # under /var/folders), not just /var/folders/X/T/.
    LOG=$(ls -t /var/folders/*/*/T/cupertino-pre-index.* 2>/dev/null | head -1)
    if [[ -z "$LOG" ]]; then
        printf '\n❌ --skip-save requires a prior run to have left a save log behind; none found under /var/folders/*/T/cupertino-pre-index.*\n' >&2
        exit 1
    fi
else
    LOG=$(mktemp -t cupertino-pre-index)
fi
DB="$CORPUS/search.db"

bail() {
    printf '\n❌ %s\n' "$1" >&2
    exit 1
}

pass() {
    printf '  ✓ %s\n' "$1"
}

# ----- pre-flight -----

[[ -d "$CORPUS" ]] || bail "corpus dir missing: $CORPUS (run scripts/setup-mini-corpus.sh first)"
[[ -x "$BINARY" ]] || bail "release binary missing: $BINARY (run: cd $CUPERTINO_REPO/Packages && make build-release)"
[[ -d "$CORPUS/docs" ]] || bail "$CORPUS/docs missing; corpus fixture is incomplete (re-run setup-mini-corpus.sh)"

DOC_SYMLINK_COUNT=$(find "$CORPUS/docs" -type l 2>/dev/null | wc -l | tr -d ' ')
[[ "$DOC_SYMLINK_COUNT" -gt 1000 ]] || bail "$CORPUS/docs has only $DOC_SYMLINK_COUNT symlinks; coverage assertions would be unreliable (expected ~41,000 for the 10% fixture)"

# Disk sleep on the active save volume is a real risk on long jobs. The
# May 18 production save almost stalled because of disksleep=10 on the
# Claw mini's external SSD. macOS process-level caffeinate prevents
# SYSTEM sleep but not DISK sleep; only `sudo pmset -a disksleep 0`
# does that. This pre-flight fails loudly so the operator fixes it
# before paying for the 11h save, not after.
DISKSLEEP=$(pmset -g 2>/dev/null | awk '/disksleep/ {print $2}')
if [[ "${DISKSLEEP:-1}" != "0" ]]; then
    bail "disksleep is ${DISKSLEEP:-unknown}, not 0; long save may stall on disk-sleep eviction. Fix: sudo pmset -a disksleep 0  (then re-run this script)"
fi

echo "=== pre-index validation gate (#794) ==="
echo "  corpus:    $CORPUS  ($DOC_SYMLINK_COUNT doc symlinks)"
echo "  binary:    $BINARY"
echo "  save log:  $LOG"
echo

if [[ "$SKIP_SAVE" -eq 1 ]]; then
    echo "=== --skip-save: reusing existing save.db + log ==="
    echo "  save log: $LOG (from a prior run; assertions key off it)"
    [[ -f "$DB" ]] || bail "--skip-save needs $DB from a prior run; not found. Re-run without --skip-save once."
else
    # Wipe stale save output from prior runs (assertions key off post-save DB state).
    rm -f "$CORPUS"/search.db "$CORPUS"/search.db-shm "$CORPUS"/search.db-wal "$CORPUS"/save-*.jsonl

    echo "=== Running cupertino save (expect ~5-11 min) ==="
    echo "  Tail the save log in another tab:"
    echo "    tail -f $LOG"
    echo

    if ! "$BINARY" save --docs --docs-dir "$CORPUS/docs" --base-dir "$CORPUS" --yes > "$LOG" 2>&1; then
        bail "save itself failed; tail $LOG for the error"
    fi
fi

# ----- Gate 1: cleanup -----

echo
echo "=== Gate 1: cleanup (no #789 packages-residue) ==="

PKG_TABLES=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'packages%' OR name = 'package_dependencies');" | wc -l | tr -d ' ')
if [[ "$PKG_TABLES" -ne 0 ]]; then
    bail "search.db carries $PKG_TABLES packages-residue table(s); #789 migration didn't take. Run: sqlite3 $DB '.schema packages*'"
fi
pass "no packages-residue tables in sqlite_master"

SWIFT_PKG_LINES=$(grep -cE "swift-packages|SwiftPackagesStrategy|PackagesIndexer|Indexing Swift packages" "$LOG" || true)
if [[ "$SWIFT_PKG_LINES" -ne 0 ]]; then
    bail "save log contains $SWIFT_PKG_LINES swift-packages emission line(s); strategy registration not removed. Check Search.IndexBuilder.makeDefaultStrategies"
fi
pass "save log clean of swift-packages emission"

# Wrap each `grep -v` in `{ ... || true; }` because `set -e` + `set -o pipefail`
# would otherwise kill the script when the filter strips ALL matches (which is
# the success case for us). The leading grep also gets the same wrapper so a
# clean codebase (zero matches at all) doesn't bail.
ORPHAN_READERS=$( \
    { grep -rEn "FROM packages\b|\bPackagesIndexer\b|Search\.SwiftPackagesStrategy" "$CUPERTINO_REPO/Packages/Sources" --include="*.swift" 2>/dev/null || true; } \
    | sed -E 's|^[^:]+:[0-9]+:||' \
    | { grep -vE "^[[:space:]]*(//|/\*|\*[^/])" || true; } \
    | { grep -v "#789" || true; } \
    | wc -l | tr -d ' ')
if [[ "$ORPHAN_READERS" -ne 0 ]]; then
    bail "source has $ORPHAN_READERS orphan packages-reader reference(s); grep them: grep -rEn 'FROM packages\\b|\\bPackagesIndexer\\b|Search\\.SwiftPackagesStrategy' $CUPERTINO_REPO/Packages/Sources --include='*.swift' | grep -vE ':[[:space:]]*(//|/\\*|\\*)' | grep -v '#789'"
fi
pass "source-tree clean of orphan packages-readers"

# ----- Gate 2: symbolgraph value-add -----

echo
echo "=== Gate 2: symbolgraph value-add (apple-constraints + iter-3 + generic_constraints coverage) ==="

CONSTRAINTS="$CORPUS/apple-constraints.json"
if [[ ! -e "$CONSTRAINTS" ]]; then
    bail "apple-constraints.json missing at $CONSTRAINTS (regenerate via cupertino-constraints-gen against the latest cupertino-symbolgraphs corpus zip)"
fi

# Follow a symlink if the fixture is set up that way.
if [[ -L "$CONSTRAINTS" ]]; then
    RESOLVED=$(readlink "$CONSTRAINTS")
    # readlink may return a relative path; prepend the dir if it's not absolute.
    case "$RESOLVED" in
        /*) ;;
        *) RESOLVED="$CORPUS/$RESOLVED" ;;
    esac
else
    RESOLVED="$CONSTRAINTS"
fi
SIZE=$(stat -f '%z' "$RESOLVED" 2>/dev/null || stat -c '%s' "$RESOLVED" 2>/dev/null)
if [[ -z "$SIZE" ]] || [[ "$SIZE" -lt 5000000 ]]; then
    bail "apple-constraints.json suspiciously small (${SIZE:-unknown} bytes; expected >5MB; regenerate via cupertino-constraints-gen against the latest corpus zip)"
fi
pass "apple-constraints.json present (${SIZE} bytes; resolved to $RESOLVED)"

if grep -q "Applied authoritative Apple constraints table" "$LOG"; then
    pass "iter-3 'Applied authoritative Apple constraints table' log line present"
else
    bail "save log missing 'Applied authoritative Apple constraints table' line; iter-3 silently no-op'd. Check LiveDocsIndexingRunner staticConstraintsLookup loader (Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift)"
fi

CONSTRAINTS_ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM doc_symbols WHERE generic_constraints IS NOT NULL AND generic_constraints != '';")
# Absolute floor against the 10% mini-corpus. Empirical baseline measured
# during #794 implementation: ~3,474 rows on the 10% fixture. Floor of 500
# accommodates fixture-mix variance (different sampled frameworks → different
# generic-bearing populations) while still firing loudly if iter-3 silently
# no-op'd (would be 0 rows). A ratio-based gate doesn't work here because
# generic_constraints can be populated on rows where generic_params is NULL
# (iter-3 fills constraints from apple-constraints.json regardless of whether
# AST extraction caught the params half).
if [[ "$CONSTRAINTS_ROWS" -lt 500 ]]; then
    bail "generic_constraints row count $CONSTRAINTS_ROWS is below 500 floor; symbolgraph constraints pipeline degraded or iter-3 silently no-op'd. Check Search.Index.applyAppleStaticConstraints SQL UPDATE path against the LiveDocsIndexingRunner staticConstraintsLookup loader"
fi
pass "generic_constraints populated: $CONSTRAINTS_ROWS rows (floor 500)"

# ----- summary -----

echo
echo "=== ALL PRE-INDEX GATES PASSED ==="
echo "Safe to kick off the real 11h+ save against the production corpus."
echo
echo "Save log: $LOG"
echo "Mini-corpus search.db left in place at: $DB"
