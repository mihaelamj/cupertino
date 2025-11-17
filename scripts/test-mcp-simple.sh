#!/bin/bash
# Simple MCP Server Test
# Sends a single request and shows the response

echo "🧪 Quick MCP Server Test"
echo ""

# Test: List resources
echo "Sending resources/list request..."
echo ""

echo '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "resources/list",
  "params": {}
}' | timeout 5 .build/debug/cupertino-mcp serve 2>&1

echo ""
echo "Test complete!"
echo ""
echo "If you see JSON-RPC response above, the server is working!"
echo "If you see resource URIs, documentation is being served correctly."
