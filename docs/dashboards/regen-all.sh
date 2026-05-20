#!/usr/bin/env bash
# Regenerate every dashboard HTML from the audit markdown source.
#
# Run this after editing any audit under docs/audits/ or after a new
# audit lands. Nothing is hardcoded per-audit; the scripts derive
# everything from the markdown.
#
# Usage:
#   cd docs/dashboards/
#   ./regen-all.sh
#
# Or from anywhere:
#   bash docs/dashboards/regen-all.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "==> Per-audit dashboards"
for f in ../audits/search-quality-*-v*.md; do
    python3 _render-audit-dashboard.py "$f"
done

echo ""
echo "==> Index dashboard"
python3 _render-index-dashboard.py

echo ""
echo "Done."
