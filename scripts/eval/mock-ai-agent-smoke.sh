#!/usr/bin/env bash
# End-to-end smoke for the cupertino MCP server via the mock-ai-agent client.
#
# Where `mcp-smoke.sh` exercises raw JSON-RPC over a direct pipe and asserts
# on response shape, this script verifies that the full mock-ai-agent demo
# flow (initialize -> notifications/initialized -> tools/list -> tools/call
# -> resources/list -> resources/read -> shutdown) completes against a
# real `cupertino serve` server, end-to-end, with no timeouts.
#
# Closes issue #1004: the `Task.yield()` fix landed in PR #1005 unblocks
# subsequent stdin writes that pre-fix never reached the server's read loop.
#
# Runs against the dev base directory (`~/.cupertino-dev/`); requires the
# release-mode binary built via `make build-release`.
#
# Exit codes:
#   0 - mock-ai-agent flow completed (exit 0 + "Mock AI Agent Complete" marker)
#   1 - timeout, crash, or missing completion marker
set -euo pipefail

BINARY="${CUPERTINO_BINARY:-Packages/.build/release/cupertino}"
AGENT="${MOCK_AI_AGENT_BINARY:-Packages/.build/release/mock-ai-agent}"
LOG="${TMPDIR:-/tmp}/mock-ai-agent-smoke-$$.log"
trap 'rm -f "$LOG"' EXIT

for bin in "$BINARY" "$AGENT"; do
  if [ ! -x "$bin" ]; then
    echo "❌ Binary not found at $bin. Run 'cd Packages && make build-release' first."
    exit 1
  fi
done

TIMEOUT_PREFIX=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX="timeout 90"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX="gtimeout 90"
fi

echo "🧪 mock-ai-agent end-to-end smoke against $BINARY"
echo

# --quiet suppresses raw JSON dumps + base64 icon blob; --response-timeout 60
# absorbs cold-start budget on slower CI runners. The mock-ai-agent demo
# completes successfully when the trailing "Mock AI Agent Complete" line
# appears in its stdout.
$TIMEOUT_PREFIX "$AGENT" --quiet --response-timeout 60 "$BINARY" serve > "$LOG" 2>&1 || true

echo "captured: $(wc -c < "$LOG" | tr -d ' ') bytes"
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

grep -q "Initialized with server: cupertino" "$LOG"; assert $? "initialize handshake completes"
grep -q "Initialized notification sent" "$LOG"; assert $? "notifications/initialized sent"
grep -q "Found 12 tools:" "$LOG"; assert $? "tools/list returns 12 tools"
grep -q "Tool execution complete" "$LOG"; assert $? "tools/call (search) completes"
grep -q "Resource read complete" "$LOG"; assert $? "resources/read completes"
grep -q "Shutdown notification sent" "$LOG"; assert $? "shutdown notification sent"
grep -q "Mock AI Agent Complete" "$LOG"; assert $? "full flow reaches completion marker"
! grep -q "❌ Error:" "$LOG"; assert $? "no ❌ Error lines in output"

echo
if [ "$errors" -eq 0 ]; then
  echo "✅ mock-ai-agent smoke passed."
  exit 0
else
  echo "❌ mock-ai-agent smoke failed ($errors assertion(s)). Last 30 lines of log:"
  tail -30 "$LOG"
  exit 1
fi
