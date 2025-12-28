#!/bin/bash
#
# Test: Verify install.sh uses echo -e for all color codes
#
# This prevents regression of issue #124 where ANSI escape
# sequences were displayed as literal text.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/../install.sh"

echo "Testing install.sh for ANSI escape sequence issues..."

# Check for echo statements with color variables that are missing -e flag
# Pattern: echo " (without -e) followed by content containing ${COLOR} or ${NC}
BROKEN_LINES=$(grep -n 'echo "[^"]*\${' "$INSTALL_SCRIPT" | grep -v 'echo -e' || true)

if [[ -n "$BROKEN_LINES" ]]; then
    echo "ERROR: Found echo statements with color codes missing -e flag:"
    echo "$BROKEN_LINES"
    echo ""
    echo "Fix: Change 'echo' to 'echo -e' for lines with color variables"
    exit 1
fi

echo "✓ All echo statements with color codes use -e flag"
exit 0
