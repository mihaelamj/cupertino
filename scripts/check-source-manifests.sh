#!/usr/bin/env bash
#
# check-source-manifests.sh
#
# Validates the per-source declared manifests under docs/sources/<id>/
# against the schema in docs/design/corpus-structure.md §3.
#
# Step 2 of the per-source DB split epic: the manifests land as
# scaffolding ahead of the Swift YAML loader (step 3). This script is
# the only mechanical validation today; once the binary loader wires
# up, the same manifests are decoded into Shared.Models.CorpusManifest
# and the runtime decoder catches schema drift on every build.
#
# What this script catches:
#   1. Missing manifest.yaml for a source folder
#   2. Required field missing (sourceId / displayName / corpusFolder /
#      destinationDB / fetcher / indexer / capabilities)
#   3. sourceId does NOT match the folder name
#   4. fetcher.kind not in the allowed set
#   5. capabilities.searchers / operations not in the allowed set
#   6. fetcher.options carries non-string values (would silently fail
#      decode into [String: String]? once the loader lands)
#
# Exit codes:
#   0   all manifests valid
#   1   validation error (details printed)
#   2   invocation error (yq not installed, repo layout missing)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v yq >/dev/null 2>&1; then
    echo "error: yq not installed; \`brew install yq\` to run this check." >&2
    exit 2
fi

if [[ ! -d "docs/sources" ]]; then
    echo "error: docs/sources/ does not exist; nothing to validate." >&2
    exit 2
fi

REQUIRED_FIELDS=(sourceId displayName corpusFolder destinationDB fetcher indexer capabilities)

ALLOWED_FETCHER_KINDS=(apple-docs-api git-clone http-archive github-api file-bundle)

ALLOWED_SEARCHERS=(
    text symbols property-wrappers concurrency conformances generics
    package-search sample-files
)

ALLOWED_OPERATIONS=(
    read-by-uri list-frameworks list-samples resolve-refs
)

errors=()
manifests_checked=0

contains() {
    local needle="$1"
    shift
    for hay in "$@"; do
        [[ "$hay" == "$needle" ]] && return 0
    done
    return 1
}

for manifest_dir in docs/sources/*/; do
    folder_name=$(basename "$manifest_dir")
    manifest_path="${manifest_dir}manifest.yaml"

    if [[ ! -f "$manifest_path" ]]; then
        errors+=("MISSING  $manifest_dir  →  manifest.yaml is missing")
        continue
    fi

    manifests_checked=$((manifests_checked + 1))

    # Validate YAML parses.
    if ! yq eval '.' "$manifest_path" >/dev/null 2>&1; then
        errors+=("PARSE    $manifest_path  →  YAML does not parse")
        continue
    fi

    # Required fields.
    for field in "${REQUIRED_FIELDS[@]}"; do
        value=$(yq eval ".$field" "$manifest_path")
        if [[ "$value" == "null" || -z "$value" ]]; then
            errors+=("REQUIRED $manifest_path  →  missing required field: $field")
        fi
    done

    # sourceId matches folder name.
    source_id=$(yq eval '.sourceId' "$manifest_path")
    if [[ "$source_id" != "$folder_name" ]]; then
        errors+=("SOURCEID $manifest_path  →  sourceId '$source_id' does not match folder name '$folder_name'")
    fi

    # fetcher.kind is in the allowed set.
    fetcher_kind=$(yq eval '.fetcher.kind' "$manifest_path")
    if [[ "$fetcher_kind" != "null" ]]; then
        if ! contains "$fetcher_kind" "${ALLOWED_FETCHER_KINDS[@]}"; then
            errors+=("FETCHER  $manifest_path  →  fetcher.kind '$fetcher_kind' not in allowed set: ${ALLOWED_FETCHER_KINDS[*]}")
        fi
    fi

    # fetcher.options values are all strings (per the Fetcher.options:
    # [String: String]? type). yq's tag inspection: scalars carry !!str
    # for quoted strings; unquoted numbers/floats carry !!int / !!float.
    bad_option_types=$(yq eval '.fetcher.options // {} | to_entries | .[] | select(.value | tag != "!!str") | .key' "$manifest_path" 2>/dev/null || true)
    if [[ -n "$bad_option_types" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            errors+=("OPTIONS  $manifest_path  →  fetcher.options.$key is not a string (quote it; e.g. '0.05' not 0.05)")
        done <<< "$bad_option_types"
    fi

    # capabilities.searchers entries are in the allowed set.
    searchers=$(yq eval '.capabilities.searchers[]' "$manifest_path" 2>/dev/null || true)
    while IFS= read -r searcher; do
        [[ -z "$searcher" ]] && continue
        if ! contains "$searcher" "${ALLOWED_SEARCHERS[@]}"; then
            errors+=("SEARCHER $manifest_path  →  capabilities.searchers entry '$searcher' not in allowed set: ${ALLOWED_SEARCHERS[*]}")
        fi
    done <<< "$searchers"

    # capabilities.operations entries are in the allowed set.
    operations=$(yq eval '.capabilities.operations[]' "$manifest_path" 2>/dev/null || true)
    while IFS= read -r operation; do
        [[ -z "$operation" ]] && continue
        if ! contains "$operation" "${ALLOWED_OPERATIONS[@]}"; then
            errors+=("OPERATIO $manifest_path  →  capabilities.operations entry '$operation' not in allowed set: ${ALLOWED_OPERATIONS[*]}")
        fi
    done <<< "$operations"
done

if [[ ${#errors[@]} -eq 0 ]]; then
    echo "✅ docs/sources/ manifests valid"
    echo "   manifests checked: $manifests_checked"
    exit 0
fi

{
    echo "❌ docs/sources/ manifest validation failed"
    echo
    echo "   manifests checked:  $manifests_checked"
    echo "   errors detected:    ${#errors[@]}"
    echo
    for line in "${errors[@]}"; do
        echo "     $line"
    done
    echo
    echo "Schema: docs/design/corpus-structure.md §3"
} >&2
exit 1
