#!/usr/bin/env bash
# Read-only smoke test for a repo-built cupertino binary against a prepared
# release corpus. This is an on-demand promotion gate, not a per-PR CI check.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/eval/release-corpus-smoke.sh [CORPUS_DIR]

Builds the current checkout's cupertino binary, copies it into a temporary
directory, writes a temporary sibling cupertino.config.json pointing at
CORPUS_DIR, and runs a read-only smoke matrix across the release corpus.

Defaults:
  CORPUS_DIR: $CUPERTINO_RELEASE_CORPUS, else ~/.cupertino

This script never runs setup, fetch, save, or any reindexing command.
USAGE
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
PACKAGES_DIR="$REPO_ROOT/Packages"
CORPUS_INPUT="${1:-${CUPERTINO_RELEASE_CORPUS:-$HOME/.cupertino}}"

expand_path() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${1#~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

CORPUS_INPUT="$(expand_path "$CORPUS_INPUT")"
if [ ! -d "$CORPUS_INPUT" ]; then
  echo "release-corpus-smoke: corpus directory not found: $CORPUS_INPUT" >&2
  exit 1
fi
CORPUS_DIR="$(cd "$CORPUS_INPUT" && pwd -P)"

REQUIRED_DBS=(
  "apple-documentation.db"
  "hig.db"
  "apple-archive.db"
  "swift-evolution.db"
  "swift-org.db"
  "swift-book.db"
  "apple-sample-code.db"
  "packages.db"
)

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cupertino-release-corpus-smoke.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

OK=$'\033[32m✓\033[0m'
FAIL=$'\033[31m✗\033[0m'
PROBE_INDEX=0
PASS_COUNT=0
FAIL_COUNT=0

fail() {
  local message="$1"
  printf "  %b %s\n" "$FAIL" "$message"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
  local message="$1"
  printf "  %b %s\n" "$OK" "$message"
  PASS_COUNT=$((PASS_COUNT + 1))
}

stat_one() {
  if stat -f '%N|%z|%m' "$1" >/dev/null 2>&1; then
    stat -f '%N|%z|%m' "$1"
  else
    stat -c '%n|%s|%Y' "$1"
  fi
}

snapshot_corpus_files() {
  local out="$1"
  : > "$out"
  for db in "${REQUIRED_DBS[@]}"; do
    local path="$CORPUS_DIR/$db"
    stat_one "$path" >> "$out"

    # SQLite may refresh an existing -shm file's mtime during read-only
    # access. Track sidecar existence and size so the smoke still catches
    # creation/deletion/growth without falsely failing on that harmless mtime.
    for suffix in "-wal" "-shm"; do
      path="$CORPUS_DIR/$db$suffix"
      if [ -e "$path" ]; then
        if stat -f '%N|%z' "$path" >/dev/null 2>&1; then
          stat -f '%N|%z' "$path" >> "$out"
        else
          stat -c '%n|%s' "$path" >> "$out"
        fi
      fi
    done
  done
}

validate_required_dbs() {
  local missing=0
  for db in "${REQUIRED_DBS[@]}"; do
    local path="$CORPUS_DIR/$db"
    if [ ! -s "$path" ]; then
      printf "missing or empty: %s\n" "$path" >&2
      missing=1
    fi
  done
  return "$missing"
}

contains_all() {
  local file="$1"
  shift
  local marker
  for marker in "$@"; do
    if ! grep -Fq "$marker" "$file"; then
      printf "missing marker: %s\n" "$marker" >&2
      return 1
    fi
  done
}

contains_all_ci() {
  local file="$1"
  shift
  local marker
  for marker in "$@"; do
    if ! grep -Fiq "$marker" "$file"; then
      printf "missing marker: %s\n" "$marker" >&2
      return 1
    fi
  done
}

validate_json_payload() {
  local file="$1"
  local mode="$2"
  python3 - "$file" "$mode" <<'PY'
import json
import sys

path, mode = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
decoder = json.JSONDecoder()
payload = None

for index, char in enumerate(text):
    if char not in "[{":
        continue
    try:
        payload, _ = decoder.raw_decode(text[index:])
        break
    except json.JSONDecodeError:
        continue

if payload is None:
    raise SystemExit(f"no JSON payload found in {path}")

def require(condition, message):
    if not condition:
        raise SystemExit(message)

if mode == "frameworks":
    require(isinstance(payload, list), "list-frameworks payload is not a JSON array")
    names = {str(item.get("name", "")).lower() for item in payload if isinstance(item, dict)}
    require(len(payload) > 100, f"expected >100 frameworks, got {len(payload)}")
    for name in ("swiftui", "uikit", "appkit", "foundation"):
        require(name in names, f"framework missing: {name}")
elif mode == "documents":
    require(isinstance(payload, dict), "list-documents payload is not a JSON object")
    require(payload.get("source") == "apple-docs", "list-documents source is not apple-docs")
    require(payload.get("framework") == "swiftui", "list-documents framework is not swiftui")
    docs = payload.get("documents", [])
    require(len(docs) >= 3, f"expected at least 3 documents, got {len(docs)}")
    require(payload.get("total", 0) > 1000, "SwiftUI total document count is unexpectedly small")
elif mode == "children":
    require(isinstance(payload, dict), "list-children payload is not a JSON object")
    require(payload.get("parentURI") == "apple-docs://swiftui", "list-children parentURI mismatch")
    children = payload.get("children", [])
    require(len(children) >= 5, f"expected at least 5 children, got {len(children)}")
    titles = {str(item.get("title", "")).lower() for item in children if isinstance(item, dict)}
    require("views" in titles, "SwiftUI children do not include Views")
elif mode == "samples":
    require(isinstance(payload, dict), "list-samples payload is not a JSON object")
    projects = payload.get("projects", [])
    require(len(projects) >= 10, f"expected at least 10 sample projects, got {len(projects)}")
    ids = {str(item.get("id", "")) for item in projects if isinstance(item, dict)}
    require("avfoundation-avcam-building-a-camera-app" in ids, "AVCam sample is missing")
elif mode == "read_sample":
    require(isinstance(payload, dict), "read-sample payload is not a JSON object")
    require(payload.get("id") == "avfoundation-avcam-building-a-camera-app", "read-sample id mismatch")
    require(payload.get("fileCount", 0) > 0, "read-sample fileCount is empty")
    require("Capture photos" in payload.get("description", ""), "read-sample description marker missing")
elif mode == "symbols":
    require(isinstance(payload, dict), "search-symbols payload is not a JSON object")
    rows = payload.get("results", [])
    require(rows, "search-symbols returned no rows")
    require(
        any(row.get("symbol_name") == "NavigationStack" and row.get("doc_uri") == "apple-docs://swiftui/navigationstack" for row in rows),
        "NavigationStack symbol row missing",
    )
elif mode == "conformances":
    require(isinstance(payload, dict), "search-conformances payload is not a JSON object")
    rows = payload.get("results", [])
    require(rows, "search-conformances returned no rows")
    require(any("View" in str(row.get("conformances", "")) for row in rows), "no returned row mentions View conformance")
elif mode == "generics":
    require(isinstance(payload, dict), "search-generics payload is not a JSON object")
    require(payload.get("filters", {}).get("constraint") == "Sendable", "search-generics constraint filter mismatch")
    rows = payload.get("results", [])
    require(rows, "search-generics returned no rows")
    require(any("Sendable" in str(row.get("generic_params", "")) for row in rows), "no returned row carries a Sendable generic constraint")
elif mode == "inheritance":
    require(isinstance(payload, dict), "inheritance payload is not a JSON object")
    require(payload.get("uri") == "apple-docs://uikit/uibutton", "inheritance UIButton URI mismatch")
    tree_text = json.dumps(payload).lower()
    require("uicontrol" in tree_text, "inheritance tree missing UIControl")
    require("uiview" in tree_text, "inheritance tree missing UIView")
else:
    raise SystemExit(f"unknown JSON validation mode: {mode}")
PY
}

validate_spec() {
  local file="$1"
  local spec="$2"
  case "$spec" in
    contains:*)
      local raw="${spec#contains:}"
      local parts=()
      IFS='|' read -r -a parts <<< "$raw"
      contains_all "$file" "${parts[@]}"
      ;;
    icontains:*)
      local raw="${spec#icontains:}"
      local parts=()
      IFS='|' read -r -a parts <<< "$raw"
      contains_all_ci "$file" "${parts[@]}"
      ;;
    json:*)
      validate_json_payload "$file" "${spec#json:}"
      ;;
    *)
      printf "unknown validation spec: %s\n" "$spec" >&2
      return 1
      ;;
  esac
}

print_excerpt() {
  local file="$1"
  echo "---- output excerpt ($file) ----"
  sed -n '1,120p' "$file"
  echo "---- end excerpt ----"
}

run_probe() {
  local label="$1"
  local spec="$2"
  shift 2
  PROBE_INDEX=$((PROBE_INDEX + 1))
  local out="$TMP_DIR/probe-$PROBE_INDEX.out"

  printf '[%02d] %s\n' "$PROBE_INDEX" "$label"
  set +e
  "$SMOKE_BIN" "$@" > "$out" 2>&1
  local status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    fail "command failed with exit code $status: cupertino $*"
    print_excerpt "$out"
    return
  fi

  if validate_spec "$out" "$spec"; then
    pass "$label"
  else
    fail "output validation failed: $label"
    print_excerpt "$out"
  fi
}

echo "Release-corpus smoke"
echo "  repo:   $REPO_ROOT"
echo "  corpus: $CORPUS_DIR"
echo

if validate_required_dbs; then
  pass "all 8 release corpus databases are present and non-empty"
else
  fail "one or more required release corpus databases are missing"
  echo
  echo "Release-corpus smoke failed: $FAIL_COUNT failure(s), $PASS_COUNT passed check(s)."
  exit 1
fi

BEFORE_STATS="$TMP_DIR/corpus-before.stats"
AFTER_STATS="$TMP_DIR/corpus-after.stats"
snapshot_corpus_files "$BEFORE_STATS"

echo
echo "Building repo-built cupertino"
(cd "$PACKAGES_DIR" && swift build --product cupertino)
BIN_DIR="$(cd "$PACKAGES_DIR" && swift build --show-bin-path)"
BUILT_BIN="$BIN_DIR/cupertino"
if [ ! -x "$BUILT_BIN" ]; then
  echo "release-corpus-smoke: built binary not found: $BUILT_BIN" >&2
  exit 1
fi

SMOKE_BIN_DIR="$TMP_DIR/bin"
mkdir -p "$SMOKE_BIN_DIR"
SMOKE_BIN="$SMOKE_BIN_DIR/cupertino"
cp "$BUILT_BIN" "$SMOKE_BIN"
chmod +x "$SMOKE_BIN"

python3 - "$CORPUS_DIR" "$SMOKE_BIN_DIR/cupertino.config.json" <<'PY'
import json
import sys

corpus, config_path = sys.argv[1], sys.argv[2]
with open(config_path, "w", encoding="utf-8") as handle:
    json.dump({"baseDirectory": corpus}, handle, separators=(",", ":"))
    handle.write("\n")
PY

echo
echo "Built binary: $BUILT_BIN"
echo "Smoke copy:   $SMOKE_BIN"
echo
echo "Running read-only command matrix"

run_probe "doctor validates schema and core DBs" \
  "contains:MCP Server|apple-documentation.db|hig.db|apple-archive.db|swift-evolution.db|swift-org.db|swift-book.db|apple-sample-code.db|packages.db|Schema version" \
  doctor

run_probe "apple-docs search finds NavigationStack" \
  "contains:NavigationStack|apple-docs://swiftui/navigationstack" \
  search "NavigationStack" --source apple-docs --limit 2 --format text

run_probe "fan-out search finds actor material" \
  "icontains:Searched:|actor|swift-evolution" \
  search "actor reentrancy" --limit 3 --format text

run_probe "read returns NavigationStack markdown" \
  "contains:# NavigationStack|struct NavigationStack" \
  read apple-docs://swiftui/navigationstack --format markdown

run_probe "list-frameworks returns typed JSON" \
  "json:frameworks" \
  list-frameworks --format json

run_probe "list-documents returns SwiftUI document page" \
  "json:documents" \
  list-documents --framework SwiftUI --limit 3 --format json

run_probe "list-children returns SwiftUI outline nodes" \
  "json:children" \
  list-children apple-docs://swiftui --format json

run_probe "list-samples returns sample catalog JSON" \
  "json:samples" \
  list-samples --format json

run_probe "read-sample returns AVCam JSON" \
  "json:read_sample" \
  read-sample avfoundation-avcam-building-a-camera-app --format json

run_probe "package-search finds Swift Argument Parser" \
  "contains:apple/swift-argument-parser|ArgumentParser" \
  package-search "swift argument parser" --limit 3

run_probe "package read returns ArgumentParser article" \
  "contains:ArgumentParser|Straightforward, type-safe argument parsing" \
  read apple/swift-argument-parser/Sources/ArgumentParser/Documentation.docc/ArgumentParser.md --source packages --format markdown

run_probe "search-symbols returns NavigationStack symbol JSON" \
  "json:symbols" \
  search-symbols --query NavigationStack --source apple-docs --limit 3 --format json

run_probe "search-conformances returns View conformers JSON" \
  "json:conformances" \
  search-conformances --protocol View --source apple-docs --limit 3 --format json

run_probe "search-generics returns Sendable constraints JSON" \
  "json:generics" \
  search-generics --constraint Sendable --source apple-docs --limit 3 --format json

run_probe "inheritance returns UIButton ancestor JSON" \
  "json:inheritance" \
  inheritance UIButton --direction up --depth 3 --format json

snapshot_corpus_files "$AFTER_STATS"
if diff -u "$BEFORE_STATS" "$AFTER_STATS" > "$TMP_DIR/corpus-stat.diff"; then
  pass "release corpus DB files and sidecar sizes are unchanged"
else
  fail "release corpus DB file stats or sidecar sizes changed"
  print_excerpt "$TMP_DIR/corpus-stat.diff"
fi

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "Release-corpus smoke passed: $PASS_COUNT checks."
  exit 0
fi

echo "Release-corpus smoke failed: $FAIL_COUNT failure(s), $PASS_COUNT passed check(s)."
exit 1
