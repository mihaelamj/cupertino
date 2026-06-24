#!/usr/bin/env bash
#
# check-db-quality.sh
#
# Semantic-quality gate for the per-source documentation databases.
# Catches "the DB has the right schema and opens fine, but its CONTENT
# is rotten" — the failure mode a schema/integrity check sails straight
# past.
#
# Origin: 2026-06-21. A re-crawl + rebuild of hig.db looked healthy
# (`save` reported "177 documents", integrity_check=ok, schema 18) yet
# the shipped v1.3.0 hig.db carried 346 rows of which 173 were
# `…-appledeveloperdocumentation` placeholder duplicates — the "Apple
# Developer Documentation" stub pages the #284 js-fallback filter is
# supposed to reject. They sat in `docs_structured` (inflating
# list-frameworks counts) while never entering `docs_fts` (so search
# never returned them, which is exactly why nobody noticed). The
# re-crawl exposed two compounding bugs:
#
#   1. `cupertino save --clear` rebuilds the FTS but NOT the
#      `docs_structured` rich-data table, so stale/junk rows survive.
#   2. `cupertino fetch --start-clean` ignores the saved crawl SESSION
#      but does NOT wipe the output corpus directory, so a crawl whose
#      filename convention changed leaves orphaned files behind
#      (swift-evolution: 429 old `NNNN-slug.md` + 488 new `SE-NNNN.md`
#      = 917 accumulated).
#
# The guaranteed-clean rebuild recipe (see docs/database-quality-checks.md):
#   rm -rf  ~/.cupertino/<source>/        # wipe corpus dir
#   cupertino fetch --source <source> --start-clean
#   rm -f   ~/.cupertino/<source>.db      # wipe DB (so docs_structured rebuilds)
#   cupertino save  --source <source>
#   scripts/check-db-quality.sh           # prove it
#
# THE INVARIANT this check enforces:
#
#   For every docs-schema database, `docs_structured` and `docs_fts`
#   hold the SAME population (ratio ~= 1.00). A page that is counted
#   (structured) but not searchable (fts) is junk by construction —
#   either a placeholder stub or a stale row a non-clean rebuild left
#   behind. Healthy DBs measured 2026-06-21: apple-documentation
#   363562/363566, swift-evolution 487/487, swift-org 469/469,
#   apple-archive 368/368, swift-book 43/43 — all 1.00. The rotten old
#   hig.db measured 346/173 = 2.00.
#
# Plus two exact-pattern detectors for the specific junk seen:
#   - URIs ending in a known placeholder suffix (-appledeveloperdocumentation)
#   - titles equal to the placeholder string "Apple Developer Documentation"
#
# Read-only. Never writes to any database.
#
# Usage:
#   scripts/check-db-quality.sh [DB_DIR]
#   DB_DIR defaults to ~/.cupertino
#
# Exit codes:
#   0   every docs-schema DB is clean
#   1   at least one DB failed a quality check (junk / orphan rows)
#   2   invocation error (no sqlite3, dir missing, no DBs found)

set -euo pipefail

# --- config: thresholds and known junk patterns -----------------------------

# Maximum allowed excess of docs_structured over docs_fts. Healthy is
# 1.00; a small slack absorbs legitimate non-indexed edge rows. The
# rotten hig.db was 2.00, so 1.02 is comfortably discriminating.
MAX_STRUCT_FTS_RATIO="1.02"

# URI suffixes that mark a placeholder-duplicate page (extend as new
# placeholder shapes are discovered; the suffix is matched with a
# leading '-').
PLACEHOLDER_SUFFIXES=("appledeveloperdocumentation")

# Title strings that mark an Apple "JS-disabled" placeholder page.
PLACEHOLDER_TITLES=("Apple Developer Documentation")

# --- preflight --------------------------------------------------------------

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "error: sqlite3 not found on PATH" >&2
    exit 2
fi

DB_DIR="${1:-$HOME/.cupertino}"
if [[ ! -d "$DB_DIR" ]]; then
    echo "error: DB dir not found: $DB_DIR" >&2
    exit 2
fi

shopt -s nullglob
DBS=("$DB_DIR"/*.db)
if [[ ${#DBS[@]} -eq 0 ]]; then
    echo "error: no .db files in $DB_DIR" >&2
    exit 2
fi

# --- helpers ----------------------------------------------------------------

# sql DB QUERY -> prints scalar result, or empty on error
sql() { sqlite3 "$1" "$2" 2>/dev/null || true; }

# has_table DB TABLE -> exit 0 if table exists
has_table() {
    local n
    n="$(sql "$1" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$2';")"
    [[ "${n:-0}" -gt 0 ]]
}

# --- main -------------------------------------------------------------------

echo "DB quality check — $DB_DIR"
echo

fail=0
checked=0

for db in "${DBS[@]}"; do
    name="$(basename "$db")"

    # docs-schema databases only (the placeholder-junk disease is
    # specific to the docs_structured + docs_fts shape). packages.db /
    # apple-sample-code.db use other schemas and are out of scope here.
    if ! has_table "$db" docs_structured || ! has_table "$db" docs_fts; then
        printf "  %-24s skip (not a docs-schema DB)\n" "$name"
        continue
    fi
    checked=$((checked + 1))

    structured="$(sql "$db" "SELECT COUNT(*) FROM docs_structured;")"
    fts="$(sql "$db" "SELECT COUNT(*) FROM docs_fts;")"
    structured="${structured:-0}"
    fts="${fts:-0}"

    db_fail=0
    reasons=()

    # 1. structured/fts population invariant
    if [[ "$fts" -eq 0 ]]; then
        if [[ "$structured" -gt 0 ]]; then
            db_fail=1; reasons+=("fts empty but structured=$structured")
        fi
    else
        over="$(awk -v s="$structured" -v f="$fts" -v m="$MAX_STRUCT_FTS_RATIO" \
            'BEGIN{print (s > f*m) ? 1 : 0}')"
        if [[ "$over" -eq 1 ]]; then
            ratio="$(awk -v s="$structured" -v f="$fts" 'BEGIN{printf "%.2f", s/f}')"
            orphans=$((structured - fts))
            db_fail=1
            reasons+=("structured/fts ratio $ratio (~$orphans rows counted but not searchable)")
        fi
    fi

    # 2. placeholder-suffix junk URIs
    for suf in "${PLACEHOLDER_SUFFIXES[@]}"; do
        n="$(sql "$db" "SELECT COUNT(*) FROM docs_structured WHERE uri LIKE '%-$suf';")"
        if [[ "${n:-0}" -gt 0 ]]; then
            db_fail=1; reasons+=("$n placeholder-suffix URIs (-$suf)")
        fi
    done

    # 3. placeholder-titled pages
    for t in "${PLACEHOLDER_TITLES[@]}"; do
        n="$(sql "$db" "SELECT COUNT(*) FROM docs_structured WHERE title='${t//\'/\'\'}';")"
        if [[ "${n:-0}" -gt 0 ]]; then
            db_fail=1; reasons+=("$n placeholder-titled pages ('$t')")
        fi
    done

    # 4. FTS index is actually queryable, not just row-counted.
    #    Checks 1-3 read `COUNT(*) FROM docs_fts`, which touches the FTS5
    #    content rows but never exercises the index b-tree. A corrupt or
    #    unbuilt FTS index can count fine yet throw on the first real
    #    MATCH — the failure a user hits at search time, which this gate
    #    (pre-MATCH) sailed straight past (the #1276 class). Run one real
    #    MATCH and fail if SQLite reports any error; a zero-hit result is
    #    fine — we only care that the query runs, not that 'swift' matches.
    if [[ "$fts" -gt 0 ]]; then
        match_err="$(sqlite3 "$db" "SELECT COUNT(*) FROM docs_fts WHERE docs_fts MATCH 'swift';" 2>&1 >/dev/null || true)"
        if [[ -n "$match_err" ]]; then
            db_fail=1; reasons+=("FTS MATCH query failed (corrupt/unbuilt index): $match_err")
        fi
    fi

    if [[ "$db_fail" -eq 0 ]]; then
        printf "  %-24s PASS  (structured=%s fts=%s)\n" "$name" "$structured" "$fts"
    else
        printf "  %-24s FAIL  (structured=%s fts=%s)\n" "$name" "$structured" "$fts"
        for r in "${reasons[@]}"; do
            printf "       └─ %s\n" "$r"
        done
        fail=1
    fi
done

echo
if [[ "$checked" -eq 0 ]]; then
    echo "error: no docs-schema DBs found in $DB_DIR" >&2
    exit 2
fi

if [[ "$fail" -eq 0 ]]; then
    echo "✅ all $checked docs-schema database(s) clean"
    exit 0
else
    echo "❌ quality check failed — see FAIL rows above"
    echo "   guaranteed-clean rebuild: wipe BOTH ~/.cupertino/<source>/ and"
    echo "   ~/.cupertino/<source>.db, then fetch --start-clean and save."
    echo "   (docs/database-quality-checks.md)"
    exit 1
fi
