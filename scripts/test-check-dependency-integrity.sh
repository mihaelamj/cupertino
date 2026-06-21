#!/usr/bin/env bash
#
# test-check-dependency-integrity.sh: red/green test for the dependency-integrity guard.
#
# Builds throwaway fixture trees from the real manifest + lockfiles, tampers each the way
# PR #1294 did, and asserts the guard's exit code. Proves the guard is non-vacuous: it
# passes the clean tree and fails each attack shape.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GUARD="$ROOT/scripts/check-dependency-integrity.sh"
WS_REL="Main.xcworkspace/xcshareddata/swiftpm/Package.resolved"

TMPDIRS=()
cleanup() { local rc=$?; for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; return "$rc"; }
trap cleanup EXIT

pass=0; fails=0
expect() { # $1 desc  $2 expected_exit  $3 fixture_root
  set +e; "$GUARD" "$3" >/dev/null 2>&1; local rc=$?; set -e
  if [ "$rc" = "$2" ]; then echo "  PASS: $1 (exit $rc)"; pass=$((pass + 1))
  else echo "  FAIL: $1 (got $rc, expected $2)"; fails=$((fails + 1)); fi
}

mkfixture() { # copies the real manifest + both lockfiles into a fresh ROOT; echoes the dir
  local d; d=$(mktemp -d); TMPDIRS+=("$d")
  mkdir -p "$d/Packages" "$d/$(dirname "$WS_REL")"
  cp "$ROOT/Packages/Package.swift" "$d/Packages/"
  cp "$ROOT/Packages/Package.resolved" "$d/Packages/"
  cp "$ROOT/$WS_REL" "$d/$WS_REL"
  echo "$d"
}

echo "dependency-integrity guard test"

G=$(mkfixture)
expect "clean tree passes" 0 "$G"

# PR #1294 exactly: fork URL repointed in the package lockfile only.
R1=$(mkfixture)
sed -i.bak 's#github.com/mihaelamj/SwiftMCPCore#github.com/KartavyaDikshit/SwiftMCPCore#' "$R1/Packages/Package.resolved"
expect "fork URL in package lockfile fails" 1 "$R1"

# One-sided repoint to a still-allowlisted owner: allowlist (A/B) passes, drift (C) catches it.
R2=$(mkfixture)
sed -i.bak 's#github.com/mihaelamj/SwiftMCPCore#github.com/apple/SwiftMCPCore#' "$R2/Packages/Package.resolved"
expect "one-sided lockfile drift fails" 1 "$R2"

# Fork URL in the manifest itself.
R3=$(mkfixture)
sed -i.bak 's#github.com/mihaelamj/SwiftMCPCore#github.com/KartavyaDikshit/SwiftMCPCore#' "$R3/Packages/Package.swift"
expect "fork URL in manifest fails" 1 "$R3"

# Casing cannot smuggle a fork past the allowlist.
R4=$(mkfixture)
sed -i.bak 's#github.com/mihaelamj/SwiftMCPCore#github.com/Apple-Mirror/SwiftMCPCore#' "$R4/Packages/Package.resolved"
expect "lookalike owner fails" 1 "$R4"

echo "── $pass passed, $fails failed ──"
if [ "$fails" = 0 ]; then exit 0; else exit 1; fi
