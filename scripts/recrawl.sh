#!/usr/bin/env bash
#
# recrawl.sh — full re-crawl on a clean slate, used for v1.0.0 "First Light"
# (#192 section I) and any future schema-bumping release.
#
# Phases run sequentially so the log is easy to follow and Apple's rate
# limiter doesn't get hammered. Sample code (`code` type) is intentionally
# last because it requires interactive WKWebView sign-in (#6, partial fix
# in v1.0; #193 replaces with public JSON post-1.0). Putting it last means
# the long automated phases can run unattended and you only need to be at
# the keyboard for the final auth step.
#
# Usage:
#   ./Scripts/recrawl.sh                          # tee output to console + log
#   ./Scripts/recrawl.sh 2>&1 | tee /tmp/<...>    # explicit redirect
#
# The script does NOT redirect output itself — pipe with `tee` if you want
# both live terminal and a tailed log.

set -euo pipefail

CUPERTINO_HOME="${CUPERTINO_HOME:-$HOME/.cupertino}"
BIN="${CUPERTINO_BIN:-./Packages/.build/release/cupertino}"

if [[ ! -x "$BIN" ]]; then
    echo "❌ cupertino binary not found at $BIN"
    echo "   Build first:"
    echo "     cd Packages && swift build -c release"
    echo "   Or override: CUPERTINO_BIN=/path/to/cupertino $0"
    exit 1
fi

log() { printf '\n=== %s ===\n' "$1"; }

START_TIME=$(date +%s)
phase_start() {
    PHASE_START=$(date +%s)
    log "Phase $1: $2 — START $(date '+%H:%M:%S')"
}
phase_end() {
    local elapsed=$(( $(date +%s) - PHASE_START ))
    log "Phase $1: $2 — DONE in ${elapsed}s ($((elapsed / 60))m $((elapsed % 60))s)"
}

# ---------- 0. Wipe stale state ----------
log "Phase 0/10: Wiping stale databases (schema v12 requires fresh DBs)"
PHASE_START=$(date +%s)
for f in search.db samples.db packages.db .setup-version; do
    target="$CUPERTINO_HOME/$f"
    if [[ -e "$target" ]]; then
        echo "   removing $target"
        rm -f "$target"
    fi
done
phase_end "0/10" "Wipe"

# ---------- 1-7. Web + direct fetches in dependency-friendly order ----------
phase_start "1/10" "Apple Developer Documentation (largest, ~hours)"
"$BIN" fetch --type docs
phase_end "1/10" "Apple Developer Documentation"

phase_start "2/10" "Swift Evolution proposals"
"$BIN" fetch --type evolution
phase_end "2/10" "Swift Evolution"

phase_start "3/10" "Swift.org documentation + Swift book"
"$BIN" fetch --type swift
phase_end "3/10" "Swift.org"

phase_start "4/10" "Human Interface Guidelines"
"$BIN" fetch --type hig
phase_end "4/10" "HIG"

phase_start "5/10" "Apple Archive (legacy guides)"
"$BIN" fetch --type archive
phase_end "5/10" "Apple Archive"

phase_start "6/10" "Priority package metadata"
"$BIN" fetch --type packages
phase_end "6/10" "Package metadata"

phase_start "7/10" "Per-package documentation (READMEs + source)"
"$BIN" fetch --type package-docs
phase_end "7/10" "Package docs"

# ---------- 8. Sample code (interactive) ----------
log "Phase 8/10: Sample code"
echo "   This phase opens a browser window for Apple Developer sign-in."
echo "   Sign in, then the download proceeds automatically."
echo "   If the WKWebView path fails, you can Ctrl-C and skip — save still"
echo "   works on what's been fetched so far."
PHASE_START=$(date +%s)
"$BIN" fetch --type code || {
    echo "   ⚠️  Sample code fetch failed or was skipped — continuing without it."
}
phase_end "8/10" "Sample code"

# ---------- 9. Build search index ----------
phase_start "9/10" "Build search.db (with --clear)"
"$BIN" save --clear
phase_end "9/10" "Build search.db"

# ---------- 10. Doctor verification ----------
phase_start "10/10" "Doctor — verify the result"
"$BIN" doctor || {
    echo "   ⚠️  Doctor reported issues — review above before publishing artifacts."
}
phase_end "10/10" "Doctor"

# ---------- Summary ----------
TOTAL_ELAPSED=$(( $(date +%s) - START_TIME ))
log "Re-crawl COMPLETE in $((TOTAL_ELAPSED / 60))m $((TOTAL_ELAPSED % 60))s"
echo
echo "Next: publish the artifacts per #192 section I."
echo "  • zip + upload search.db + samples.db to mihaelamj/cupertino-docs"
echo "  • zip + upload packages.db to mihaelamj/cupertino-packages"
echo "  • verify clean-profile install (#192 I6) before tagging v1.0.0"
