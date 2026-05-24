#!/usr/bin/env bash
# CLI surface smoke test for the cupertino binary.
#
# Where mcp-smoke.sh and mock-ai-agent-smoke.sh exercise the MCP server
# surface, this script exercises the cupertino CLI's user-facing
# subcommands (version, doctor, search, read, list-frameworks,
# inheritance). Representative of the real-world flow a developer
# follows: install cupertino, run setup, then query the docs index
# from the command line.
#
# Runs against the dev base directory (`~/.cupertino-dev/`); requires
# the release-mode binary built via `make build-release`.
#
# Exit codes:
#   0 - all CLI probes pass
#   1 - any probe failed
set -euo pipefail

BINARY="${CUPERTINO_BINARY:-Packages/.build/release/cupertino}"

if [ ! -x "$BINARY" ]; then
  echo "❌ Binary not found at $BINARY. Run 'cd Packages && make build-release' first."
  exit 1
fi

echo "🧪 CLI smoke test against $BINARY"
echo

OK='\033[32m✓\033[0m'
FAIL='\033[31m✗\033[0m'
errors=0
assert() {
  if [ "$1" -eq 0 ]; then
    printf "  %b %s\n" "$OK" "$2"
  else
    printf "  %b %s\n" "$FAIL" "$2"
    errors=$((errors + 1))
  fi
}

# Probe 1: --version returns a non-empty semver-shape string.
VERSION_OUT="$("$BINARY" --version 2>&1 | tail -1)"
echo "Probe 1: version"
[ -n "$VERSION_OUT" ]; assert $? "version output non-empty (got '$VERSION_OUT')"
[[ "$VERSION_OUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; assert $? "version is semver-shaped"
echo

# Probe 2: doctor reports all 3 DBs healthy.
DOCTOR_OUT="$("$BINARY" doctor 2>&1)"
echo "Probe 2: doctor"
grep -q "MCP Server" <<< "$DOCTOR_OUT"; assert $? "doctor reports MCP Server section"
grep -q "search.db" <<< "$DOCTOR_OUT"; assert $? "doctor reports search.db"
grep -q "samples.db" <<< "$DOCTOR_OUT"; assert $? "doctor reports samples.db"
grep -q "packages.db" <<< "$DOCTOR_OUT"; assert $? "doctor reports packages.db"
echo

# Probe 3: search returns hits for a canonical query.
SEARCH_OUT="$("$BINARY" search "View" --limit 3 2>&1)"
echo "Probe 3: search 'View'"
grep -q "Searched:" <<< "$SEARCH_OUT"; assert $? "search output contains 'Searched:' marker"
grep -q "apple-docs://" <<< "$SEARCH_OUT"; assert $? "search results include apple-docs URIs"
echo

# Probe 4: read returns content for a known URI.
READ_OUT="$("$BINARY" read 'apple-docs://swiftui/view' --format markdown 2>&1)"
echo "Probe 4: read apple-docs://swiftui/view"
[ "$(echo "$READ_OUT" | wc -c | tr -d ' ')" -gt 500 ]; assert $? "read body non-trivial size ($(echo "$READ_OUT" | wc -c | tr -d ' ') chars)"
grep -q "swiftui/view" <<< "$READ_OUT"; assert $? "read body references the URI's framework path"
echo

# Probe 5: list-frameworks returns at least 100 framework names.
FRAMEWORKS_OUT="$("$BINARY" list-frameworks 2>&1)"
echo "Probe 5: list-frameworks"
grep -q "Available Frameworks" <<< "$FRAMEWORKS_OUT"; assert $? "list-frameworks header present"
LINES=$(echo "$FRAMEWORKS_OUT" | wc -l | tr -d ' ')
[ "$LINES" -gt 100 ]; assert $? "list-frameworks returns >100 lines (got $LINES)"
echo

# Probe 6: inheritance walks the UIButton ancestor chain.
INHERIT_OUT="$("$BINARY" inheritance UIButton --direction up --depth 3 2>&1)"
echo "Probe 6: inheritance UIButton up"
grep -q "uicontrol" <<< "$INHERIT_OUT"; assert $? "inheritance chain contains UIControl"
grep -q "uiview" <<< "$INHERIT_OUT"; assert $? "inheritance chain contains UIView"
echo

if [ "$errors" -eq 0 ]; then
  echo "✅ CLI smoke passed."
  exit 0
else
  echo "❌ CLI smoke failed ($errors assertion(s))."
  exit 1
fi
