#!/bin/bash
# Regenerate the embedded Swift catalog files from JSON source data.
#
# Why: since #161 we no longer ship `Cupertino_Resources.bundle` next to the
# binary. The catalog JSON files are compiled in as Swift raw-string literals
# under Packages/Sources/Resources/Embedded/. This script regenerates those
# Swift files from source JSON whenever the catalog content changes.
#
# Workflow:
#   1. Drop the updated source JSON into /tmp/catalogs/ (matching filenames:
#      priority-packages.json, archive-guides-catalog.json,
#      swift-packages-catalog.json).
#   2. Run this script.
#   3. Commit the regenerated Swift files.
#
# Note: sample-code-catalog.json is NO LONGER embedded (#215). Sample-code
# metadata is sourced from `<sample-code-dir>/catalog.json`, written at
# fetch time by `cupertino fetch --type code`. If you place a
# sample-code-catalog.json in /tmp/catalogs/, this script ignores it.
#
# Note: swift-packages-catalog.json is NO LONGER embedded (#194). The 568 KB
# URL list was deleted; the canonical Swift-packages corpus now lives in
# `packages.db` (downloaded via `cupertino setup`). If you place a
# swift-packages-catalog.json in /tmp/catalogs/, this script ignores it.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-/tmp/catalogs}"
DST="$REPO/Packages/Sources/Resources/Embedded"

if [[ ! -d "$SRC" ]]; then
    echo "Source directory not found: $SRC"
    echo "Usage: $0 [path-to-json-source-dir]"
    exit 1
fi

mkdir -p "$DST"

python3 - "$SRC" "$DST" <<'PY'
import sys, json, pathlib, re

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])

def sym(stem: str) -> str:
    parts = re.split(r'[-_]', stem)
    return ''.join(p.capitalize() for p in parts)

def emit_raw(json_path: pathlib.Path, out_path: pathlib.Path) -> None:
    raw = json_path.read_text(encoding='utf-8')
    delim = '#'
    while ('"' + delim) in raw or (delim + '"') in raw:
        delim += '#'
    sym_name = sym(json_path.stem) + 'Embedded'
    content = (
        f'// Auto-generated from {json_path.name}. Do not edit by hand.\n'
        f'// Regenerate via: Scripts/generate-embedded-catalogs.sh\n\n'
        f'import Foundation\n\n'
        f'// swiftlint:disable line_length type_body_length file_length\n'
        f'// Auto-generated raw-string-literal catalog; lint thresholds don\'t apply.\n\n'
        f'public enum {sym_name} {{\n'
        f'    public static let json: String = {delim}"""\n'
        f'{raw}\n"""{delim}\n\n'
        f'    public static var data: Data {{ Data(json.utf8) }}\n'
        f'}}\n'
    )
    out_path.write_text(content, encoding='utf-8')
    print(f'wrote {out_path.name} ({len(raw)} bytes, delim={delim})')

for json_path in sorted(src.glob('*.json')):
    # sample-code-catalog is sourced from disk at fetch time (#215);
    # never re-embed it as a Swift literal.
    if json_path.name == 'sample-code-catalog.json':
        print(f'skipping {json_path.name} (sample-code is on-disk only since #215)')
        continue
    # swift-packages-catalog is no longer embedded (#194); the canonical
    # corpus lives in packages.db (downloaded via `cupertino setup`).
    if json_path.name == 'swift-packages-catalog.json':
        print(f'skipping {json_path.name} (swift-packages is packages.db-only since #194)')
        continue
    out = dst / (sym(json_path.stem) + 'Embedded.swift')
    emit_raw(json_path, out)
PY

echo "Done. Regenerated files in: $DST"
echo "Commit the updated .swift files; do not commit the source JSON files."
