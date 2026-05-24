#!/usr/bin/env bash
# MCP smoke test for the cupertino MCP server.
#
# Verifies that `cupertino serve` exposes the MCP protocol surface
# correctly for: (1) initialize handshake, (2) notifications/initialized
# acknowledgement, (3) tools/list returns 12 tool descriptors,
# (4) tools/call name=search returns a non-empty result body with the
# expected semantic markers.
#
# Runs against the dev base directory (`~/.cupertino-dev/`); requires
# the release-mode binary built via `make build-release`. Uses a direct
# JSON-RPC stdio pipe rather than mock-ai-agent because of a known
# stall in mock-ai-agent's reader after the first response (#TODO file
# issue).
#
# Exit codes:
#   0 - all four MCP probes pass
#   1 - any probe failed (initialize / tools/list / tools/call shape)
set -euo pipefail

BINARY="${CUPERTINO_BINARY:-Packages/.build/release/cupertino}"
LOG="${TMPDIR:-/tmp}/mcp-smoke-$$.log"
trap 'rm -f "$LOG"' EXIT

if [ ! -x "$BINARY" ]; then
  echo "❌ Binary not found at $BINARY. Run 'cd Packages && make build-release' first."
  exit 1
fi

echo "🧪 MCP smoke test against $BINARY"
echo

# Server stderr is captured to a sibling log so a premature exit
# (e.g. missing DB at the dev base directory) shows up here instead
# of being silently swallowed and reported as a broken-pipe upstream.
ERRLOG="${LOG}.stderr"
trap 'rm -f "$LOG" "$ERRLOG"' EXIT

# Send three JSON-RPC messages over stdio: initialize, tools/list, tools/call.
# Each is on its own line per the MCP stdio framing rule. Sleep windows
# give the server time to respond before the next message lands.
# `|| true` on the subshell suppresses the SIGPIPE exit (EPIPE = 141)
# we get if cupertino serve exits early; the assertion block below
# catches the real failure mode (missing responses in $LOG) and the
# stderr block surfaces the underlying cause.
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"mcp-smoke","version":"1"}}}'
  sleep 8  # cold-start budget
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' 2>/dev/null || true
  sleep 1
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' 2>/dev/null || true
  sleep 5
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":"NSURLSession","limit":3}}}' 2>/dev/null || true
  sleep 10  # query execution budget
} | timeout 60 "$BINARY" serve 2>"$ERRLOG" > "$LOG" || true

# If the server log is empty or near-empty, the server died early.
# Surface its stderr instead of asserting on an empty file.
if [ "$(wc -c < "$LOG" | tr -d ' ')" -lt 100 ]; then
  echo "❌ cupertino serve produced no/empty response; stderr follows:"
  echo "--- server stderr ---"
  cat "$ERRLOG"
  echo "--- end stderr ---"
  exit 1
fi

bytes=$(wc -c < "$LOG" | tr -d ' ')
echo "captured: $bytes bytes from MCP server"
echo

# Assertions per memory feedback_mcp_probe_shape_not_length: assert on
# semantic markers, not just response size.
python3 <<PY
import json, sys

OK = '\033[32m✓\033[0m'
FAIL = '\033[31m✗\033[0m'
errors = 0

def assert_(cond, label):
    global errors
    print(f"  {OK if cond else FAIL} {label}")
    if not cond: errors += 1

initialize_result = None
tools_list_result = None
tools_call_result = None
with open('$LOG') as f:
    for line in f.read().splitlines():
        if not line.startswith('{'): continue
        try:
            d = json.loads(line)
        except: continue
        if d.get('id') == 1: initialize_result = d.get('result')
        elif d.get('id') == 2: tools_list_result = d.get('result')
        elif d.get('id') == 3: tools_call_result = d.get('result')

print("Probe 1: initialize")
assert_(initialize_result is not None, "id=1 response received")
if initialize_result:
    info = initialize_result.get('serverInfo', {})
    assert_(info.get('name') == 'cupertino', f"serverInfo.name == 'cupertino' (got '{info.get('name')}')")
    assert_(info.get('version'), f"serverInfo.version present (got '{info.get('version')}')")
    assert_(initialize_result.get('protocolVersion'), "protocolVersion present")

print()
print("Probe 2: tools/list")
assert_(tools_list_result is not None, "id=2 response received")
if tools_list_result:
    tools = tools_list_result.get('tools', [])
    assert_(len(tools) == 12, f"12 tools registered (got {len(tools)})")
    tool_names = {t.get('name') for t in tools}
    for required in ['search', 'read_document', 'get_inheritance', 'search_symbols', 'list_frameworks']:
        assert_(required in tool_names, f"tools contains '{required}'")

print()
print("Probe 3: tools/call name=search")
assert_(tools_call_result is not None, "id=3 response received")
if tools_call_result:
    assert_(not tools_call_result.get('isError', False), "isError == false")
    content = tools_call_result.get('content', [])
    text = content[0].get('text', '') if content else ''
    assert_('NSURLSession' in text, "response body contains 'NSURLSession'")
    assert_('apple-docs' in text, "response body contains 'apple-docs' source marker")
    assert_(len(text) > 500, f"response body non-trivial size ({len(text)} chars)")

print()
if errors == 0:
    print("✅ MCP smoke passed.")
    sys.exit(0)
else:
    print(f"❌ MCP smoke failed ({errors} assertion(s)).")
    sys.exit(1)
PY
