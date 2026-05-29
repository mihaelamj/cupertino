#!/usr/bin/env bash
#
# check-orphaned-sources.sh
#
# Fails if any .swift file under Packages/Sources or Packages/Tests is not
# compiled by any SwiftPM target. SwiftPM silently ignores source files that
# fall outside every target's resolved `path:`: such a file is compiled into
# nothing, so a test inside it never runs and never errors (swift test just
# reports "0 tests"). This guard closes that class of bug.
#
# Motivating instance (#1135 / #1125): OutputFormatAliasTests.swift was added
# at the Tests/CLICommandTests/ root. That directory has no target of its own;
# only its subfolders (DoctorTests / FetchTests / SaveTests / ServeTests) are
# testTargets via explicit path:. The file compiled into nothing and the suite
# never ran.
#
# Run from the repo root:
#   scripts/check-orphaned-sources.sh
#
# Exit codes:
#   0  every .swift under Sources/ + Tests/ is owned by a target
#   1  orphaned .swift file(s) found
#   2  invocation error (jq missing, or `swift package describe` failed)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/Packages"

command -v jq >/dev/null 2>&1 || {
    echo "error: jq not found (required to parse 'swift package describe')" >&2
    exit 2
}

# Prefer Xcode's toolchain on macOS (the PATH `swift` may be a swiftly build
# that can't parse the Xcode SDK); fall back to plain `swift` on Linux CI.
if command -v xcrun >/dev/null 2>&1; then
    SWIFT=(xcrun swift)
else
    SWIFT=(swift)
fi

describe=$("${SWIFT[@]}" package describe --type json 2>/dev/null) || {
    echo "error: 'swift package describe --type json' failed (manifest not resolvable?)" >&2
    exit 2
}

# Files SwiftPM actually compiles: each target's path + its resolved sources,
# relative to Packages/. Restrict to .swift.
spm_files=$(echo "$describe" \
    | jq -r '.targets[] | .path as $p | (.sources // [])[] | "\($p)/\(.)"' \
    | grep '\.swift$' \
    | sort -u)

# Every .swift on disk under the two source roots, relative to Packages/.
disk_files=$(find Sources Tests -name '*.swift' -type f | sed 's#^\./##' | sort -u)

# On disk but not seen by any target.
orphaned=$(comm -23 <(printf '%s\n' "$disk_files") <(printf '%s\n' "$spm_files") || true)

if [[ -z "$orphaned" ]]; then
    count=$(printf '%s\n' "$disk_files" | grep -c . || true)
    echo "✅ no orphaned sources: all $count .swift files under Sources/ + Tests/ are owned by a target"
    exit 0
fi

{
    echo "❌ orphaned .swift file(s) compiled by no SwiftPM target:"
    echo
    printf '%s\n' "$orphaned" | sed 's#^#   Packages/#'
    echo
    echo "Each file above is silently excluded from every target, so any tests"
    echo "in it never run (swift test reports 0 tests). Fix: move the file into a"
    echo "directory covered by some target's path:, or declare a target for its"
    echo "directory in Packages/Package.swift. See #1135."
} >&2
exit 1
