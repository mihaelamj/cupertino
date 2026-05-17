#!/usr/bin/env bash
# check-issue-body-staleness.sh: scan open issue bodies for drift.
#
# Born from the 2026-05-17 full-tracker audit: 47 of 56 open issues had
# at least one factual error in the body (stale file paths, phantom
# paths, wrong cross-refs, wrong schema columns). Bodies decay because
# code moves while bodies stand still. This script is the mechanical
# backstop that surfaces drift before the next deep audit has to find
# it by hand.
#
# Five checks, four per-issue + one tracker-global:
#
#   1. RENAMED PATHS: bodies still cite a file path that was renamed
#      or split. Maintained rename map below.
#
#   2. PHANTOM PATHS: bodies cite a file path that does not exist
#      anywhere in the repo or declared sibling repos. Caught 7 issues
#      citing `mihaela-blog-ideas/cupertino/research/CUPERTINO_*.md`,
#      a file that was never written.
#
#   3. STALE CROSS-REFS: bodies say "blocked on #X" / "pending in #X"
#      / "depends on #X" / "after #X lands" where #X is CLOSED.
#
#   4. STALE SCHEMA CLAIMS: bodies reference `docs_metadata.<col>` or
#      `samples.<table>.<col>` that does not exist in the current
#      schema. Caught #70 / #73 claiming `docs_metadata.abstract` and
#      `docs_metadata.code_examples` which live elsewhere.
#
#   5. LABEL DRIFT: tracker-global checks for orphan `blocked_by_<N>`
#      labels (target closed), `fix-in: v<X.Y.Z>` labels for shipped
#      versions (SHIPPED_VERSIONS list), single-carrier topical labels
#      (1 open carrier = grow or fold), and open issues missing kind
#      or priority labels. Maintained `SHIPPED_VERSIONS` list keeps the
#      check accurate without filesystem probes.
#
# Output: a markdown report on stdout (intended to be uploaded as a
# tracking-issue body by the calling workflow). One section per check;
# within each, one bullet per issue.
#
# Usage:
#   ./scripts/check-issue-body-staleness.sh                  (full run)
#   ./scripts/check-issue-body-staleness.sh --check=labels   (single check; renamed/phantom/xref/schema/labels)
#   ./scripts/check-issue-body-staleness.sh --issue=70       (single issue)
#   ./scripts/check-issue-body-staleness.sh --dry-run        (skip gh API,
#                                                             read from
#                                                             /tmp/bodies/)
#
# Exit codes:
#   0: clean (no drift found OR --dry-run with no fixtures)
#   1: drift found (CI can fail the workflow on this)
#   2: invocation error / missing tool

set -uo pipefail

REPO="mihaelamj/cupertino"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || { echo "❌ cannot cd to repo root" >&2; exit 2; }

# --- Arg parsing -------------------------------------------------------

CHECK="all"
SINGLE_ISSUE=""
DRY_RUN=false
SCHEMA_FILE="Packages/Sources/Search/Search.Index.Schema.swift"

for arg in "$@"; do
    case "$arg" in
        --check=*) CHECK="${arg#--check=}" ;;
        --issue=*) SINGLE_ISSUE="${arg#--issue=}" ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            sed -n '2,50p' "$0" | sed 's/^# //;s/^#//'
            exit 0
            ;;
        *) echo "❌ unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# --- Tooling check ----------------------------------------------------

if ! $DRY_RUN; then
    command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not installed" >&2; exit 2; }
    command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed" >&2; exit 2; }
fi

# --- Rename map (CHECK 1) ---------------------------------------------
#
# Format: each line is "OLD_PATTERN<TAB>NEW_HINT". OLD_PATTERN is a
# regex matched against issue bodies; NEW_HINT is human-readable
# remediation text. Add entries when you do a rename / split / move.
#
# Convention: more-specific patterns first so partial overlaps land on
# the right hint.

RENAME_MAP=$(cat <<'EOF'
\bPackages/Sources/Search/SearchIndex\.swift\b	split into Search.Index.*.swift (Search.Index.swift / Search.Index.Search.swift / Search.Index.Schema.swift / Search.Index.SemanticSearch.swift / etc.)
\bPackages/Sources/Search/SearchIndexBuilder\.swift\b	renamed to Search.IndexBuilder.swift
\bPackages/Sources/SampleIndex/SampleIndexDatabase\.swift\b	renamed to Sample.Index.Database.swift
\bPackages/Sources/Resources/Embedded/ArchiveGuidesCatalogEmbedded\.swift\b	renamed to Resources.Embedded.ArchiveGuidesCatalog.swift
\bPackages/Sources/Resources/Embedded/SampleCodeCatalogEmbedded\.swift\b	deleted in #215 (sample-code metadata now lives in samples.db + ~/.cupertino/sample-code/catalog.json)
\bPackages/Sources/Resources/Embedded/SwiftPackagesCatalogEmbedded\.swift\b	deleted in #711 / #194 (catalog now in packages.db)
\bPackages/Sources/Core/Protocols/\b	package renamed: CoreProtocols/ (no slash inside)
\bSources/TUI/\b	missing Packages/ prefix: use Packages/Sources/TUI/
\bSources/Resources/Embedded/\b	missing Packages/ prefix: use Packages/Sources/Resources/Embedded/
\bdocs/tools/\b	docs tree uses docs/commands/<cmd>/option (--)/<flag>.md shape; no docs/tools/ tree exists
\bScripts/generate-embedded-catalogs\.sh\b	lowercase: scripts/generate-embedded-catalogs.sh
EOF
)

# --- Phantom paths the audit caught (CHECK 2 starters) ----------------
#
# These don't exist anywhere. Quick-win matches. The general phantom
# detector below extracts paths from bodies and checks the filesystem;
# this list is the curated set of known-bad citations to flag with a
# specific hint rather than the generic "path not found" message.

PHANTOM_HINTS=$(cat <<'EOF'
mihaela-blog-ideas/cupertino/research/CUPERTINO_FEATURE_ROADMAP\.md	research roadmap doc was never written. Reframe as "archived in private notes" or point at #742 for the diagnostic-block keystone.
mihaela-blog-ideas/cupertino/research/CUPERTINO_ACADEMIC_LITERATURE_REVIEW\.md	academic-literature review was never written. Reframe as "archived in private notes."
EOF
)

# --- Schema claims to validate (CHECK 4) ------------------------------
#
# Format: regex pattern matched against issue bodies. If the pattern
# matches but the SCHEMA_FILE doesn't define the column, flag it.
# Conservative: only checks `docs_metadata.<col>` and the most-cited
# tables. Expand as needed.

SCHEMA_TABLES=(docs_metadata docs_structured doc_symbols doc_code_examples package_metadata package_files sample_code_metadata)

# --- Cross-ref blocker phrases (CHECK 3) ------------------------------
#
# Regex fragments that indicate a #NNN mention is a BLOCKER claim
# rather than a sibling / sees-also mention. Tightened deliberately to
# avoid false positives on every "see #N" / "related: #N" line.

BLOCKER_PHRASES='(blocked[ -]?on|blocks?|depends on|after #?[0-9]+ lands|gated on|hard block on|pending in|awaits?|waiting on)'

# --- Shipped release tags (CHECK 5 — label drift) ---------------------
#
# Versions for which `fix-in: v<X.Y.Z>` labels mean "shipped" rather
# than "targeted." Append a version to this list when its tag drops.
# The script flags any `fix-in: v<X.Y.Z>` label for these versions as
# stale (suggest rename to `released-in: v<X.Y.Z>` or delete).

SHIPPED_VERSIONS=(v1.0.0 v1.0.1 v1.0.2 v1.1.0)

# --- Helpers ----------------------------------------------------------

fetch_open_issues() {
    if $DRY_RUN; then
        ls /tmp/bodies/ 2>/dev/null | sed 's/\.md$//' | sort -n
    elif [ -n "$SINGLE_ISSUE" ]; then
        echo "$SINGLE_ISSUE"
    else
        gh issue list -R "$REPO" --state open --limit 200 --json number -q '.[] | .number' | sort -n
    fi
}

fetch_body() {
    local n="$1"
    if $DRY_RUN; then
        cat "/tmp/bodies/${n}.md" 2>/dev/null || true
    else
        gh issue view "$n" -R "$REPO" --json body -q .body 2>/dev/null || true
    fi
}

issue_state() {
    local n="$1"
    if $DRY_RUN; then
        # In dry-run mode we don't know; pretend open.
        echo "OPEN"
    else
        gh issue view "$n" -R "$REPO" --json state -q .state 2>/dev/null || echo "UNKNOWN"
    fi
}

# Returns the column list for a given table by reading SCHEMA_FILE.
# Crude: extracts the lines between `CREATE TABLE <table> (` and the
# matching `);`, pulls the first whitespace-separated token on each
# row, drops constraints. Good enough for `docs_metadata` / friends.
schema_columns_for() {
    local table="$1"
    [ -f "$SCHEMA_FILE" ] || return
    awk -v t="$table" '
        BEGIN { inside = 0 }
        $0 ~ "CREATE (VIRTUAL )?TABLE (IF NOT EXISTS )?" t " *\\(|CREATE (VIRTUAL )?TABLE (IF NOT EXISTS )?" t "\\(" { inside = 1; next }
        inside && $0 ~ /^[[:space:]]*\);/ { inside = 0 }
        inside {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "" || $0 ~ /^--/) next
            split($0, parts, /[[:space:]]+|,/)
            col = parts[1]
            # skip constraints
            if (col ~ /^(PRIMARY|FOREIGN|UNIQUE|CHECK|CONSTRAINT|CREATE)/) next
            gsub(/[",;()]/, "", col)
            if (col != "") print col
        }
    ' "$SCHEMA_FILE" | sort -u
}

# --- Per-issue checks ------------------------------------------------

check_renamed() {
    local n="$1" body="$2"
    local hits=""
    while IFS=$'\t' read -r pat hint; do
        [ -z "$pat" ] && continue
        if echo "$body" | grep -qE "$pat"; then
            local sample
            sample=$(echo "$body" | grep -oE "$pat" | head -1)
            hits+="    - \`${sample}\` → ${hint}"$'\n'
        fi
    done <<<"$RENAME_MAP"
    if [ -n "$hits" ]; then
        echo "  - **#$n** (renamed paths):"
        printf "%s" "$hits"
    fi
}

check_phantom() {
    local n="$1" body="$2"
    local hits=""
    # Curated hints first
    while IFS=$'\t' read -r pat hint; do
        [ -z "$pat" ] && continue
        if echo "$body" | grep -qE "$pat"; then
            local sample
            sample=$(echo "$body" | grep -oE "$pat" | head -1)
            hits+="    - \`${sample}\` → ${hint}"$'\n'
        fi
    done <<<"$PHANTOM_HINTS"
    # Generic detector: pull `\`-quoted paths and check filesystem.
    # Conservative: only flag paths that look like source files
    # (contain `/`, end in a known source extension or have a
    # multi-segment dotted name).
    local paths
    paths=$(echo "$body" | grep -oE '`[^`]*\.(swift|md|sh|json|yml|yaml|html|sql)`' | sed 's/^`//;s/`$//' | sort -u)
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        # Skip pure-glob patterns
        [[ "$p" == *'*'* ]] && continue
        # Skip URI examples (e.g., apple-docs://...)
        [[ "$p" == *'://'* ]] && continue
        # Skip paths already flagged by curated hints
        echo "$hits" | grep -q "$p" && continue
        # Check filesystem (repo root + private sibling base if discoverable)
        if [ ! -e "$REPO_ROOT/$p" ] && [ ! -e "$p" ]; then
            # Path doesn't exist in repo. Could be in a sibling repo.
            # Conservative: only flag if it looks like a repo-local path
            # (starts with `Packages/`, `scripts/`, `docs/`, `.github/`).
            case "$p" in
                Packages/*|scripts/*|docs/*|.github/*|Apps/*)
                    hits+="    - \`${p}\` → path does not exist in repo (filesystem-checked)"$'\n'
                    ;;
            esac
        fi
    done <<<"$paths"
    if [ -n "$hits" ]; then
        echo "  - **#$n** (phantom paths):"
        printf "%s" "$hits"
    fi
}

check_xref() {
    local n="$1" body="$2"
    local hits=""
    # Extract candidate blocker contexts: any line containing both a
    # `#NNN` reference and a blocker phrase. Conservative: catches
    # the explicit "blocked on" / "pending in" patterns, misses
    # implicit ones.
    local lines
    lines=$(echo "$body" | grep -iE "$BLOCKER_PHRASES" | grep -oE "#[0-9]+" | sort -u)
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        local num="${ref#\#}"
        # Don't self-reference
        [ "$num" = "$n" ] && continue
        local state
        state=$(issue_state "$num")
        if [ "$state" = "CLOSED" ]; then
            hits+="    - blocker context references ${ref} which is CLOSED; body may be claiming a closed dep is still pending"$'\n'
        fi
    done <<<"$lines"
    if [ -n "$hits" ]; then
        echo "  - **#$n** (stale cross-refs):"
        printf "%s" "$hits"
    fi
}

check_schema() {
    local n="$1" body="$2"
    [ -f "$SCHEMA_FILE" ] || return
    local hits=""
    for table in "${SCHEMA_TABLES[@]}"; do
        local refs
        refs=$(echo "$body" | grep -oE "${table}\.[a-z_]+" | sort -u)
        [ -z "$refs" ] && continue
        local cols
        cols=$(schema_columns_for "$table")
        while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            local col="${ref#${table}.}"
            if ! echo "$cols" | grep -qx "$col"; then
                hits+="    - \`${ref}\` → column \`${col}\` not found in \`${table}\` (\`${SCHEMA_FILE}\`)"$'\n'
            fi
        done <<<"$refs"
    done
    if [ -n "$hits" ]; then
        echo "  - **#$n** (stale schema claims):"
        printf "%s" "$hits"
    fi
}

# --- Label drift (CHECK 5) -------------------------------------------
#
# Five sub-checks across all open + closed issues. These are NOT
# per-issue body parses; they operate on the label list directly.
#
# 5a. Dead `blocked_by_<N>` labels where #N is CLOSED.
# 5b. `fix-in: v<X.Y.Z>` labels for SHIPPED_VERSIONS (rename / delete).
# 5c. Single-carrier labels (1 open issue carries it) — grow or fold.
# 5d. Open issues missing a kind label (enhancement / bug / etc.).
# 5e. Open issues missing a priority label (excluding epics / wishlist).
#
# Output goes into a single LABEL_REPORT block so the workflow's
# tracking issue keeps one section for the label axis.

check_labels_global() {
    local report=""

    # 5a. blocked_by_<N> orphans
    local labels_list
    labels_list=$(gh label list -R "$REPO" --limit 200 --json name -q '.[] | .name' 2>/dev/null)
    while IFS= read -r lbl; do
        [ -z "$lbl" ] && continue
        case "$lbl" in
            blocked_by_*)
                local num="${lbl#blocked_by_}"
                [[ "$num" =~ ^[0-9]+$ ]] || continue
                local state
                state=$(issue_state "$num")
                if [ "$state" = "CLOSED" ]; then
                    local carriers
                    carriers=$(gh issue list -R "$REPO" --state open --label "$lbl" --json number -q '. | length' 2>/dev/null)
                    report+="    - \`${lbl}\` → target #${num} is CLOSED; ${carriers} open carrier(s). Remove the label from any open carriers, then delete the label."$'\n'
                fi
                ;;
        esac
    done <<<"$labels_list"

    # 5b. fix-in: v<X.Y.Z> for shipped versions
    while IFS= read -r lbl; do
        [ -z "$lbl" ] && continue
        case "$lbl" in
            "fix-in: "*)
                local ver="${lbl#fix-in: }"
                for shipped in "${SHIPPED_VERSIONS[@]}"; do
                    if [ "$ver" = "$shipped" ]; then
                        report+="    - \`${lbl}\` → version ${ver} shipped; rename to \`released-in: ${ver}\` or delete."$'\n'
                        break
                    fi
                done
                ;;
        esac
    done <<<"$labels_list"

    # 5c. Single-carrier labels (1 open carrier — neither cluster nor footnote)
    while IFS= read -r lbl; do
        [ -z "$lbl" ] && continue
        # Skip release/triage labels — they're axes, not topical
        case "$lbl" in
            priority:*|complexity:*|"released-in:"*|"fix-in:"*|"fixed: "*|enhancement|bug|documentation|epic|"good first issue"|"help wanted"|duplicate|invalid|question|wontfix|blocked|blocker)
                continue
                ;;
        esac
        local open_count
        open_count=$(gh issue list -R "$REPO" --state open --label "$lbl" --json number -q '. | length' 2>/dev/null)
        if [ "$open_count" = "1" ]; then
            local carrier
            carrier=$(gh issue list -R "$REPO" --state open --label "$lbl" --json number -q '.[0].number' 2>/dev/null)
            report+="    - \`${lbl}\` → only 1 open carrier (#${carrier}); grow the cluster or fold the categorization into the body."$'\n'
        fi
    done <<<"$labels_list"

    # 5d + 5e. Per-open-issue: missing kind / missing priority
    local issues_json
    issues_json=$(gh issue list -R "$REPO" --state open --limit 200 --json number,labels 2>/dev/null)
    local missing_kind
    missing_kind=$(echo "$issues_json" | jq -r '.[] | select(([.labels[].name] | map(test("^(enhancement|bug|documentation|epic|wishlist)$")) | any) | not) | .number')
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        report+="    - #${n} → missing kind label (no enhancement / bug / documentation / epic / wishlist)."$'\n'
    done <<<"$missing_kind"

    local missing_priority
    missing_priority=$(echo "$issues_json" | jq -r '.[] | select([.labels[].name] | map(test("^(priority:|epic|wishlist)")) | any | not) | .number')
    local count_no_priority
    count_no_priority=$(echo "$missing_priority" | grep -c . 2>/dev/null || echo "0")
    if [ "$count_no_priority" -gt 0 ]; then
        report+="    - **${count_no_priority} open issues** missing \`priority:\` label (and not labeled epic / wishlist). Backfill candidates: $(echo "$missing_priority" | head -10 | tr '\n' ' ' | sed 's/ $//')$([ "$count_no_priority" -gt 10 ] && echo " ... (+$((count_no_priority - 10)) more)")."$'\n'
    fi

    if [ -n "$report" ]; then
        echo "$report"
    fi
}

# --- Main loop --------------------------------------------------------

RENAMED_REPORT=""
PHANTOM_REPORT=""
XREF_REPORT=""
SCHEMA_REPORT=""
LABEL_REPORT=""

issues=$(fetch_open_issues)
total=$(echo "$issues" | wc -l | tr -d ' ')
echo "Scanning $total open issues..." >&2

# Label drift is global — run once, not per-issue
if [ "$CHECK" = "all" ] || [ "$CHECK" = "labels" ]; then
    LABEL_REPORT=$(check_labels_global)
fi

for n in $issues; do
    body=$(fetch_body "$n")
    [ -z "$body" ] && continue

    if [ "$CHECK" = "all" ] || [ "$CHECK" = "renamed" ]; then
        out=$(check_renamed "$n" "$body")
        [ -n "$out" ] && RENAMED_REPORT+="$out"$'\n'
    fi
    if [ "$CHECK" = "all" ] || [ "$CHECK" = "phantom" ]; then
        out=$(check_phantom "$n" "$body")
        [ -n "$out" ] && PHANTOM_REPORT+="$out"$'\n'
    fi
    if [ "$CHECK" = "all" ] || [ "$CHECK" = "xref" ]; then
        out=$(check_xref "$n" "$body")
        [ -n "$out" ] && XREF_REPORT+="$out"$'\n'
    fi
    if [ "$CHECK" = "all" ] || [ "$CHECK" = "schema" ]; then
        out=$(check_schema "$n" "$body")
        [ -n "$out" ] && SCHEMA_REPORT+="$out"$'\n'
    fi
done

# --- Report -----------------------------------------------------------

DRIFT=false

cat <<EOF
# Issue body staleness report

Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by \`scripts/check-issue-body-staleness.sh\`.

Each section lists open issues whose bodies contain drift relative to the current repo state. Per-bullet remediation hints are auto-generated; pair workflow walks them in the next bug-list pass.

EOF

if [ -n "$RENAMED_REPORT" ]; then
    DRIFT=true
    echo "## Renamed paths (check 1)"
    echo ""
    echo "Bodies still cite a path that was renamed, split, or deleted. Hints below name the current location."
    echo ""
    printf "%s" "$RENAMED_REPORT"
    echo ""
fi

if [ -n "$PHANTOM_REPORT" ]; then
    DRIFT=true
    echo "## Phantom paths (check 2)"
    echo ""
    echo "Bodies cite paths that do not exist anywhere in the repo. Either the path was made up, or it's a sibling-repo path the script can't see, re-anchor or remove the citation."
    echo ""
    printf "%s" "$PHANTOM_REPORT"
    echo ""
fi

if [ -n "$XREF_REPORT" ]; then
    DRIFT=true
    echo "## Stale cross-refs (check 3)"
    echo ""
    echo "Bodies use blocker phrasing (\"blocked on\", \"pending in\", \"depends on\", \"after #N lands\") for an issue that is now CLOSED. Either the dep shipped (body should say so) or the blocker text is wrong."
    echo ""
    printf "%s" "$XREF_REPORT"
    echo ""
fi

if [ -n "$SCHEMA_REPORT" ]; then
    DRIFT=true
    echo "## Stale schema claims (check 4)"
    echo ""
    echo "Bodies reference \`<table>.<column>\` shapes that don't match the current schema. Schema source: \`${SCHEMA_FILE}\`."
    echo ""
    printf "%s" "$SCHEMA_REPORT"
    echo ""
fi

if [ -n "$LABEL_REPORT" ]; then
    DRIFT=true
    echo "## Label drift (check 5)"
    echo ""
    echo "Tracker-level label problems: orphan \`blocked_by_<N>\` (referenced issue closed), \`fix-in: v<X.Y.Z>\` for shipped versions, single-carrier topical labels (grow or fold), and open issues missing a kind or priority label. Shipped versions are maintained in the script's \`SHIPPED_VERSIONS\` list — bump it when a new release tag drops."
    echo ""
    printf "%s" "$LABEL_REPORT"
    echo ""
fi

if ! $DRIFT; then
    echo "✅ No drift detected across $total open issues."
    exit 0
fi

echo "---"
echo ""
echo "**Total open issues scanned:** $total"
echo ""
echo "Origin: ironclad-sweep 2026-05-17 audit found 47 / 56 open issues had at least one drift error. This script is the mechanical backstop. Methodology doc: \`docs/audits/methodology.md\`."

exit 1
