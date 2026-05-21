#!/usr/bin/env bash
# test-check-issue-body-staleness.sh: fixture-based regression test for
# scripts/check-issue-body-staleness.sh.
#
# Origin: #886. The staleness checker had two false-positive patterns
# surfaced during the 2026-05-21 manual hygiene walk:
#
#   Bug 1: check_renamed used raw substring grep against the rename map.
#          Bodies that correctly cited `Packages/Sources/<X>/` still got
#          flagged for "missing Packages/ prefix" because `Sources/<X>/`
#          is a substring of the prefixed form.
#
#   Bug 2: check_schema read only search.db's schema source
#          (`Packages/Sources/Search/Search.Index.Schema.swift`). Bodies
#          citing packages.db columns (defined in PackageIndex.swift) or
#          samples.db columns (defined in Sample.Index.Database.swift)
#          got flagged as "column not found" because the script looked
#          at the wrong file.
#
# This harness builds /tmp/bodies/ with controlled fixtures covering
# (a) the false-positive cases that must NOT flag post-fix, and
# (b) the genuine-finding cases that must STILL flag post-fix, then
# runs the checker in --dry-run mode and asserts on the resulting
# report.
#
# Usage:
#   bash scripts/test-check-issue-body-staleness.sh
#
# Exit codes:
#   0: all assertions passed
#   1: one or more assertions failed
#   2: invocation error / missing tool

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT="$REPO_ROOT/scripts/check-issue-body-staleness.sh"
[ -x "$SCRIPT" ] || { echo "missing or non-executable: $SCRIPT" >&2; exit 2; }

FIXTURES_DIR=/tmp/bodies
FAILS=0
ASSERTIONS=0

fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
ok() { :; }
assert_no_match() {
    local label="$1" needle="$2" haystack="$3"
    ASSERTIONS=$((ASSERTIONS + 1))
    if echo "$haystack" | grep -q "$needle"; then
        fail "$label: expected NO match for [$needle]"
        echo "  --- offending output ---"
        echo "$haystack" | grep "$needle" | sed 's/^/  /'
    fi
}
assert_match() {
    local label="$1" needle="$2" haystack="$3"
    ASSERTIONS=$((ASSERTIONS + 1))
    if ! echo "$haystack" | grep -q "$needle"; then
        fail "$label: expected match for [$needle] but none found"
        echo "  --- haystack snapshot ---"
        echo "$haystack" | sed 's/^/  /' | head -30
    fi
}

# --- Build fixtures -------------------------------------------------------

rm -rf "$FIXTURES_DIR"
mkdir -p "$FIXTURES_DIR"

# Fixture 7: correctly-prefixed `Packages/Sources/TUI/...`.
# Pre-fix: substring match flags this as "missing Packages/ prefix".
# Post-fix: no flag.
cat > "$FIXTURES_DIR/7.md" <<'BODY'
The TUI screen lives in `Packages/Sources/TUI/Infrastructure/Screen.swift`.
No other references.
BODY

# Fixture 103: correctly-prefixed `Packages/Sources/Resources/Embedded/...`.
# Same pattern as 7.
cat > "$FIXTURES_DIR/103.md" <<'BODY'
Embedded resources are under `Packages/Sources/Resources/Embedded/Catalog.swift`.
No bare `Sources/Resources/` references in this body.
BODY

# Fixture 189: genuine bare `Sources/TUI/...` references.
# Pre-fix and post-fix: SHOULD flag.
cat > "$FIXTURES_DIR/189.md" <<'BODY'
The escape sequence tests live in `Sources/TUI/Infrastructure/Tests/EscapeTests.swift`.
The renderer test lives in `Sources/TUI/Render/Tests/RendererTests.swift`.
BODY

# Fixture 251: packages.db column `package_files.kind` (exists in PackageIndex.swift,
# not in Search.Index.Schema.swift). Pre-fix: flagged as missing.
# Post-fix: no flag for that one. We also include an actually-bad column
# (`docs_metadata.this_does_not_exist`) which MUST keep firing.
cat > "$FIXTURES_DIR/251.md" <<'BODY'
The packages.db `package_files.kind` column carries the file kind.
A genuinely-stale claim: `docs_metadata.this_does_not_exist`.
BODY

# Fixture 9001: samples.db column `file_imports.module_name` (exists in
# Sample.Index.Database.swift, not in Search.Index.Schema.swift).
# Pre-fix: flagged. Post-fix: no flag.
cat > "$FIXTURES_DIR/9001.md" <<'BODY'
Samples capture `file_imports.module_name` per source file.
BODY

# --- Run the checker ------------------------------------------------------

RENAMED_OUT=$(bash "$SCRIPT" --dry-run --check=renamed 2>/dev/null || true)
SCHEMA_OUT=$(bash "$SCRIPT" --dry-run --check=schema 2>/dev/null || true)

# --- Bug 1 assertions: rename check ---------------------------------------

# False positives (must NOT fire post-fix)
assert_no_match "rename-1a" "#7" "$RENAMED_OUT"
assert_no_match "rename-1b" "#103" "$RENAMED_OUT"

# Genuine findings (must STILL fire post-fix)
assert_match "rename-1c-genuine" "#189" "$RENAMED_OUT"
assert_match "rename-1d-genuine-hit" "Sources/TUI/" "$RENAMED_OUT"

# --- Bug 2 assertions: schema check ---------------------------------------

# False positives (must NOT fire post-fix)
assert_no_match "schema-2a" "package_files.kind" "$SCHEMA_OUT"
assert_no_match "schema-2b" "file_imports.module_name" "$SCHEMA_OUT"

# Genuine finding (must STILL fire post-fix)
assert_match "schema-2c-genuine" "docs_metadata.this_does_not_exist" "$SCHEMA_OUT"

# --- Cleanup --------------------------------------------------------------

rm -rf "$FIXTURES_DIR"

# --- Report ---------------------------------------------------------------

if [ "$FAILS" -eq 0 ]; then
    echo "PASS: $ASSERTIONS / $ASSERTIONS assertions"
    exit 0
else
    echo "FAIL: $FAILS / $ASSERTIONS assertions failed"
    exit 1
fi
