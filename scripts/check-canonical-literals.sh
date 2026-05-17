#!/usr/bin/env bash
# check-canonical-literals.sh — guard against duplicate-constant smells
#
# Stage D of the ironclad-sweep methodology (#101 class-of-bug regression
# lock). When the same load-bearing literal appears in multiple Sources/
# files independently, future renames silently desync. This script
# enforces that each registered literal lives in exactly ONE source
# location.
#
# Each entry in the canonical-literal registry below names:
#   - The literal (e.g. "selected-archive-guides.json")
#   - The expected single source location (file path + grep anchor)
#   - The issue / PR that defines the invariant
#
# Exit codes:
#   0 — every literal appears in exactly one location
#   1 — at least one literal appears in 0 or 2+ locations
#   2 — invocation error
#
# Run from repo root: ./scripts/check-canonical-literals.sh
#
# Integration: invoked by .github/workflows/lint.yml as a pre-commit
# guard. Developers can also run locally before opening a PR.

set -uo pipefail

# Don't use `set -e` — we want to keep going after a per-literal failure
# so the user sees every violation in one run.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || {
    echo "❌ failed to cd to repo root" >&2
    exit 2
}

EXIT_CODE=0
FAILURES=0

# Print to stderr to avoid polluting any downstream pipeline output.
log() { printf '%s\n' "$*" >&2; }

# Per-literal check.
#
# Args:
#   $1 literal      — the string that must appear in exactly one Sources/ file
#   $2 expected     — path:line-pattern expected to contain the literal
#   $3 issue        — issue / PR reference for the invariant
check_literal() {
    local literal="$1"
    local expected="$2"
    local issue="$3"

    # Count matches across Sources/ (excludes Resources/Embedded which carry
    # JSON catalogs by design — those use the literals but only as DATA,
    # not as code-level constants).
    local matches
    matches=$(grep -rln --include='*.swift' \
        --exclude-dir='Resources/Embedded' \
        -- "$literal" Packages/Sources/ 2>/dev/null || true)
    local count
    count=$(printf '%s' "$matches" | grep -c . || true)

    case "$count" in
        0)
            log "❌ #$issue: literal \"$literal\" found in ZERO Sources/ files (expected: $expected)"
            FAILURES=$((FAILURES + 1))
            EXIT_CODE=1
            ;;
        1)
            # Verify the one match is in the expected location.
            if grep -F -q -- "$expected" <<<"$matches"; then
                # Pass.
                :
            else
                log "❌ #$issue: literal \"$literal\" found in WRONG location"
                log "   expected: $expected"
                log "   actual:   $matches"
                FAILURES=$((FAILURES + 1))
                EXIT_CODE=1
            fi
            ;;
        *)
            log "❌ #$issue: literal \"$literal\" found in $count Sources/ files (expected: 1, at $expected)"
            log "$matches" | while IFS= read -r f; do log "   — $f"; done
            log "   This is exactly the #101 duplicate-constant smell — wire all callers"
            log "   through a single canonical accessor (typically Shared.Paths or"
            log "   Shared.Constants.FileName)."
            FAILURES=$((FAILURES + 1))
            EXIT_CODE=1
            ;;
    esac
}

# MARK: - Canonical literal registry

# #101 — user-archive-selections file. Single source of truth is
# `Shared.Constants.FileName.userArchiveSelections`. Both
# `Crawler.ArchiveGuideCatalog` and `TUI/Models/ArchiveGuidesCatalog`
# consume `Shared.Paths.userArchiveSelectionsFile` which reads the
# constant.
check_literal \
    "selected-archive-guides.json" \
    "Packages/Sources/Shared/Constants/Shared.Constants.swift" \
    "101"

# MARK: - Summary

if [ "$EXIT_CODE" -eq 0 ]; then
    log "✅ canonical literals OK — every registered literal appears in exactly one Sources/ file"
else
    log ""
    log "❌ $FAILURES canonical-literal violation(s) — Stage D regression locks tripped"
    log ""
    log "Pre-#101, this script would have caught the duplicate \"selected-archive-guides.json\""
    log "literal between Crawler/Crawler.ArchiveGuideCatalog.swift and"
    log "TUI/Models/ArchiveGuidesCatalog.swift before it shipped. The Stage A closure"
    log "replay (docs/audits/closure-replay-2026-05-17.md) reopened #101 specifically"
    log "for this duplicate. Stage D's purpose is to prevent the next one."
fi

exit "$EXIT_CODE"
