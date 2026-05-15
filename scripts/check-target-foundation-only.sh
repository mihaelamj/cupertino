#!/usr/bin/env bash
#
# check-target-foundation-only.sh
#
# Epic #536 guard: every producer SPM target listed in STRICT_PRODUCERS
# below imports only:
#
#   - External primitives (Foundation, OSLog, SQLite3, SwiftSyntax,
#     SwiftParser, ArgumentParser, Testing, WebKit, AppKit, CryptoKit,
#     FoundationNetworking, system frameworks)
#   - Foundation-only utility tier (SharedConstants, LoggingModels,
#     Resources, Diagnostics, ASTIndexer, MCPCore, MCPSharedTools)
#   - Per-producer protocol seams (*Models companions)
#
# The principle: each producer plus its protocol-seam companion(s) is
# the standalone-portable unit. Pull out (Search + SearchModels) into
# a fresh repo with the foundation-tier deps and it builds against
# external SwiftPM dependencies alone.
#
# Rationale + design references:
#   - GoF (1994) Strategy p. 315 / Factory Method p. 107: program to
#     an interface, place the interface in a foundation-only seam.
#   - Apple SwiftNIO: NIOCore (foundation-only protocols) + NIOPosix
#     (concrete impl). Same shape as LoggingModels + Logging in
#     cupertino, and the same shape applied per-producer here.
#   - Apple swift-log (SSWG): foundation-only Logging target carrying
#     the LogHandler protocol + pure-Swift defaults; OS-coupled
#     handlers in entirely separate packages.
#   - Point-Free swift-dependencies: protocol-or-struct interface +
#     live/preview/test conformances registered via DependencyKey;
#     orthogonal to where the interface lives, compatible with our
#     choice.
#   - Cupertino user principle (2026-05-15): "no singletons, only
#     dependencies"; "dependencies all the way, not using other
#     packages, protocols instead"; "every package can be pulled out
#     of monorepo anytime, every one, anytime."
#
# Run from the repo root:
#
#   scripts/check-target-foundation-only.sh
#
# Exit codes:
#   0   every STRICT_PRODUCERS target imports only allowed modules
#   1   at least one forbidden import found (details on stderr)
#   2   invocation error (wrong cwd, sources dir missing)
#
# Phase 0 of #536 ships this script with STRICT_PRODUCERS empty —
# every producer is grandfathered out by default. Each subsequent PR
# in phase 3 audits one producer's imports, lands the cleanup, then
# adds it to STRICT_PRODUCERS to lock in the rule.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SOURCES_DIR="Packages/Sources"
if [ ! -d "$SOURCES_DIR" ]; then
    echo "error: $SOURCES_DIR not found — run from repo root" >&2
    exit 2
fi

# External primitives + foundation-tier system frameworks.
# These are always allowed for any target.
EXTERNAL_PRIMITIVES=(
    Foundation
    FoundationNetworking
    FoundationEssentials
    os
    OSLog
    Combine
    SwiftSyntax
    SwiftParser
    SwiftSyntaxBuilder
    SwiftSyntaxMacros
    SwiftDiagnostics
    SwiftOperators
    SwiftCompilerPlugin
    SQLite3
    CryptoKit
    Crypto
    WebKit
    AppKit
    UIKit
    SwiftUI
    Combine
    Network
    CoreFoundation
    CoreServices
    System
    Darwin
    ArgumentParser
    Testing
    XCTest
)

# Foundation-only Cupertino utility tier — small targets that are
# themselves foundation-only by construction. Allowed for any
# producer.
FOUNDATION_TIER=(
    SharedConstants
    LoggingModels
    Resources
    Diagnostics
    ASTIndexer
    MCPCore
    MCPSharedTools
)

# Producer protocol-seam companions (the *Models targets). Each
# carries protocols + value types for one producer. Foundation-only
# by contract. Allowed for any consumer that needs the seams.
MODELS_TARGETS=(
    CoreProtocols
    CrawlerModels
    CorePackageIndexingModels
    SearchModels
    SampleIndexModels
    ServicesModels
)

# Producers that have been audited + opt into the strict rule.
#
# Phase 2 of #536 (2026-05-15) opted in the 6 `*Models` protocol-seam
# companions. All carry Foundation + foundation-tier + other *Models
# imports only — no actors with I/O, no URLSession, no FileManager.
# Phase 2a (#542) moved `Core.PackageIndexing.GitHubCanonicalizer` +
# `Core.PackageIndexing.ExclusionList` out of `CoreProtocols` before
# this opt-in.
#
# Phase 3 of #536 (2026-05-15) opts in all 17 producer / feature
# targets at once. Each target was empirically verified standalone-
# portable via `scripts/check-target-portability.sh <Target>` — the
# script physically copies the target + its declared deps into a tmp
# repo and runs `xcrun swift build` against a fresh SwiftPM checkout.
# All 17 built green, confirming the Shared-layer absorption (#536
# phases 1a-1d) automatically brought every producer into compliance
# with the foundation-only rule.
STRICT_PRODUCERS=(
    # Phase 2b-2f (#536): protocol-seam companions, foundation-only.
    CoreProtocols
    CrawlerModels
    CorePackageIndexingModels
    SearchModels
    SampleIndexModels
    ServicesModels

    # Phase 3 (#536): producer / feature targets.
    Availability
    Cleanup
    Core
    CoreJSONParser
    CorePackageIndexing
    CoreSampleCode
    Crawler
    Distribution
    Indexer
    Ingest
    Logging
    MCPSupport
    RemoteSync
    SampleIndex
    Search
    SearchToolProvider
    Services
)

# Grandfathered: producers still under the legacy contract (enforced
# by scripts/check-package-purity.sh, not this script). Empty after
# phase 3 — every producer is now strict.
GRANDFATHERED_TARGETS=(
)

is_in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$needle" = "$item" ]; then
            return 0
        fi
    done
    return 1
}

# Build the global allow-list: external + foundation tier + all *Models.
# Producer's own *Models is allowed; other producers' *Models also
# allowed (the everliv / SwiftNIO pattern: any consumer may import
# any foundation-only protocol seam).
ALLOWED_GLOBAL=(
    "${EXTERNAL_PRIMITIVES[@]}"
    "${FOUNDATION_TIER[@]}"
    "${MODELS_TARGETS[@]}"
)

violations=0
violation_lines=()

# Override map for targets whose source folder lives under a parent
# folder rather than at `Sources/<Target>/`. Mirrors the `path:` field
# in `Package.swift` for these targets. Keep in sync if more targets
# are nested.
target_source_path() {
    case "$1" in
        CoreJSONParser)       echo "$SOURCES_DIR/Core/JSONParser" ;;
        CorePackageIndexing)  echo "$SOURCES_DIR/Core/PackageIndexing" ;;
        MCPCore)              echo "$SOURCES_DIR/MCP" ;;
        MCPClient)            echo "$SOURCES_DIR/MCP/Client" ;;
        MCPSharedTools)       echo "$SOURCES_DIR/MCP/SharedTools" ;;
        MCPSupport)           echo "$SOURCES_DIR/MCP/Support" ;;
        *)                    echo "$SOURCES_DIR/$1" ;;
    esac
}

# For each STRICT_PRODUCERS target, walk its source files and confirm
# every import is in the allow list. Use `+` expansion so an empty
# array doesn't trip `set -u`.
for target in ${STRICT_PRODUCERS[@]+"${STRICT_PRODUCERS[@]}"}; do
    target_dir="$(target_source_path "$target")"
    if [ ! -d "$target_dir" ]; then
        echo "error: STRICT_PRODUCERS lists $target but $target_dir doesn't exist" >&2
        exit 2
    fi

    # Collect every top-of-file import from this target's .swift files.
    # Strip `@testable` prefix, `@_exported` prefix, and trailing
    # `.SubModule` qualifiers; we care about the top-level module name.
    while IFS= read -r line; do
        # line format: "<file>:<lineno>:import <Module>" or "<file>:<lineno>:@testable import <Module>"
        # Extract the module name (the token after `import`).
        module="$(echo "$line" | sed -E 's/^.*:[0-9]+:[[:space:]]*(@_exported[[:space:]]+|@testable[[:space:]]+)?import[[:space:]]+([A-Za-z0-9_]+).*/\2/')"
        # Skip lines that didn't parse to a clean module name.
        if [ -z "$module" ] || [ "$module" = "$line" ]; then
            continue
        fi
        if ! is_in_list "$module" "${ALLOWED_GLOBAL[@]}"; then
            violation_lines+=("$target: $line")
            violations=$((violations + 1))
        fi
    done < <(grep -rEn '^[[:space:]]*(@_exported[[:space:]]+|@testable[[:space:]]+)?import[[:space:]]+[A-Za-z0-9_]+' "$target_dir" --include='*.swift' 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
    echo "❌ Foundation-only check failed: $violations forbidden import(s)." >&2
    echo "" >&2
    echo "A strict producer target imported a module outside its foundation-only allow-list:" >&2
    echo "  external primitives: ${EXTERNAL_PRIMITIVES[*]}" >&2
    echo "  foundation tier:     ${FOUNDATION_TIER[*]}" >&2
    echo "  *Models seams:       ${MODELS_TARGETS[*]}" >&2
    echo "" >&2
    echo "Either route the dependency through a protocol seam in a *Models target," >&2
    echo "or move the type into the foundation tier (e.g. SharedConstants)." >&2
    echo "" >&2
    echo "Violations:" >&2
    for line in "${violation_lines[@]}"; do
        echo "  $line" >&2
    done
    echo "" >&2
    echo "See #536 for the rationale." >&2
    exit 1
fi

strict_count="${#STRICT_PRODUCERS[@]}"
grandfathered_count="${#GRANDFATHERED_TARGETS[@]}"
if [ "$strict_count" -eq 0 ]; then
    echo "✅ Foundation-only check passed — STRICT_PRODUCERS is empty (phase 0)."
    echo "   $grandfathered_count producer(s) grandfathered, awaiting per-target audit."
else
    echo "✅ Foundation-only check passed — $strict_count producer(s) opted into the strict rule:"
    for t in ${STRICT_PRODUCERS[@]+"${STRICT_PRODUCERS[@]}"}; do
        echo "   - $t"
    done
    if [ "$grandfathered_count" -gt 0 ]; then
        echo "   $grandfathered_count producer(s) still grandfathered. Migrate them through phase 3 of #536."
    fi
fi
