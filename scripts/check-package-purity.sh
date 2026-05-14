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
    Availability
    Cleanup
    Core
    CoreJSONParser
    CorePackageIndexing
    CoreSampleCode
    Crawler
    Diagnostics
    Distribution
    Indexer
    Ingest
    RemoteSync
    SampleIndex
    Search
)

# Targets that ARE composition roots — they may import any concrete.
# CLI and TUI ship as binaries. MockAIAgent and ReleaseTool are
# additional binary-like roots that need direct access to concretes.
EXEMPT_TARGETS=(
    CLI
    TUI
    MockAIAgent
    ReleaseTool
)

# Grandfathered targets — pre-existing leaks acknowledged here so
# the guard passes against the tree as it stands today. New imports
# from these targets still fail; the goal is to migrate each
# grandfathered target out of this list as its leaks are cleaned up.
#
# Empty after #505 closed: Crawler routed its three concrete-Core
# deps through Strategy protocols in CrawlerModels.
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
    for g in "${GRANDFATHERED_TARGETS[@]}"; do
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
    for g in "${GRANDFATHERED_TARGETS[@]}"; do
        echo "    - $g"
    done
    echo "  Follow-up issue tracks migrating these out. New imports from any other"
    echo "  non-binary target still fail; this is the floor, not the ceiling."
else
    echo "✅ Package purity check passed — no consumer target imports a concrete producer."
fi
