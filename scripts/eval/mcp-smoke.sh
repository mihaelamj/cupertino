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

# `timeout` is GNU coreutils (Linux); macOS has it as `gtimeout` if
# Homebrew installed coreutils, otherwise absent. Detect a portable
# wrapper so the smoke runs in CI on macos-15 (no coreutils) and on
# Linux/CI runners + dev boxes that may have either.
TIMEOUT_PREFIX=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX="timeout 90"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX="gtimeout 60"
fi
# else: no bounded-runtime helper available; rely on the calling
# environment to enforce a budget (CI sets `timeout-minutes`).

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
  sleep 8
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_document","arguments":{"uri":"apple-docs://swiftui/view"}}}' 2>/dev/null || true
  sleep 8
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_inheritance","arguments":{"symbol":"UIButton","direction":"up","depth":3}}}' 2>/dev/null || true
  sleep 5
  printf '%s\n' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_frameworks","arguments":{}}}' 2>/dev/null || true
  sleep 5
  printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"search_property_wrappers","arguments":{"wrapper":"State"}}}' 2>/dev/null || true
  sleep 8
} | $TIMEOUT_PREFIX "$BINARY" serve 2>"$ERRLOG" > "$LOG" || true

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

results = {}
with open('$LOG') as f:
    for line in f.read().splitlines():
        if not line.startswith('{'): continue
        try:
            d = json.loads(line)
        except: continue
        rid = d.get('id')
        if rid is not None: results[rid] = d.get('result')

initialize_result = results.get(1)
tools_list_result = results.get(2)
search_result = results.get(3)
read_doc_result = results.get(4)
inheritance_result = results.get(5)
list_fw_result = results.get(6)
prop_wrap_result = results.get(7)

def body_text(result):
    if not result: return ""
    content = result.get('content', [])
    return content[0].get('text', '') if content else ''

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
print("Probe 3: tools/call name=search (query=NSURLSession)")
assert_(search_result is not None, "id=3 response received")
if search_result:
    assert_(not search_result.get('isError', False), "isError == false")
    text = body_text(search_result)
    assert_('NSURLSession' in text, "response body contains 'NSURLSession'")
    assert_('apple-docs' in text, "response body contains 'apple-docs' source marker")
    assert_(len(text) > 500, f"response body non-trivial size ({len(text)} chars)")

print()
print("Probe 4: tools/call name=read_document (uri=apple-docs://swiftui/view)")
assert_(read_doc_result is not None, "id=4 response received")
if read_doc_result:
    assert_(not read_doc_result.get('isError', False), "isError == false")
    text = body_text(read_doc_result)
    assert_(len(text) > 1000, f"read_document body non-trivial size ({len(text)} chars)")
    assert_('View' in text or 'view' in text, "read_document body references View")

print()
print("Probe 5: tools/call name=get_inheritance (symbol=UIButton direction=up)")
assert_(inheritance_result is not None, "id=5 response received")
if inheritance_result:
    assert_(not inheritance_result.get('isError', False), "isError == false")
    text = body_text(inheritance_result)
    assert_('UIButton' in text, "inheritance body contains 'UIButton'")
    assert_('uicontrol' in text.lower(), "inheritance chain contains UIControl")

print()
print("Probe 6: tools/call name=list_frameworks")
assert_(list_fw_result is not None, "id=6 response received")
if list_fw_result:
    assert_(not list_fw_result.get('isError', False), "isError == false")
    text = body_text(list_fw_result)
    assert_(len(text) > 5000, f"list_frameworks body non-trivial size ({len(text)} chars)")
    for fw in ['swiftui', 'uikit', 'foundation']:
        assert_(fw in text.lower(), f"list_frameworks output mentions '{fw}'")

print()
print("Probe 7: tools/call name=search_property_wrappers (wrapper=State)")
assert_(prop_wrap_result is not None, "id=7 response received")
if prop_wrap_result:
    assert_(not prop_wrap_result.get('isError', False), "isError == false")
    text = body_text(prop_wrap_result)
    assert_('Property Wrapper:' in text, "search_property_wrappers body contains 'Property Wrapper:' marker")
    assert_('State' in text, "search_property_wrappers body contains 'State'")

print()
if errors == 0:
    print("✅ MCP smoke passed.")
    sys.exit(0)
else:
    print(f"❌ MCP smoke failed ({errors} assertion(s)).")
    sys.exit(1)
PY
