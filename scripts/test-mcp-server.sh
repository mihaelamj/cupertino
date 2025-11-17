#!/bin/bash
# Test script for Cupertino MCP Server
# This script sends test requests to verify the server is working correctly

set -e

echo "🧪 Testing Cupertino MCP Server"
echo "================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if cupertino-mcp exists
if ! command -v .build/debug/cupertino-mcp &> /dev/null; then
    echo -e "${RED}❌ cupertino-mcp not found${NC}"
    echo "   Build it first: swift build --product cupertino-mcp"
    exit 1
fi

echo -e "${GREEN}✅ Found cupertino-mcp${NC}"
echo ""

# Test 1: Initialize request
echo "Test 1: Initialize"
echo "------------------"
INIT_REQUEST='{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "resources": {}
    },
    "clientInfo": {
      "name": "test-client",
      "version": "1.0.0"
    }
  }
}'

echo "$INIT_REQUEST" | .build/debug/cupertino-mcp serve 2>/dev/null | {
    read -r response
    if echo "$response" | grep -q '"result"'; then
        echo -e "${GREEN}✅ Initialize successful${NC}"
        echo "$response" | python3 -m json.tool 2>/dev/null | head -20
    else
        echo -e "${RED}❌ Initialize failed${NC}"
        echo "$response"
        exit 1
    fi
}
echo ""

# Test 2: List resources
echo "Test 2: List Resources"
echo "----------------------"
LIST_REQUEST='{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "resources/list",
  "params": {}
}'

echo "$LIST_REQUEST" | .build/debug/cupertino-mcp serve 2>/dev/null | {
    read -r response
    if echo "$response" | grep -q '"result"'; then
        echo -e "${GREEN}✅ List resources successful${NC}"
        resource_count=$(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('result', {}).get('resources', [])))" 2>/dev/null || echo "0")
        echo "   Found $resource_count resources"

        if [ "$resource_count" -gt 0 ]; then
            echo "   First 3 resources:"
            echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
resources = data.get('result', {}).get('resources', [])
for r in resources[:3]:
    print(f\"   - {r.get('uri', 'unknown')}: {r.get('name', 'unknown')}\")
" 2>/dev/null
        else
            echo -e "${YELLOW}⚠️  No resources found. Did you download documentation first?${NC}"
            echo "   Run: cupertino crawl --max-pages 10 --output-dir ~/.cupertino/docs"
        fi
    else
        echo -e "${RED}❌ List resources failed${NC}"
        echo "$response"
        exit 1
    fi
}
echo ""

# Test 3: List resource templates
echo "Test 3: List Resource Templates"
echo "--------------------------------"
TEMPLATE_REQUEST='{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "resources/templates/list",
  "params": {}
}'

echo "$TEMPLATE_REQUEST" | .build/debug/cupertino-mcp serve 2>/dev/null | {
    read -r response
    if echo "$response" | grep -q '"result"'; then
        echo -e "${GREEN}✅ List templates successful${NC}"
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
templates = data.get('result', {}).get('resourceTemplates', [])
for t in templates:
    print(f\"   - {t.get('uriTemplate', 'unknown')}\")
    print(f\"     {t.get('description', '')}\")
" 2>/dev/null
    else
        echo -e "${RED}❌ List templates failed${NC}"
        echo "$response"
        exit 1
    fi
}
echo ""

# Test 4: Read a resource (if any exist)
echo "Test 4: Read Resource (if available)"
echo "-------------------------------------"

# Try to get first resource URI
FIRST_URI=$(echo "$LIST_REQUEST" | .build/debug/cupertino-mcp serve 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    resources = data.get('result', {}).get('resources', [])
    if resources:
        print(resources[0].get('uri', ''))
except:
    pass
" 2>/dev/null)

if [ -n "$FIRST_URI" ]; then
    READ_REQUEST=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "resources/read",
  "params": {
    "uri": "$FIRST_URI"
  }
}
EOF
)

    echo "   Reading: $FIRST_URI"
    echo "$READ_REQUEST" | .build/debug/cupertino-mcp serve 2>/dev/null | {
        read -r response
        if echo "$response" | grep -q '"result"'; then
            echo -e "${GREEN}✅ Read resource successful${NC}"
            content_length=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
contents = data.get('result', {}).get('contents', [])
if contents and 'text' in contents[0]:
    print(len(contents[0]['text']))
" 2>/dev/null || echo "0")
            echo "   Content length: $content_length characters"
        else
            echo -e "${RED}❌ Read resource failed${NC}"
            echo "$response"
        fi
    }
else
    echo -e "${YELLOW}⚠️  Skipped (no resources available)${NC}"
fi
echo ""

# Summary
echo "================================"
echo "🎉 MCP Server Test Complete"
echo ""
echo "Next steps:"
echo "1. If no resources found, download docs:"
echo "   cupertino crawl --max-pages 10 --output-dir ~/.cupertino/docs"
echo ""
echo "2. Configure Claude Desktop:"
echo "   Edit ~/Library/Application Support/Claude/claude_desktop_config.json"
echo ""
echo "3. Add this configuration:"
echo '   {
     "mcpServers": {
       "cupertino": {
         "command": "/usr/local/bin/cupertino-mcp",
         "args": ["serve"]
       }
     }
   }'
echo ""
echo "4. Restart Claude Desktop"
