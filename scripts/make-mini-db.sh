#!/usr/bin/env bash
#
# scripts/make-mini-db.sh — build a persistent miniature cupertino DB
# for develop-side MCP / CLI probes that DO NOT touch ~/.cupertino/.
#
# Sister of `scripts/smoke-reindex.sh`. They share the 7-page
# `Packages/Tests/Fixtures/SmokeCorpus/` fixture set but differ in
# intent:
#
#   smoke-reindex.sh : throwaway temp DB + 10 invariant checks,
#                      validates the indexer pipeline in ~1s.
#   make-mini-db.sh  : persistent DB at a predictable path that
#                      survives across runs, intended for repeated
#                      MCP `tools/call` probes, `cupertino search`
#                      verifications, and ad-hoc local checks.
#
# Why this exists (2026-05-16): a develop-side MCP probe seeded a
# fresh v15 fixture DB directly at `~/.cupertino/search.db` (instead
# of an isolated path) and the post-probe restore step failed
# silently. Main came up at promote retest time, opened the live
# search.db, saw 8 rows + v15, and flagged it as a 2.48 GB → 1 MB
# truncation incident. No data was lost (a separate backup was
# restored intact), but the false-alarm overhead was real. This
# script gives develop a no-friction default that's impossible to
# confuse with the user-facing bundle path.
#
# Usage:
#   ./scripts/make-mini-db.sh                  # builds at /tmp/cupertino-mini-db
#   ./scripts/make-mini-db.sh --out /tmp/X     # custom output path
#   ./scripts/make-mini-db.sh --clean          # rm -rf the out dir first
#   ./scripts/make-mini-db.sh --verbose        # show save's full output
#
# After the build prints "✅ done", probe with:
#
#   ./Packages/.build/release/cupertino search SwiftUI \
#       --base-dir /tmp/cupertino-mini-db
#
#   ./Packages/.build/release/cupertino serve \
#       --base-dir /tmp/cupertino-mini-db
#
# Exit code: 0 on success, 1 on any failure.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/Packages/Tests/Fixtures/SmokeCorpus"
BIN="$REPO_ROOT/Packages/.build/release/cupertino"
OUT="/tmp/cupertino-mini-db"
CLEAN=0
VERBOSE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out)
            OUT="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown flag: $1 (see --help)" >&2
            exit 1
            ;;
    esac
done

if [ ! -x "$BIN" ]; then
    echo "❌ release binary not found at $BIN" >&2
    echo "   build it with: cd Packages && xcrun swift build -c release --product cupertino" >&2
    exit 1
fi

if [ ! -d "$FIXTURES" ]; then
    echo "❌ fixture corpus not found at $FIXTURES" >&2
    exit 1
fi

# Refuse to point at ~/.cupertino — the whole point of this script
# is to keep develop-side probes away from the bundle path.
case "$OUT" in
    "$HOME/.cupertino"|"$HOME/.cupertino/"*|"/Users/"*"/.cupertino"|"/Users/"*"/.cupertino/"*)
        echo "❌ refusing to build mini DB inside ~/.cupertino (--out is $OUT)" >&2
        echo "   pick a different path; this script exists precisely to avoid that one." >&2
        exit 1
        ;;
esac

echo "Mini DB build — 7 fixture pages"
echo "  Output:   $OUT"
echo "  Fixtures: $FIXTURES"
echo "  Binary:   $BIN"

if [ "$CLEAN" -eq 1 ] && [ -d "$OUT" ]; then
    echo "  Cleaning existing output dir..."
    rm -rf "$OUT"
fi

mkdir -p "$OUT"

if [ "$VERBOSE" -eq 1 ]; then
    "$BIN" save --docs \
        --base-dir "$OUT" \
        --docs-dir "$FIXTURES" \
        --yes
    STATUS=$?
else
    SAVE_LOG="$OUT/.save.log"
    "$BIN" save --docs \
        --base-dir "$OUT" \
        --docs-dir "$FIXTURES" \
        --yes > "$SAVE_LOG" 2>&1
    STATUS=$?
fi

if [ "$STATUS" -ne 0 ]; then
    echo "❌ save failed (exit $STATUS)" >&2
    if [ "$VERBOSE" -eq 0 ]; then
        echo "   re-run with --verbose to see save output, or inspect: $SAVE_LOG" >&2
    fi
    exit 1
fi

DB_PATH="$OUT/search.db"
if [ ! -f "$DB_PATH" ]; then
    echo "❌ save reported success but $DB_PATH wasn't created" >&2
    exit 1
fi

SIZE=$(stat -f%z "$DB_PATH" 2>/dev/null || stat -c%s "$DB_PATH" 2>/dev/null)
PAGES=$(/usr/bin/sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM docs_metadata" 2>/dev/null || echo "?")

echo ""
echo "✅ done"
echo "  search.db:  $DB_PATH ($SIZE bytes, $PAGES pages)"
echo ""
echo "Probe with:"
echo "  $BIN search SwiftUI --base-dir $OUT"
echo "  $BIN serve --base-dir $OUT"
