#!/usr/bin/env bash
#
# check-import-contract-coverage.sh
#
# #975 / per-package-import-contract.md enforcement.
# Verifies that every SPM target declared in `Packages/Package.swift`
# has a corresponding row in `docs/package-import-contract.md`.
# Silent drift between the manifest and the contract is the class
# of bug that landed 9 missing rows by 2026-05-23 (audit:
# `docs/audits/2026-05-23-rule-canon-audit.md` HIGH-2).
#
# Test targets are deliberately excluded: they exist for tests only
# and don't carry a production import contract. Composition-root
# binaries (`CLI`, `TUI`, `MockAIAgent`, `ReleaseTool`, `ConstraintsGen`)
# are also excluded — they import the universe by design.
#
# Run from the repo root:
#
#   scripts/check-import-contract-coverage.sh
#
# Exit codes:
#   0   every declared production target has a contract row
#   1   at least one declared target has no contract row
#   2   invocation error (wrong cwd, files missing)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PACKAGE_MANIFEST="Packages/Package.swift"
CONTRACT_DOC="docs/package-import-contract.md"

if [ ! -f "$PACKAGE_MANIFEST" ]; then
    echo "error: $PACKAGE_MANIFEST not found, run from repo root" >&2
    exit 2
fi
if [ ! -f "$CONTRACT_DOC" ]; then
    echo "error: $CONTRACT_DOC not found, run from repo root" >&2
    exit 2
fi

# Composition-root binaries + test targets we intentionally exclude.
# These are binary entry points or test-only helpers; the contract
# describes producer + foundation-only library targets only.
EXCLUDE=(
    CLI
    TUI
    MockAIAgent
    ReleaseTool
    ConstraintsGen
    TestSupport
)

# Extract every `Target.target(name: "X")` and `Target.executableTarget(name: "X")`
# declaration from the manifest. Excludes test targets (they don't
# show up in this regex since they use Target.testTarget).
declared=$(grep -E "Target\.(target|executableTarget)\(" "$PACKAGE_MANIFEST" -A2 \
    | grep -oE 'name: "[A-Z][^"]+"' \
    | sed 's/name: "//;s/"//' \
    | sort -u)

# Extract every contract row's target name (the first backtick-quoted
# identifier on a `| `Foo` |` line). The contract rows look like:
#   | `TargetName` | allowed imports | current state |
contract=$(grep -E "^\| \`[A-Z][A-Za-z]+\`" "$CONTRACT_DOC" \
    | grep -oE '^\| `[A-Z][A-Za-z]+`' \
    | grep -oE '`[A-Z][A-Za-z]+`' \
    | tr -d '`' \
    | sort -u)

# Compute drift: declared - excluded - contract.
declared_file=$(mktemp)
excluded_file=$(mktemp)
contract_file=$(mktemp)
trap 'rm -f "$declared_file" "$excluded_file" "$contract_file"' EXIT

printf '%s\n' "$declared" > "$declared_file"
printf '%s\n' "${EXCLUDE[@]}" | sort -u > "$excluded_file"
printf '%s\n' "$contract" > "$contract_file"

# Targets that are declared + not in the exclude list.
production=$(comm -23 "$declared_file" "$excluded_file")
production_file=$(mktemp)
trap 'rm -f "$declared_file" "$excluded_file" "$contract_file" "$production_file"' EXIT
printf '%s\n' "$production" > "$production_file"

# Production targets missing from the contract.
missing=$(comm -23 "$production_file" "$contract_file")

declared_count=$(printf '%s\n' "$declared" | grep -c . || true)
production_count=$(printf '%s\n' "$production" | grep -c . || true)
contract_count=$(printf '%s\n' "$contract" | grep -c . || true)

if [ -z "$missing" ]; then
    echo "✅ Import-contract coverage: every declared production target has a row in $CONTRACT_DOC"
    echo "   declared targets: $declared_count"
    echo "   excluded (binaries + TestSupport): ${#EXCLUDE[@]}"
    echo "   production targets requiring rows: $production_count"
    echo "   contract rows: $contract_count"
    exit 0
fi

missing_count=$(printf '%s\n' "$missing" | grep -c . || true)
{
    echo "❌ Import-contract coverage: $missing_count declared production target(s) have no row in $CONTRACT_DOC"
    echo
    echo "Missing rows:"
    printf '%s\n' "$missing" | sed 's/^/  - /'
    echo
    echo "Fix: append a contract row per target in $CONTRACT_DOC. Each row carries:"
    echo "   | \`TargetName\` | <allowed imports> | <current state with audit citation> |"
    echo
    echo "If a target is intentionally exempt (binary, test helper), add it to the EXCLUDE array in this script."
} >&2

exit 1
