#!/usr/bin/env bash
#
# check-package-purity.sh
#
# Phase B guardrail (epic #503): every non-binary, non-test SPM source
# target under Packages/Sources/<Target>/ may import only:
#
#   - Foundation
#   - the Shared kernel (SharedConstants, SharedCore, SharedUtils,
#     SharedModels, SharedConfiguration)
#   - cross-cutting infra (Logging, MCPCore)
#   - its own *Models companion (or any *Models target — those are
#     foundation-only abstractions)
#   - other consumer / coordinator targets that don't own actors of
#     a different concern (Services, SearchToolProvider, MCPSupport,
#     MCPSharedTools, MCPClient)
#
# Forbidden: any direct import of a concrete-producer target — a
# target that owns actors, I/O, or external resources that belong to
# a different concern. Those imports are reserved for the composition
# root binaries (CLI, TUI) and the test composition roots
# (Packages/Tests/<X>Tests).
#
# Run from the repo root:
#
#   scripts/check-package-purity.sh
#
# Exit codes:
#   0   every consumer target stays inside the allowed surface
#   1   at least one forbidden import found (details printed to stderr)
#   2   invocation error (wrong cwd, sources dir missing)
#
# Background: see #503 (Phase B of the GoF protocol-DI refactor) and
# its closing PR for the architectural rationale. The principle is
# Robert C. Martin's Dependency Inversion (1996), restating GoF
# "Program to an interface, not an implementation." (1994 p. 18):
# consumers depend on abstractions, never on a concrete producer of
# a different concern.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SOURCES_DIR="Packages/Sources"
if [ ! -d "$SOURCES_DIR" ]; then
    echo "error: $SOURCES_DIR not found — run from repo root" >&2
    exit 2
fi

# Concrete-producer targets. Any import of these from a non-binary,
# non-test source target is a Phase B violation. Add new producers
# here when they ship.
#
# NOT on this list (and intentionally so):
#   ASTIndexer — pure SwiftSyntax wrapper, no actors, no I/O. Acts
#     as a shared kernel for AST parsing the same way SharedUtils
#     acts as a kernel for path resolution. Importing it is the
#     same as importing Foundation.
FORBIDDEN_MODULES=(
    AppleConstraintsKit
    Availability
    Cleanup
    Core
    CoreJSONParser
    CorePackageIndexing
    CoreSampleCode
    Crawler
    Diagnostics
    Distribution
    Enrichment
    Indexer
    Ingest
    RemoteSync
    SampleIndex
    SearchAPI
    SearchSQLite
    SampleIndexSQLite
    CrawlerWebKit
    CoreJSONParserWebKit
    CoreSampleCodeWebKit
)

# Targets that ARE composition roots; they may import any concrete.
# CLI and TUI ship as binaries. MockAIAgent and ReleaseTool are
# additional binary-like roots that need direct access to concretes.
# ConstraintsGen is the cupertino-constraints-gen executable (#759)
# that bundles AppleConstraintsKit for shipping the apple-constraints.json
# table; treated as a binary composition root for purity audit.
EXEMPT_TARGETS=(
    CLI
    TUI
    MockAIAgent
    ReleaseTool
    ConstraintsGen
    # Canonical production composition root: registers every
    # `<X>Source` provider. #536 lift 3 moved the GitHub-fetch wiring
    # here, so it injects `Sample.Core.LiveGitHubFetcherFactory` into
    # `SampleCodeSource` and legitimately imports the `CoreSampleCode`
    # concrete like the binary composition roots above.
    CupertinoComposition
    # WebKit-companion siblings (#904); each extends its parent
    # producer's types so it legitimately imports the parent. They are
    # themselves on FORBIDDEN_MODULES (no other consumer may import them);
    # only the composition root binaries link them.
    CoreJSONParserWebKit
    CoreSampleCodeWebKit
    # `SampleCodeSource` graduated out of this list in #536 lift 3: its
    # GitHub-fetch concrete is now reached through the
    # `Sample.Core.GitHubFetcherFactory` seam, wired at
    # CupertinoComposition. `PackagesSource` graduated out in #536 lift 5:
    # its `PackagesFetchStrategy` (the 3-stage Swift Package Index
    # pipeline) moved INTO the `CorePackageIndexing` producer and is now
    # reached through the `Search.PackageFetchStrategyFactory` seam,
    # injected at CupertinoComposition. The Crawler.<X> concretes for
    # HIG / Evolution / AppleArchive / AppleDocs were physically lifted
    # INTO their respective source targets, so those four never needed an
    # exemption. No per-source target imports a concrete producer anymore;
    # every `<X>Source` is now audited.
)

# Grandfathered targets — pre-existing leaks acknowledged here so
# the guard passes against the tree as it stands today. New imports
# from these targets still fail; the goal is to migrate each
# grandfathered target out of this list as its leaks are cleaned up.
#
# Notes (kept here for archaeology; both entries are no longer active):
#
# - `Enrichment` graduated out of this list in #906 once the 6 sibling
#   passes were rewired to take `any Search.IndexWriter` /
#   `any Search.PackageWriter` / `any Sample.Index.Writer` via init
#   injection. The target now imports only foundation-tier and Models
#   modules and opts directly into STRICT_PRODUCERS in
#   `check-target-foundation-only.sh`.
#
# - `SearchSQLite` graduated out of this list in #898F (the domain-types
#   lift follow-up to #898 sub-PR E). `Search.Source` + `Search.QueryIntent`
#   + `detectQueryIntent` + `Search.SourceProperties` were carved out of
#   `Search.ComposableResult.swift` into `SearchModels`;
#   `Search.SourceDefinition.swift` (carrying `SourceDefinition` +
#   `SourceRegistry` + extensions on Source/QueryIntent) whole-file moved
#   to `SearchModels`; `Search.SearchResult.swift`, `DocKind.swift`,
#   `Search.SourceIndexer.swift`, and `Search.Index.DocLinkRewriter.swift`
#   whole-file moved to `SearchSQLite`. SearchSQLite no longer
#   `import Search` and opts directly into STRICT_PRODUCERS.
GRANDFATHERED_TARGETS=()

is_exempt() {
    local target="$1"
    for exempt in "${EXEMPT_TARGETS[@]}"; do
        if [ "$target" = "$exempt" ]; then
            return 0
        fi
    done
    return 1
}

is_grandfathered() {
    local target="$1"
    for g in "${GRANDFATHERED_TARGETS[@]:-}"; do
        if [ "$target" = "$g" ]; then
            return 0
        fi
    done
    return 1
}

# Build the grep alternation pattern once. Matches the start of a
# line plus optional leading whitespace (Swift import statements at
# top-of-file have no indent, but be defensive).
PATTERN="^[[:space:]]*import[[:space:]]+($(IFS='|'; echo "${FORBIDDEN_MODULES[*]}"))[[:space:]]*$"

violations=0
violation_lines=()

# Walk every top-level directory under Packages/Sources/.
grandfathered_lines=()

while IFS= read -r -d '' target_dir; do
    target="$(basename "$target_dir")"
    if is_exempt "$target"; then
        continue
    fi
    # Skip the MCP umbrella — its sub-targets (Client, Core, Support,
    # SharedTools) are checked individually below.
    if [ "$target" = "MCP" ]; then
        continue
    fi
    # Family-folder umbrellas (post-#1042 folder-grouping restructure):
    # Sources/<Family>/ holds multiple sub-targets. Skip the umbrella
    # walk; the per-target walk below handles each sub-target by its
    # actual path: declaration. See `folder-grouping.md` § "Per-target
    # import audit must still work".
    case "$target" in
        Core|Search|Source|Enrichment|Distribution|Cleanup|Logging|Crawler|Availability|SampleIndex|RemoteSync|Services|Indexer)
            continue
            ;;
    esac

    # grep -rE returns non-zero when no match; capture and continue
    # rather than letting `set -e` kill us.
    set +e
    matches="$(grep -rEn "$PATTERN" "$target_dir" --include='*.swift' 2>/dev/null || true)"
    set -e
    if [ -n "$matches" ]; then
        if is_grandfathered "$target"; then
            while IFS= read -r line; do
                grandfathered_lines+=("$line")
            done <<< "$matches"
        else
            while IFS= read -r line; do
                violation_lines+=("$line")
                violations=$((violations + 1))
            done <<< "$matches"
        fi
    fi
done < <(find "$SOURCES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

# Family-folder sub-targets (post-#1042 restructure). Each entry is
# (subfolder, target-name); the target name is checked against
# EXEMPT_TARGETS + GRANDFATHERED_TARGETS just like the top-level walk.
declare -a FAMILY_SUBTARGETS=(
    "Sources/Core/Core:Core"
    "Sources/Core/Protocols:CoreProtocols"
    "Sources/Core/JSONParser:CoreJSONParser"
    "Sources/Core/JSONParser/WebKit:CoreJSONParserWebKit"
    "Sources/Core/PackageIndexing:CorePackageIndexing"
    "Sources/Core/PackageIndexing/Model:CorePackageIndexingModels"
    "Sources/Core/SampleCode/Core:CoreSampleCode"
    "Sources/Core/SampleCode/Model:CoreSampleCodeModels"
    "Sources/Core/SampleCode/WebKit:CoreSampleCodeWebKit"
    "Sources/Search/API:SearchAPI"
    "Sources/Search/Model:SearchModels"
    "Sources/Search/Schema:SearchSchema"
    "Sources/Search/SQLite:SearchSQLite"
    "Sources/Search/StrategyHelpers:SearchStrategyHelpers"
    "Sources/Search/ToolProvider:SearchToolProvider"
    "Sources/Source/AppleArchive:AppleArchiveSource"
    "Sources/Source/AppleDocs:AppleDocsSource"
    "Sources/Source/HIG:HIGSource"
    "Sources/Source/Packages:PackagesSource"
    "Sources/Source/SampleCode:SampleCodeSource"
    "Sources/Source/SwiftBook:SwiftBookSource"
    "Sources/Source/SwiftEvolution:SwiftEvolutionSource"
    "Sources/Source/SwiftOrg:SwiftOrgSource"
    "Sources/Enrichment/Core:Enrichment"
    "Sources/Enrichment/Model:EnrichmentModels"
    "Sources/Enrichment/Pass:EnrichmentPasses"
    "Sources/Distribution/Core:Distribution"
    "Sources/Distribution/Model:DistributionModels"
    "Sources/Cleanup/Core:Cleanup"
    "Sources/Cleanup/Model:CleanupModels"
    "Sources/Logging/Core:Logging"
    "Sources/Logging/Model:LoggingModels"
    "Sources/Crawler/Core:Crawler"
    "Sources/Crawler/Model:CrawlerModels"
    "Sources/Crawler/WebKit:CrawlerWebKit"
    "Sources/Availability/Core:Availability"
    "Sources/Availability/Model:AvailabilityModels"
    "Sources/Availability/FoundationNetworking:AvailabilityFoundationNetworking"
    "Sources/SampleIndex/Core:SampleIndex"
    "Sources/SampleIndex/Model:SampleIndexModels"
    "Sources/SampleIndex/SQLite:SampleIndexSQLite"
    "Sources/RemoteSync/Core:RemoteSync"
    "Sources/RemoteSync/Model:RemoteSyncModels"
    "Sources/Services/Core:Services"
    "Sources/Services/Model:ServicesModels"
    "Sources/Indexer/Core:Indexer"
    "Sources/Indexer/Model:IndexerModels"
)

repo_root="$(cd "$SOURCES_DIR/.." && pwd)"
for entry in "${FAMILY_SUBTARGETS[@]}"; do
    sub_path="${entry%%:*}"
    sub_target="${entry##*:}"
    if is_exempt "$sub_target"; then
        continue
    fi
    sub_dir="$repo_root/$sub_path"
    [ -d "$sub_dir" ] || continue
    set +e
    matches="$(grep -REn "$PATTERN" "$sub_dir" --include='*.swift' 2>/dev/null --exclude-dir=Core --exclude-dir=Model --exclude-dir=Pass --exclude-dir=Schema --exclude-dir=SQLite --exclude-dir=API --exclude-dir=StrategyHelpers --exclude-dir=ToolProvider --exclude-dir=WebKit --exclude-dir=Protocols --exclude-dir=FoundationNetworking --exclude-dir=JSONParser --exclude-dir=PackageIndexing --exclude-dir=SampleCode --exclude-dir=HTMLParser || true)"
    set -e
    if [ -n "$matches" ]; then
        if is_grandfathered "$sub_target"; then
            while IFS= read -r line; do
                grandfathered_lines+=("$line")
            done <<< "$matches"
        else
            while IFS= read -r line; do
                violation_lines+=("$line")
                violations=$((violations + 1))
            done <<< "$matches"
        fi
    fi
done

# MCP sub-targets sit one level deeper.
for mcp_sub in Client Core Support SharedTools; do
    sub_dir="$SOURCES_DIR/MCP/$mcp_sub"
    [ -d "$sub_dir" ] || continue
    set +e
    matches="$(grep -rEn "$PATTERN" "$sub_dir" --include='*.swift' 2>/dev/null || true)"
    set -e
    if [ -n "$matches" ]; then
        while IFS= read -r line; do
            violation_lines+=("$line")
            violations=$((violations + 1))
        done <<< "$matches"
    fi
done

if [ "$violations" -gt 0 ]; then
    echo "❌ Package purity check failed: $violations forbidden import(s)." >&2
    echo "" >&2
    echo "A non-binary SPM target imported a concrete-producer module." >&2
    echo "Concrete imports are reserved for the composition root binaries" >&2
    echo "(${EXEMPT_TARGETS[*]}). Route the dependency through the" >&2
    echo "target's *Models protocol seam instead, or inject a factory." >&2
    echo "" >&2
    echo "Violations:" >&2
    for line in "${violation_lines[@]}"; do
        echo "  $line" >&2
    done
    echo "" >&2
    echo "See #503 for the rationale (Phase B of the GoF protocol-DI refactor)." >&2
    exit 1
fi

if [ "${#grandfathered_lines[@]}" -gt 0 ]; then
    echo "⚠️  Package purity check passed — but ${#grandfathered_lines[@]} grandfathered import(s) remain in:"
    for g in "${GRANDFATHERED_TARGETS[@]:-}"; do
        echo "    - $g"
    done
    echo "  Follow-up issue tracks migrating these out. New imports from any other"
    echo "  non-binary target still fail; this is the floor, not the ceiling."
else
    echo "✅ Package purity check passed — no consumer target imports a concrete producer."
fi
