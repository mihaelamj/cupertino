#!/usr/bin/env bash
#
# check-canonical-db-shape.sh
#
# Read-only smoke check that verifies a `cupertino` installation's
# `search.db` is in canonical shape. Used to disambiguate genuine
# corpus / retrieval bugs from corruption-state false positives.
#
# Origin: 2026-05-17 round closed four issues (#708 / #709 / #715 /
# #719) that were all probing a corrupt 160 MB / 37 frameworks /
# 21,701 documents `~/.cupertino/search.db` — the residue of a
# same-session runaway-save incident. Two cycles of file-issue →
# cross-link → comment → close burned more time than running this
# smoke check upfront would have.
#
# The check is read-only. Never touches `~/.cupertino/*.db`, never
# runs `save`, never writes anything. Just calls
# `cupertino list-frameworks` and parses the header line.
#
# Run from the repo root or with `CUPERTINO_BIN` pointing at any
# `cupertino` binary:
#
#   scripts/check-canonical-db-shape.sh
#   CUPERTINO_BIN=/opt/homebrew/bin/cupertino scripts/check-canonical-db-shape.sh
#
# Exit codes:
#   0   DB shape matches canonical bundle (framework + doc counts above
#       the established floor)
#   1   DB shape below floor — corrupt or partial bundle; restore via
#       `cupertino setup` before treating any "no results" report as a
#       real bug
#   2   invocation error (binary not found, list-frameworks didn't run)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Honour CUPERTINO_BIN env override; otherwise prefer the brew bottle
# (the canonical user install), then fall back to the repo's debug build.
BIN="${CUPERTINO_BIN:-}"
if [[ -z "$BIN" ]]; then
    if [[ -x /opt/homebrew/bin/cupertino ]]; then
        BIN=/opt/homebrew/bin/cupertino
    elif [[ -x "$REPO_ROOT/Packages/.build/debug/cupertino" ]]; then
        BIN="$REPO_ROOT/Packages/.build/debug/cupertino"
    fi
fi

if [[ -z "$BIN" || ! -x "$BIN" ]]; then
    echo "error: cupertino binary not found" >&2
    echo "       checked CUPERTINO_BIN, /opt/homebrew/bin/cupertino, Packages/.build/debug/cupertino" >&2
    echo "       set CUPERTINO_BIN to your install, or run \`cd Packages && swift build\` first" >&2
    exit 2
fi

# Canonical-bundle floor. The v1.0.x / v1.1.x bundles ship at 420
# frameworks / 285,735 documents (per the v1.0.2 release notes). The
# floor below is conservative — anything significantly above represents
# a healthy bundle. We deliberately don't pin the exact count because
# each release re-indexes the corpus and the numbers shift; the floor
# is what distinguishes "canonical bundle present" from "corrupt /
# partial DB".
#
# Empirically observed shapes during the 2026-05-17 false-positive
# triage:
#   - Canonical v1.0.2 bundle: 420 frameworks, 285,735 docs
#   - Mid-corruption partial:   37 frameworks,  21,701 docs (1/11 of
#                                                              canonical)
# The floor sits well above the corruption shape and well below any
# realistic shipped bundle.
MIN_FRAMEWORKS=300
MIN_DOCS=200000

# Header from `cupertino list-frameworks` looks like:
#   Available Frameworks (420 total, 285735 documents):
HEADER=$("$BIN" list-frameworks 2>/dev/null | head -1 || true)

if [[ -z "$HEADER" ]]; then
    echo "❌ cupertino list-frameworks produced no output" >&2
    echo "   binary: $BIN" >&2
    exit 2
fi

# Parse `(<frameworks> total, <docs> documents)`.
if [[ "$HEADER" =~ \(([0-9]+)\ total,\ ([0-9]+)\ documents\) ]]; then
    FRAMEWORK_COUNT="${BASH_REMATCH[1]}"
    DOC_COUNT="${BASH_REMATCH[2]}"
else
    echo "❌ list-frameworks header didn't match expected shape:" >&2
    echo "   '$HEADER'" >&2
    echo "   expected: 'Available Frameworks (<N> total, <M> documents):'" >&2
    exit 2
fi

# Verdict.
if (( FRAMEWORK_COUNT >= MIN_FRAMEWORKS )) && (( DOC_COUNT >= MIN_DOCS )); then
    echo "✅ canonical DB shape OK"
    echo "   binary:     $BIN"
    echo "   frameworks: $FRAMEWORK_COUNT  (floor: $MIN_FRAMEWORKS)"
    echo "   documents:  $DOC_COUNT  (floor: $MIN_DOCS)"
    exit 0
else
    echo "❌ DB shape below canonical floor — corrupt or partial bundle"
    echo "   binary:     $BIN"
    echo "   frameworks: $FRAMEWORK_COUNT  (floor: $MIN_FRAMEWORKS)"
    echo "   documents:  $DOC_COUNT  (floor: $MIN_DOCS)"
    echo ""
    echo "   Run \`cupertino setup\` to restore the canonical bundle"
    echo "   before treating any \"no results found\" / \"sparse coverage\""
    echo "   report as a real bug. Probing against a corrupt DB produces"
    echo "   false-positive reports that burn triage time." >&2
    exit 1
fi
