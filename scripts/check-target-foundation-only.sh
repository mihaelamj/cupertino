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
# the standalone-portable unit. Pull out (SearchAPI + SearchModels) into
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
    IndexerModels
    DistributionModels
    CleanupModels
    CoreSampleCodeModels
    RemoteSyncModels
    EnrichmentModels
    SearchSchema
    AvailabilityModels
    SearchStrategyHelpers
)

# Producers that have been audited + opt into the strict rule.
#
# Phase 2 of #536 (2026-05-15) opted in the original 6 `*Models`
# protocol-seam companions. The closures-to-Observer epic added 5 more
# `*Models` seams (IndexerModels, DistributionModels, CleanupModels,
# CoreSampleCodeModels, RemoteSyncModels), and #837 added
# EnrichmentModels for the postprocessor pipeline, bringing the total
# in this array to 12 (the 11 `*Models`-suffixed entries below + the
# unsuffixed CoreProtocols, which is grouped with the seams).
# All carry Foundation + foundation-tier + other `*Models` imports only;
# no actors with I/O, no URLSession, no FileManager.
# Phase 2a (#542) moved `Core.PackageIndexing.GitHubCanonicalizer` +
# `Core.PackageIndexing.ExclusionList` out of `CoreProtocols` before
# this opt-in.
#
# Phase 3 of #536 (2026-05-15) opted in 17 producer / feature targets
# at once. Each target was empirically verified standalone-portable via
# `scripts/check-target-portability.sh <Target>`: the script physically
# copies the target + its declared deps into a tmp repo and runs
# `xcrun swift build` against a fresh SwiftPM checkout. All 17 built
# green, confirming the Shared-layer absorption (#536 phases 1a-1d)
# automatically brought every producer into compliance with the
# foundation-only rule. PR #908 added AppleConstraintsKit as the 18th,
# bringing the producer block to 18 entries; AppleConstraintsKit's
# imports (`Foundation`, `SearchModels`) match the foundation-only
# allow-list trivially, but the portability test for it is queued, not
# run.
STRICT_PRODUCERS=(
    # Phase 2b-2f (#536): protocol-seam companions, foundation-only.
    CoreProtocols
    CrawlerModels
    CorePackageIndexingModels
    SearchModels
    SampleIndexModels
    ServicesModels

    # Closures-to-Observer epic: foundation-only seam target for
    # `Indexer.*Service` Request / Outcome / Event value types + the
    # three `*Service.EventObserving` protocols. Pattern A namespace
    # anchor (lives in this seam, producer extends it).
    IndexerModels

    # Closures-to-Observer epic: foundation-only seam target for
    # `Distribution.*` Request / Outcome / Event / Progress value types
    # + `SetupService.EventObserving` / `ArtifactDownloader.ProgressObserving`
    # / `ArtifactExtractor.TickObserving` protocols. Pattern A
    # namespace anchor.
    DistributionModels

    # Closures-to-Observer epic: foundation-only seam target for the
    # `Sample.Cleanup.CleanerProgressObserving` protocol. Payload is
    # `Shared.Models.CleanupProgress` from foundation-tier
    # SharedConstants. Flat-named (the producer `Sample.Cleanup.Cleaner`
    # is an actor, can't be extended from outside).
    CleanupModels

    # Closures-to-Observer epic: foundation-only seam target for
    # `Sample.Core.GitHubFetcherProgress` value type +
    # `Sample.Core.GitHubFetcherProgressObserving` Observer protocol.
    # Flat-named (the producer `Sample.Core.GitHubFetcher` is a public
    # final class, can't be extended cleanly from outside; the
    # `Sample.Core` enum namespace itself lives in SharedConstants and
    # is extended here).
    CoreSampleCodeModels

    # Closures-to-Observer epic: foundation-only seam target for the
    # `RemoteSync` namespace anchor, the `RemoteSync.Progress` /
    # `IndexState` / `IndexerResult` / `IndexerError` value types, and
    # the `DocumentIndexing` Strategy + `IndexerProgressObserving` /
    # `IndexerDocumentObserving` Observer protocols that drive
    # `RemoteSync.Indexer.run`. Flat-named because the producer
    # `RemoteSync.Indexer` is a public actor in the `RemoteSync` target
    # (can't be extended from this foundation-only seam).
    RemoteSyncModels

    # Postprocessor pipeline seam (#837): foundation-only target carrying
    # the EnrichmentPass protocol + value types every enrichment pass
    # emits. Audited alongside the other *Models seams.
    EnrichmentModels

    # Search-schema constants target (#898 sub-PR A): foundation-only
    # target carrying the DDL SQL strings + the
    # `Search.Schema.currentVersion` Int32. Executor methods on
    # Search.Index that consume these constants stay in the Search
    # target until #898 sub-PR E (SearchSQLite extraction).
    SearchSchema

    # Phase 3 (#536): producer / feature targets.
    #
    # `Enrichment` graduated in #906: the 6 sibling passes now take
    # `any Search.IndexWriter` / `any Search.PackageWriter` /
    # `any Sample.Index.Writer` via init injection, so the target
    # imports only SearchModels + SampleIndexModels + EnrichmentModels
    # + SharedConstants and audits clean against the foundation-only
    # allow-list.
    #
    # `SearchSQLite` graduated in #898F (the domain-types lift follow-up
    # to #898 sub-PR E): `Search.Source`, `Search.QueryIntent`,
    # `detectQueryIntent`, and `Search.SourceProperties` moved out of
    # `Search.ComposableResult.swift` into `SearchModels`;
    # `Search.SourceDefinition` + `Search.SourceRegistry` whole-file
    # moved to `SearchModels`; `Search.SearchResult` (SampleCodeResult +
    # PackageResult), `DocKind`/`Classify`, `Search.SourceIndexer`
    # protocol + indexer concretes + `Search.IndexerRegistry`, and
    # `DocLinkRewriter` whole-file moved to `SearchSQLite` (no external
    # consumers in the SearchAPI target). The target now imports only
    # foundation + Models + SQLite3 and audits clean.

    # Producer (#759): AppleConstraintsKit ships `Search.StaticConstraintsLookup`
    # conformance built from `swift symbolgraph-extract` output. Foundation
    # + SearchModels only; matches foundation-only allow-list trivially.
    # Opted into the audit by PR #908 (2026-05-22).
    AppleConstraintsKit

    Availability
    Cleanup
    Core
    CoreJSONParser
    CorePackageIndexing
    CoreSampleCode
    Crawler
    Distribution
    Enrichment
    Indexer
    Ingest
    Logging
    MCPSupport
    RemoteSync
    SampleIndex
    SampleIndexSQLite
    SearchAPI
    SearchSQLite
    AppleDocsSource
    HIGSource
    SampleCodeSource
    SwiftEvolutionSource
    SwiftOrgSource
    AppleArchiveSource
    AppleConstraintsPass
    HierarchyPass
    PackagesAppleConstraintsPass
    PackagesAppleImportsPass
    SamplesAppleConstraintsPass
    SynonymsPass
    CrawlerWebKit
    SearchToolProvider
    Services
)

# WebKit-companion siblings that legitimately import their parent
# producer to extend its types (Core.JSONParser.RefResolver.TitleFetcher
# conformance, Sample.Core.Downloader namespace). Same exclusion shape
# Enrichment had pre-#906. Tracked separately by check-package-purity.sh
# FORBIDDEN_MODULES (no consumer target may import them).
#   - CoreJSONParserWebKit (#904)
#   - CoreSampleCodeWebKit (#904)

# Grandfathered: producers still under the legacy contract (enforced
# by scripts/check-package-purity.sh, not this script). Stayed empty
# after #536 phase 3 and remains empty post-#906: the per-pass split
# (sub-PRs B-G, closed 2026-05-23) lifted every pass out of the
# Enrichment producer into its own foundation-tier sibling
# (`AppleConstraintsPass`, `HierarchyPass`, `PackagesAppleConstraintsPass`,
# `PackagesAppleImportsPass`, `SamplesAppleConstraintsPass`,
# `SynonymsPass`); each opted into STRICT_PRODUCERS directly. The
# `Enrichment` package now retains only `LiveRunner` and is itself in
# STRICT_PRODUCERS via the #906 protocol-rewire. There is no longer a
# producer with deferred foundation-only opt-in. This array stays
# empty until a future producer needs that deferral.
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
