#!/usr/bin/env bash
#
# check-target-portability.sh
#
# Portability proof for a single feature target: copy the target's source
# folder plus its transitive dependency closure into a tmp directory,
# write a minimal Package.swift that lists only those targets and their
# external dependencies, then build (and optionally test) it in isolation.
#
# A green run proves the target is genuinely liftable from the monorepo:
# a downstream consumer could copy the same files into a fresh repo with
# the printed manifest and it would compile against just the declared
# deps. Anything the target reaches transitively that we haven't
# declared shows up here as a build error.
#
# This is the empirical companion to `check-package-purity.sh` (which
# audits source-level imports). Purity asks "do you import what you
# declare?"; portability asks "do you declare what you actually need?"
#
# Usage:
#
#   scripts/check-target-portability.sh <Target> [--test]
#
# Examples:
#
#   scripts/check-target-portability.sh Services
#   scripts/check-target-portability.sh Services --test
#   scripts/check-target-portability.sh Crawler
#
# Exit codes:
#   0   target builds (and tests pass, with --test) in isolation
#   1   build or test failure
#   2   invocation error

set -euo pipefail

if [ $# -lt 1 ]; then
    cat <<EOF >&2
usage: $0 <Target> [--test]

Lifts <Target> and its transitive deps into /tmp/cupertino-portability-<target>/
and builds it as a standalone Swift package.
EOF
    exit 2
fi

TARGET="$1"
RUN_TESTS="no"
if [ "${2:-}" = "--test" ]; then
    RUN_TESTS="yes"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/Packages/Package.swift"

if [ ! -f "$MANIFEST" ]; then
    echo "error: Packages/Package.swift not found at $MANIFEST" >&2
    exit 2
fi

# Resolve target + transitive deps + paths from the monorepo manifest.
# Python parses the Target.target(...) blocks rather than trying to do it
# in shell; the manifest format is regular enough that ad-hoc parsing
# stays small.
PORT_DIR="/tmp/cupertino-portability-$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')"
rm -rf "$PORT_DIR"
mkdir -p "$PORT_DIR/Sources"

python3 - "$MANIFEST" "$TARGET" "$PORT_DIR" <<'PY'
import re
import sys
import shutil
from pathlib import Path

manifest_path = Path(sys.argv[1])
target_root = sys.argv[2]
port_dir = Path(sys.argv[3])
repo_sources = manifest_path.parent / "Sources"

raw = manifest_path.read_text()
# Strip `// ...` line comments so they don't break field detection.
manifest = re.sub(r'//[^\n]*', '', raw)

# Locate Target.target(...) blocks by finding the opener and walking
# paren depth until the matching close. This handles arbitrary
# whitespace, optional fields, and nested .product(...) deps without
# fragile single-shot regex.
targets = {}
i = 0
while True:
    j = manifest.find("Target.target(", i)
    if j == -1:
        break
    # Walk paren depth from the opening paren.
    start = j + len("Target.target")
    depth = 0
    k = start
    while k < len(manifest):
        ch = manifest[k]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                break
        k += 1
    if depth != 0:
        break
    block = manifest[start + 1:k]  # inside the parens
    i = k + 1

    name_m = re.search(r'name:\s*"([^"]+)"', block)
    if not name_m:
        continue
    name = name_m.group(1)

    deps_m = re.search(r'dependencies:\s*\[', block)
    deps = []
    products = []
    if deps_m:
        # Walk bracket depth for dependencies array.
        b = deps_m.end()
        bdepth = 1
        c = b
        while c < len(block) and bdepth > 0:
            if block[c] == '[':
                bdepth += 1
            elif block[c] == ']':
                bdepth -= 1
            c += 1
        deps_raw = block[b:c - 1]
        products = re.findall(
            r'\.product\(\s*name:\s*"([^"]+)"\s*,\s*package:\s*"([^"]+)"',
            deps_raw,
        )
        deps_no_products = re.sub(r'\.product\([^)]*\)', "", deps_raw)
        deps = re.findall(r'"([^"]+)"', deps_no_products)

    path_match = re.search(r'path:\s*"([^"]+)"', block)
    exclude_match = re.search(r'exclude:\s*\[([^\]]*)\]', block)
    excludes = re.findall(r'"([^"]+)"', exclude_match.group(1)) if exclude_match else []
    targets[name] = {
        "deps": deps,
        "products": products,
        "path": path_match.group(1) if path_match else f"Sources/{name}",
        "excludes": excludes,
    }

if target_root not in targets:
    print(f"error: target '{target_root}' not in {manifest_path}", file=sys.stderr)
    sys.exit(2)

# BFS for production closure.
prod_closure = set()
stack = [target_root]
while stack:
    t = stack.pop()
    if t in prod_closure or t not in targets:
        continue
    prod_closure.add(t)
    stack.extend(targets[t]["deps"])

# Test-time closure adds whatever the target's tests import directly.
test_dir = manifest_path.parent / "Tests" / f"{target_root}Tests"
test_extra = set()
if test_dir.is_dir():
    for f in test_dir.rglob("*.swift"):
        for line in f.read_text(errors="ignore").splitlines():
            m = re.match(r"^(?:@testable\s+)?import\s+([A-Za-z0-9_]+)\s*$", line)
            if m and m.group(1) in targets:
                test_extra.add(m.group(1))
    # Close over their deps too.
    stack = list(test_extra)
    while stack:
        t = stack.pop()
        if t in test_extra and t in targets:
            for d in targets[t]["deps"]:
                if d not in test_extra:
                    test_extra.add(d)
                    stack.append(d)

closure = prod_closure | test_extra
# Collect external products used by anything in the closure.
external_packages = set()
for t in closure:
    for product, pkg in targets[t].get("products", []):
        external_packages.add(pkg)

# Copy source folders. Resolve unique top-level folder per target's path.
copied_top = set()
for t in closure:
    p = Path(targets[t]["path"])  # repo-relative
    abs_path = manifest_path.parent / p
    if not abs_path.is_dir():
        print(f"error: source path for {t} not found: {abs_path}", file=sys.stderr)
        sys.exit(2)
    # Copy by top-level under Sources/.
    # Several targets share a parent (e.g. Sources/Shared) — copy the
    # parent once so all sub-target paths line up.
    parts = p.parts  # ('Sources', 'Shared', 'Utils') or ('Sources', 'Services')
    if len(parts) < 2:
        continue
    top = parts[1]  # 'Services' or 'Shared'
    top_src = manifest_path.parent / "Sources" / top
    top_dst = port_dir / "Sources" / top
    if top in copied_top or top_dst.exists():
        continue
    shutil.copytree(top_src, top_dst)
    copied_top.add(top)

# Optional: copy the test folder for the candidate target.
test_target_name = f"{target_root}Tests"
test_src = manifest_path.parent / "Tests" / test_target_name
if test_src.is_dir():
    (port_dir / "Tests").mkdir(exist_ok=True)
    shutil.copytree(test_src, port_dir / "Tests" / test_target_name, dirs_exist_ok=True)

# Emit Package.swift.
def fmt_deps(deps_list, products_list):
    parts = [f'"{d}"' for d in deps_list]
    for product, pkg in products_list:
        parts.append(f'.product(name: "{product}", package: "{pkg}")')
    return ", ".join(parts)

ordered = sorted(closure)
lines = [
    "// swift-tools-version:6.0",
    f"// Portability harness for `{target_root}` — generated by scripts/check-target-portability.sh.",
    "// Mirrors the monorepo manifest entries for the target + its transitive deps.",
    "// A green build here proves the target is liftable from the monorepo without",
    "// dragging undeclared concerns along.",
    "",
    "import PackageDescription",
    "",
    "let package = Package(",
    f'    name: "{target_root}Portability",',
    "    platforms: [",
    "        .macOS(.v14),",
    "        .iOS(.v17),",
    "    ],",
    "    products: [",
    f'        .library(name: "{target_root}", targets: ["{target_root}"]),',
    "    ],",
]
if external_packages:
    lines.append("    dependencies: [")
    for pkg in sorted(external_packages):
        if pkg == "swift-syntax":
            lines.append('        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),')
        else:
            print(f"warning: no URL recipe for external package '{pkg}' — edit the script", file=sys.stderr)
    lines.append("    ],")
lines.append("    targets: [")
for t in ordered:
    cfg = targets[t]
    args = [f'name: "{t}"']
    args.append(f"dependencies: [{fmt_deps(cfg['deps'], cfg.get('products', []))}]")
    if cfg["path"] != f"Sources/{t}":
        args.append(f'path: "{cfg["path"]}"')
    if cfg["excludes"]:
        ex = ", ".join(f'"{e}"' for e in cfg["excludes"])
        args.append(f"exclude: [{ex}]")
    # Exclude README.md if present in the source (mirrors monorepo).
    src_dir = port_dir / cfg["path"]
    if (src_dir / "README.md").is_file() and not any("README" in e for e in cfg["excludes"]):
        # Re-emit with README excluded.
        args[-1] = args[-1] if cfg["excludes"] else "exclude: [\"README.md\"]"
    body = ",\n            ".join(args)
    lines.append(f"        .target(\n            {body}\n        ),")
# Test target.
if test_src.is_dir():
    test_imports = set()
    for f in test_src.rglob("*.swift"):
        for line in f.read_text(errors="ignore").splitlines():
            m = re.match(r"^(?:@testable\s+)?import\s+([A-Za-z0-9_]+)\s*$", line)
            if m and m.group(1) in targets:
                test_imports.add(m.group(1))
    test_deps = sorted(test_imports)
    deps_str = ", ".join(f'"{d}"' for d in test_deps)
    lines.append(f"        .testTarget(")
    lines.append(f'            name: "{test_target_name}",')
    lines.append(f'            dependencies: [{deps_str}]')
    lines.append(f"        ),")
lines.append("    ]")
lines.append(")")
(port_dir / "Package.swift").write_text("\n".join(lines) + "\n")

print(f"PORT_DIR={port_dir}")
print(f"PROD_CLOSURE_SIZE={len(prod_closure)}")
print(f"FULL_CLOSURE_SIZE={len(closure)}")
PY

echo ""
echo "=== building $TARGET standalone ==="
cd "$PORT_DIR"
if [ "$RUN_TESTS" = "yes" ]; then
    xcrun swift test 2>&1 | tail -10
else
    xcrun swift build 2>&1 | tail -10
fi
