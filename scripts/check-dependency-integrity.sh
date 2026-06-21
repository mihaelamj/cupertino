#!/usr/bin/env bash
#
# check-dependency-integrity.sh: supply-chain guard for cupertino's dependency graph.
#
# Born from PR #1294 (2026-06-21): an external PR repointed `SwiftMCPCore` from the
# canonical `mihaelamj` repository to a contributor-owned fork by editing only
# `Packages/Package.resolved`. It was inert (the manifest was unchanged, so SwiftPM
# never resolved the fork) but indistinguishable from a supply-chain attack, and
# nothing in CI flagged the dependency change. This guard makes that whole class of
# change fail mechanically.
#
# Pure text inspection: no build, no network, no code execution. Safe to run on an
# untrusted external PR (it only parses Package.swift and the two Package.resolved
# files; it never fetches or executes a dependency).
#
# Checks:
#   A. Every dependency URL in Package.swift points at an allowlisted owner.
#   B. Every `location` pinned in each Package.resolved is an allowlisted owner.
#   C. Dependency identities present in both lockfiles pin the same location
#      (catches a one-sided repoint, exactly the PR #1294 shape).
#
# Usage: scripts/check-dependency-integrity.sh [ROOT]
#   ROOT defaults to the git top level; pass a fixture dir to test the guard.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

# The ONLY owners cupertino pulls dependencies from. A URL pointing anywhere else
# (a personal fork, a typosquat, a mirror) is rejected.
ALLOWED_OWNERS="apple swiftlang mihaelamj"

MANIFEST="$ROOT/Packages/Package.swift"
PKG_LOCK="$ROOT/Packages/Package.resolved"
WS_LOCK="$ROOT/Main.xcworkspace/xcshareddata/swiftpm/Package.resolved"

fail=0
note() { printf '   %s\n' "$1"; }

owner_allowed() {
  # $1 = a github URL. Returns 0 if the owner segment is allowlisted (case-insensitive,
  # so KartavyaDikshit / Apple-lookalikes cannot slip past on casing).
  local owner
  owner=$(printf '%s' "$1" | sed -E 's#^https?://github\.com/([^/]+)/.*#\1#' | tr '[:upper:]' '[:lower:]')
  local a
  for a in $ALLOWED_OWNERS; do [ "$owner" = "$a" ] && return 0; done
  return 1
}

# --- A: manifest dependency URLs ---
if [ -f "$MANIFEST" ]; then
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    owner_allowed "$url" || { note "✗ Package.swift declares a non-allowlisted dependency: $url"; fail=1; }
  done < <(grep -oE 'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$MANIFEST" | sort -u)
else
  note "✗ missing $MANIFEST"; fail=1
fi

# --- B: lockfile locations ---
for lock in "$PKG_LOCK" "$WS_LOCK"; do
  if [ ! -f "$lock" ]; then
    note "✗ missing lockfile: $lock"; fail=1; continue
  fi
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    owner_allowed "$url" || { note "✗ $lock pins a non-allowlisted location: $url"; fail=1; }
  done < <(grep -oE '"location"[[:space:]]*:[[:space:]]*"[^"]+"' "$lock" \
            | sed -E 's#.*"(https?://[^"]+)".*#\1#' | sort -u)
done

# --- C: shared identities must pin the same location across both lockfiles ---
if [ -f "$PKG_LOCK" ] && [ -f "$WS_LOCK" ]; then
  if ! python3 - "$PKG_LOCK" "$WS_LOCK" <<'PY'; then fail=1; fi
import json, sys
def pins(path):
    try:
        d = json.load(open(path))
    except Exception:
        return {}
    out = {}
    for x in d.get("pins", []):
        loc = (x.get("location") or "").rstrip("/")
        if loc.endswith(".git"):
            loc = loc[:-4]
        out[x.get("identity")] = loc.lower()
    return out
a = pins(sys.argv[1]); b = pins(sys.argv[2])
bad = [(i, a[i], b[i]) for i in (set(a) & set(b)) if a[i] != b[i]]
for i, la, lb in bad:
    print(f"   ✗ {i}: package lockfile pins {la} but workspace lockfile pins {lb}")
sys.exit(1 if bad else 0)
PY
fi

if [ "$fail" -ne 0 ]; then
  echo "❌ dependency-integrity check FAILED"
  echo "   Allowed dependency owners: $ALLOWED_OWNERS"
  echo "   A dependency repointed to any other owner (for example a contributor fork) is"
  echo "   rejected. See PR #1294 for why this guard exists."
  exit 1
fi
echo "✅ dependency-integrity OK: manifest + both lockfiles pin only [$ALLOWED_OWNERS]; lockfiles agree"
