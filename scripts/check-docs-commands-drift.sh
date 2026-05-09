#!/usr/bin/env bash
#
# check-docs-commands-drift.sh
#
# Verifies that docs/commands/ matches the cupertino binary's actual --help
# surface. Catches the drift that builds up between releases:
#
#   • CLI options that have no corresponding option .md file
#   • option .md files for flags that no longer exist in --help
#   • enum-value drift (--type, --source values added or renamed)
#
# Run from the repo root:
#
#   scripts/check-docs-commands-drift.sh
#
# Exit codes:
#   0   docs match the binary surface
#   1   drift detected (details printed to stderr)
#   2   invocation error (binary not built, env mismatch)
#
# Background: see commit 8a7c066 for the structural-drift fixup that
# motivated this check, and 12cd5fb for the deeper content-shape drift
# this script does NOT cover (JSON shapes, sample output formatting).
# Those need a richer harness; this script catches the cheap and common
# cases.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BIN="${CUPERTINO_BIN:-Packages/.build/debug/cupertino}"

if [[ ! -x "$BIN" ]]; then
    echo "error: cupertino binary not found at $BIN" >&2
    echo "       run \`cd Packages && swift build\` first, or set CUPERTINO_BIN" >&2
    exit 2
fi

# Visible + hidden subcommands. Keep in sync with the CLI's CommandConfiguration
# subcommand list (see Packages/Sources/CLI/CupertinoMain.swift).
COMMANDS=(
    setup fetch save serve search read
    list-frameworks list-samples
    read-sample read-sample-file
    doctor cleanup resolve-refs
    package-search   # hidden
)

# --- structural drift: option .md files vs --help OPTIONS section ---------

total_missing=0
total_orphan=0
drift_lines=()

for cmd in "${COMMANDS[@]}"; do
    help=$("$BIN" "$cmd" --help 2>&1)

    # Parse only the OPTIONS: block (not the OVERVIEW prose) so we don't pick
    # up flag-shaped strings inside descriptions.
    bin_opts=$(echo "$help" \
        | awk '/^OPTIONS:/,/^[A-Z]+:/ { if (/^OPTIONS:/) next; if (/^[A-Z]+:/ && !/^OPTIONS:/) exit; print }' \
        | grep -oE -- '--[a-z][a-z0-9-]+' \
        | sort -u \
        | grep -vE '^--(help|version)$' || true)

    # Some commands have OPTIONS as the last block (no terminator).
    if [[ -z "$bin_opts" ]]; then
        bin_opts=$(echo "$help" \
            | awk '/^OPTIONS:/,0' \
            | grep -oE -- '--[a-z][a-z0-9-]+' \
            | sort -u \
            | grep -vE '^--(help|version)$' || true)
    fi

    # Enumerate documented options. `default.md` is excluded (it documents
    # the behavior of running the command with no flags, not a real flag).
    if [[ -d "docs/commands/$cmd/option (--)" ]]; then
        doc_opts=$(ls "docs/commands/$cmd/option (--)/" 2>/dev/null \
            | grep '\.md$' \
            | sed 's/\.md$//' \
            | grep -v '^default$' \
            | sort -u \
            | sed 's/^/--/' || true)
    else
        doc_opts=""
    fi

    bin_file=$(mktemp)
    doc_file=$(mktemp)
    { printf '%s\n' "$bin_opts" | grep -v '^$' || true; } > "$bin_file"
    { printf '%s\n' "$doc_opts" | grep -v '^$' || true; } > "$doc_file"

    missing=$(comm -23 "$bin_file" "$doc_file")
    orphan=$(comm -13 "$bin_file" "$doc_file")

    if [[ -n "$missing" ]]; then
        m_count=$(echo "$missing" | wc -l | tr -d ' ')
        total_missing=$((total_missing + m_count))
        while IFS= read -r flag; do
            drift_lines+=("MISSING DOC  $cmd  $flag  →  docs/commands/$cmd/option (--)/${flag#--}.md")
        done <<< "$missing"
    fi
    if [[ -n "$orphan" ]]; then
        o_count=$(echo "$orphan" | wc -l | tr -d ' ')
        total_orphan=$((total_orphan + o_count))
        while IFS= read -r flag; do
            drift_lines+=("ORPHAN DOC   $cmd  $flag  →  docs/commands/$cmd/option (--)/${flag#--}.md")
        done <<< "$orphan"
    fi

    rm -f "$bin_file" "$doc_file"
done

# --- enum-value drift: --type and --source values vs (=value) subdirs -----

# Hardcoded expected enum values per (command, option). Update in lockstep
# with the Swift enum definitions in:
#   • Sources/CLI/Commands/FetchCommand.swift  (FetchType)
#   • Sources/CLI/Commands/SearchCommand.swift (SearchSource)
# A new enum value added in the CLI without updating BOTH this script AND
# docs/commands/<cmd>/option (--)/<opt> (=value)/<value>.md will trip the
# check. Hardcoding is more reliable than parsing ArgumentParser's
# error-message format, which intermixes value names with parenthetical
# descriptions.

declare -a enum_drift_lines

check_enum_explicit() {
    local cmd="$1"
    local opt="$2"
    shift 2
    local expected_values=("$@")
    local enum_dir="docs/commands/$cmd/option (--)/$opt (=value)"
    [[ -d "$enum_dir" ]] || return 0

    local doc_values
    doc_values=$(ls "$enum_dir" 2>/dev/null \
        | grep '\.md$' \
        | sed 's/\.md$//' \
        | grep -v '^default$' \
        | sort -u || true)

    local b d
    b=$(mktemp); d=$(mktemp)
    printf '%s\n' "${expected_values[@]}" | sort -u > "$b"
    { printf '%s\n' "$doc_values" | grep -v '^$' || true; } > "$d"

    local missing orphan
    missing=$(comm -23 "$b" "$d")
    orphan=$(comm -13 "$b" "$d")

    if [[ -n "$missing" ]]; then
        while IFS= read -r v; do
            enum_drift_lines+=("MISSING VALUE  $cmd --$opt  $v  →  $enum_dir/$v.md")
            total_missing=$((total_missing + 1))
        done <<< "$missing"
    fi
    if [[ -n "$orphan" ]]; then
        while IFS= read -r v; do
            enum_drift_lines+=("ORPHAN VALUE   $cmd --$opt  $v  →  $enum_dir/$v.md")
            total_orphan=$((total_orphan + 1))
        done <<< "$orphan"
    fi

    rm -f "$b" "$d"
}

check_enum_explicit fetch  type    docs swift evolution packages code samples archive hig availability all
check_enum_explicit search source  apple-docs samples hig apple-archive swift-evolution swift-org swift-book packages all

# --- report ---------------------------------------------------------------

if [[ ${#drift_lines[@]} -eq 0 && ${#enum_drift_lines[@]} -eq 0 ]]; then
    echo "✅ docs/commands/ matches binary --help surface"
    echo "   commands checked:        ${#COMMANDS[@]}"
    echo "   missing / orphan / enum: 0 / 0 / 0"
    exit 0
fi

{
    echo "❌ docs/commands/ has drifted from the binary --help surface"
    echo
    echo "   commands checked:    ${#COMMANDS[@]}"
    echo "   total missing docs:  $total_missing  (CLI flag has no .md)"
    echo "   total orphan docs:   $total_orphan  (.md exists, no CLI flag)"
    echo
    if [[ ${#drift_lines[@]} -gt 0 ]]; then
        echo "   structural drift:"
        for line in "${drift_lines[@]}"; do
            echo "     $line"
        done
        echo
    fi
    if [[ ${#enum_drift_lines[@]} -gt 0 ]]; then
        echo "   enum-value drift:"
        for line in "${enum_drift_lines[@]}"; do
            echo "     $line"
        done
        echo
    fi
    echo "Fix: author the missing .md files (matching the format used by the"
    echo "rest of docs/commands/), \`git rm\` the orphans, \`git mv\` renamed"
    echo "enum values. Re-run this script to confirm."
} >&2

exit 1
