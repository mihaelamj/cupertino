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
#      (1 open carrier = grow or fold), and open issues missing a kind
#      label. Canonical 5-label set is bug / enhancement / epic /
#      `priority: high` / `good first issue`. Maintained
#      `SHIPPED_VERSIONS` list keeps the check accurate without
#      filesystem probes.
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

# Per-table schema source routing. Each cited `<table>.<col>` reference
# in an issue body is validated against the DIRECTORY that defines that
# table's columns. Pre-#886 the script read only search.db's schema, so
# any packages.db or samples.db column citation false-flagged as "column
# not found" (Origin: #886). #1137 widened this from a single file to a
# directory: columns are added across many files (CREATE TABLE in the
# schema file, plus later ALTER TABLE ... ADD COLUMN in migrations), so
# `schema_columns_for` now scans every .swift under the routed dir for
# both CREATE and ALTER columns. Validation stays table-name scoped, so
# co-locating search + packages schemas under one dir is safe.
SCHEMA_SEARCH="Packages/Sources/SearchSQLite"
SCHEMA_PACKAGES="Packages/Sources/SearchSQLite"
SCHEMA_SAMPLES="Packages/Sources/SampleIndexSQLite"

# Resolve the schema source file for a given table name. Echoes the
# file path (relative to repo root) or empty if the table isn't routed.
schema_source_for() {
    case "$1" in
        docs_metadata|docs_structured|doc_symbols|doc_code_examples|doc_imports|framework_aliases|inheritance|sample_code_metadata)
            echo "$SCHEMA_SEARCH"
            ;;
        package_metadata|package_files|package_symbols|package_imports)
            echo "$SCHEMA_PACKAGES"
            ;;
        files|file_imports|file_symbols|projects)
            echo "$SCHEMA_SAMPLES"
            ;;
        *) echo "" ;;
    esac
}

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
Packages/Sources/Search/SearchIndex\.swift	split into Search.Index.*.swift (Search.Index.swift / Search.Index.Search.swift / Search.Index.Schema.swift / Search.Index.SemanticSearch.swift / etc.) under Packages/Sources/SearchSQLite/ post-#898
Packages/Sources/Search/SearchIndexBuilder\.swift	renamed to Search.IndexBuilder.swift; lives under Packages/Sources/SearchAPI/ post-#900
Packages/Sources/Search/	target renamed to Packages/Sources/SearchAPI/ in #900; SQLite-backed concretes split to Packages/Sources/SearchSQLite/ in #898
Packages/Sources/SampleIndex/SampleIndexDatabase\.swift	renamed to Sample.Index.Database.swift
Packages/Sources/Resources/Embedded/ArchiveGuidesCatalogEmbedded\.swift	renamed to Resources.Embedded.ArchiveGuidesCatalog.swift
Packages/Sources/Resources/Embedded/SampleCodeCatalogEmbedded\.swift	deleted in #215 (sample-code metadata now lives in samples.db + ~/.cupertino/sample-code/catalog.json)
Packages/Sources/Resources/Embedded/SwiftPackagesCatalogEmbedded\.swift	deleted in #711 / #194 (catalog now in packages.db)
Packages/Sources/Core/Protocols/	package renamed: CoreProtocols/ (no slash inside)
Sources/TUI/	missing Packages/ prefix: use Packages/Sources/TUI/
Sources/Resources/Embedded/	missing Packages/ prefix: use Packages/Sources/Resources/Embedded/
Scripts/generate-embedded-catalogs\.sh	lowercase: scripts/generate-embedded-catalogs.sh
\.github/ISSUE_TEMPLATE/feature\.md	converted to feature.yml GitHub form template in PR #745
\.github/ISSUE_TEMPLATE/bug\.md	converted to bug.yml GitHub form template in PR #745
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
# Each table in `SCHEMA_TABLES` is matched against issue bodies via the
# `<table>.<col>` shape; the column is then validated against the
# schema source file that `schema_source_for` routes the table to
# (search.db / packages.db / samples.db, see the SCHEMA_* paths above).
# Conservative: only the most-cited tables are listed; expand as
# citations enter issue bodies.

SCHEMA_TABLES=(
    # search.db tables
    docs_metadata docs_structured doc_symbols doc_code_examples sample_code_metadata
    # packages.db tables
    package_metadata package_files package_symbols package_imports
    # samples.db tables
    file_imports file_symbols
)

# --- Cross-ref blocker phrases (CHECK 3) ------------------------------
#
# Regex fragments that indicate a #NNN mention is a BLOCKER claim
# rather than a sibling / sees-also mention. Tightened deliberately to
# avoid false positives on every "see #N" / "related: #N" line.

BLOCKER_PHRASES='(blocked[ -]?on|blocked by|blocks +#?[0-9]+|depends on|after #?[0-9]+ lands|gated on|hard[ -]?block on|pending in|awaits?|waiting on)'

# #1139: an issue body legitimately references a now-closed issue as historical
# context ("#161 CLOSED, a valid historical anchor", "post-#673", "#250
# superseded", "gated on #88 ... both shipped"). check_xref skips a closed-ref
# flag when every blocker-phrase line mentioning the ref also carries a
# resolution signal; a genuine stale blocker (no such signal) still flags.
XREF_RESOLUTION_SIGNALS='closed|shipped|landed|resolved|merged|satisfied|superseded|folded|unblocked|historical|post-#|since #|already'

# --- Shipped release tags (CHECK 5: label drift) ----------------------
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

# The auto-generated staleness tracker issue (filed/updated by
# .github/workflows/issue-body-staleness.yml) must NOT be scanned: its body IS
# this report, so it always cites the phantom paths it is reporting and carries
# no kind label. Scanning it keeps the scan perpetually non-zero, so the
# workflow's "close when clean" step can never fire and the tracker can never
# close (#1302). Keep this string in sync with TITLE in the workflow.
TRACKER_TITLE="Issue body staleness tracker (auto-updated)"

# Numbers of open issues whose title is the tracker marker (usually 0 or 1).
# Empty in dry-run / explicit single-issue mode, so `--issue <n>` can still
# inspect the tracker on demand.
tracker_issue_numbers() {
    if $DRY_RUN || [ -n "$SINGLE_ISSUE" ]; then
        return 0
    fi
    gh issue list -R "$REPO" --state open --limit 200 --json number,title \
        -q ".[] | select(.title == \"$TRACKER_TITLE\") | .number" 2>/dev/null
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

# Returns the column list for a given table by scanning every .swift file
# under the schema source DIRECTORY passed in. Columns come from two
# places, unioned: the `CREATE TABLE <table> (...)` block (first token per
# row, constraints dropped) and later `ALTER TABLE <table> ADD COLUMN
# <col>` statements (migrations). #1137: a single file misses columns
# added by migrations or defined in sibling files, which false-flagged
# correct issue bodies (e.g. docs_metadata.min_ios / .kind). Matching
# stays table-name scoped, so search + packages schemas can share a dir.
schema_columns_for() {
    local table="$1" schema_dir="$2"
    [ -n "$schema_dir" ] || return
    [ -d "$schema_dir" ] || return
    {
        # CREATE TABLE columns, across every .swift in the dir.
        find "$schema_dir" -name '*.swift' -type f -exec awk -v t="$table" '
            FNR == 1 { inside = 0 }
            $0 ~ "CREATE (VIRTUAL )?TABLE (IF NOT EXISTS )?" t " *\\(|CREATE (VIRTUAL )?TABLE (IF NOT EXISTS )?" t "\\(" { inside = 1; next }
            inside && $0 ~ /^[[:space:]]*\);/ { inside = 0 }
            inside {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if ($0 == "" || $0 ~ /^--/) next
                split($0, parts, /[[:space:]]+|,/)
                col = parts[1]
                if (col ~ /^(PRIMARY|FOREIGN|UNIQUE|CHECK|CONSTRAINT|CREATE)/) next
                gsub(/[",;()]/, "", col)
                if (col != "") print col
            }
        ' {} +
        # ALTER TABLE <table> ADD COLUMN <col>, across every .swift in the dir.
        grep -rhoE "ALTER TABLE ${table} ADD COLUMN [A-Za-z_][A-Za-z0-9_]*" "$schema_dir" 2>/dev/null \
            | awk '{ print $NF }'
        # INSERT [OR REPLACE] INTO <table> (col, col, ...) explicit column lists.
        # Robust to CREATE-TABLE formatting and FTS5 virtual tables: if code
        # inserts into a column, the column exists (#1137). Newlines are
        # flattened first so multi-line INSERT column lists (e.g. doc_symbols)
        # are captured.
        find "$schema_dir" -name '*.swift' -type f -exec cat {} + 2>/dev/null | tr '\n' ' ' \
            | grep -oE "INSERT (OR REPLACE |OR IGNORE )?INTO ${table} *\([^)]*\)" \
            | grep -oE '\([^)]*\)' | tr -d '()' | tr ',' '\n' \
            | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
            | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' || true
    } | sort -u
}

# --- Per-issue checks ------------------------------------------------

check_renamed() {
    local n="$1" body="$2"
    local hits=""
    # Pre-strip legitimate `Packages/Sources/` prefixes to a sentinel so
    # "missing Packages/ prefix" patterns (those starting with `Sources/`)
    # only fire on genuinely-bare references. Without this, a body that
    # correctly cites `Packages/Sources/TUI/Foo.swift` substring-matches
    # the `Sources/TUI/` rename-map entry and gets falsely flagged.
    # Sentinel choice: `__PKG_PREFIX_OK__` (no regex metachars, never
    # appears in legitimate bodies). Origin: #886.
    local body_clean
    body_clean=$(echo "$body" | sed 's|Packages/Sources/|__PKG_PREFIX_OK__|g')
    while IFS=$'\t' read -r pat hint; do
        [ -z "$pat" ] && continue
        # Detect missing-prefix patterns by their leading `Sources/`
        # literal. For those, search the sentinel-stripped body so the
        # match counts only bare references.
        local search="$body"
        if [[ "$pat" == 'Sources/'* ]]; then
            search="$body_clean"
        fi
        if echo "$search" | grep -qE "$pat"; then
            local sample
            sample=$(echo "$search" | grep -oE "$pat" | head -1)
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
        [ "$state" = "CLOSED" ] || continue
        # #1139: skip when every blocker-phrase line mentioning this ref also
        # carries a resolution signal (the body annotates the dep as done /
        # shipped / superseded). A genuine stale blocker, where the ref is
        # cited as pending with no such signal, still flags.
        local blocker_lines unresolved
        blocker_lines=$(echo "$body" | grep -iE "$BLOCKER_PHRASES" | grep -E "#${num}([^0-9]|$)")
        unresolved=$(echo "$blocker_lines" | grep -ivE "$XREF_RESOLUTION_SIGNALS" || true)
        [ -z "$unresolved" ] && continue
        hits+="    - blocker context references ${ref} which is CLOSED; body may be claiming a closed dep is still pending"$'\n'
    done <<<"$lines"
    if [ -n "$hits" ]; then
        echo "  - **#$n** (stale cross-refs):"
        printf "%s" "$hits"
    fi
}

# #1137: an issue body may legitimately cite a `<table>.<col>` that does not
# exist yet (a proposed new column) or that used to exist and was relocated.
# The schema check skips a missing-column flag when EVERY line mentioning the
# ref carries one of these intentional-absence signals; a genuine stale claim
# (the ref appears on at least one unsignaled line) still flags.
SCHEMA_ABSENCE_SIGNALS='proposed|new column|does not exist|doesn.t exist|not an existing|relocated|moved to|lives? on|shadow table|originally-stale'

check_schema() {
    local n="$1" body="$2"
    local hits=""
    for table in "${SCHEMA_TABLES[@]}"; do
        local refs
        refs=$(echo "$body" | grep -oE "${table}\.[a-z_]+" | sort -u)
        [ -z "$refs" ] && continue
        local schema_dir
        schema_dir=$(schema_source_for "$table")
        [ -z "$schema_dir" ] && continue
        [ -d "$schema_dir" ] || continue
        local cols
        cols=$(schema_columns_for "$table" "$schema_dir")
        while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            local col="${ref#${table}.}"
            if ! echo "$cols" | grep -qx "$col"; then
                local unsignaled
                unsignaled=$(echo "$body" | grep -F "$ref" | grep -ivE "$SCHEMA_ABSENCE_SIGNALS" || true)
                [ -z "$unsignaled" ] && continue
                hits+="    - \`${ref}\` → column \`${col}\` not found in \`${table}\` (searched \`${schema_dir}\`)"$'\n'
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
# Four sub-checks across all open + closed issues. These are NOT
# per-issue body parses; they operate on the label list directly.
#
# 5a. Dead `blocked_by_<N>` labels where #N is CLOSED.
# 5b. `fix-in: v<X.Y.Z>` labels for SHIPPED_VERSIONS (rename / delete).
# 5c. Single-carrier labels (1 open issue carries it); grow or fold.
# 5d. Open issues missing a kind label (enhancement / bug / epic).
#
# Previously included a 5e "missing priority" sub-check. Dropped
# 2026-05-17 when the label set trimmed to 5 (bug / enhancement /
# epic / priority: high / good first issue). Priority is now
# presence/absence, not a required axis, so the check no longer
# applies.
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

    # 5c. Single-carrier labels (1 open carrier, neither cluster nor footnote)
    while IFS= read -r lbl; do
        [ -z "$lbl" ] && continue
        # Skip the canonical 5-label set; they are axes, not topical.
        # The set: bug / enhancement / epic / priority: high / good first issue.
        case "$lbl" in
            priority:*|"released-in:"*|"fix-in:"*|"fixed: "*|enhancement|bug|epic|"good first issue")
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

    # 5d. Per-open-issue: missing kind label
    local issues_json
    issues_json=$(gh issue list -R "$REPO" --state open --limit 200 --json number,labels,title 2>/dev/null)
    local missing_kind
    # Exclude the auto-generated tracker: it is deliberately unlabeled (#1302).
    missing_kind=$(echo "$issues_json" | jq -r --arg tracker "$TRACKER_TITLE" \
        '.[] | select(.title != $tracker) | select(([.labels[].name] | map(test("^(enhancement|bug|epic)$")) | any) | not) | .number')
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        report+="    - #${n} → missing kind label (no enhancement / bug / epic)."$'\n'
    done <<<"$missing_kind"

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
EXCLUDED_ISSUES=$(tracker_issue_numbers)
total=$(echo "$issues" | wc -l | tr -d ' ')
echo "Scanning $total open issues..." >&2

# Label drift is global, run once, not per-issue
if [ "$CHECK" = "all" ] || [ "$CHECK" = "labels" ]; then
    LABEL_REPORT=$(check_labels_global)
fi

for n in $issues; do
    # Never body-scan the auto-generated tracker (#1302).
    case " $EXCLUDED_ISSUES " in *" $n "*) continue ;; esac
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
    echo "Bodies reference \`<table>.<column>\` shapes that don't match the current schema. Per-table schema sources: \`${SCHEMA_SEARCH}\` (search.db), \`${SCHEMA_PACKAGES}\` (packages.db), \`${SCHEMA_SAMPLES}\` (samples.db)."
    echo ""
    printf "%s" "$SCHEMA_REPORT"
    echo ""
fi

if [ -n "$LABEL_REPORT" ]; then
    DRIFT=true
    echo "## Label drift (check 5)"
    echo ""
    echo "Tracker-level label problems: orphan \`blocked_by_<N>\` (referenced issue closed), \`fix-in: v<X.Y.Z>\` for shipped versions, single-carrier topical labels (grow or fold), and open issues missing a kind label (no bug / enhancement / epic). Shipped versions are maintained in the script's \`SHIPPED_VERSIONS\` list, bump it when a new release tag drops."
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
