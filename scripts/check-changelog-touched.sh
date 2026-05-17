#!/usr/bin/env bash
# check-changelog-touched.sh — fail when a non-trivial change is staged
# (or committed) without a CHANGELOG.md update.
#
# The 2026-05-17 whole-CHANGELOG audit found 7 PRs over 3 days that
# merged without CHANGELOG entries. The methodology doc
# (docs/audits/methodology.md) covers the discipline in prose. This
# script is the mechanical enforcement layer: refuse the commit until
# CHANGELOG.md is touched, OR until the developer explicitly opts out
# via `--no-verify` (pre-commit) / a `[no-changelog]` token in the
# commit message body (the explicit opt-out path).
#
# Wired via .pre-commit-config.yaml as a local hook (always runs on
# every commit) AND via .github/workflows/ci.yml as a PR-level gate
# (catches anything that bypassed pre-commit).
#
# Exit codes:
#   0 — commit is allowed
#       (CHANGELOG touched, OR only doc/test/script files touched, OR
#        the commit message body contains `[no-changelog]`)
#   1 — commit is refused (source touched, CHANGELOG not, no opt-out)
#   2 — invocation error
#
# Modes:
#   ./scripts/check-changelog-touched.sh                  (pre-commit:
#                                                          inspects the
#                                                          staged diff)
#   ./scripts/check-changelog-touched.sh --base=<ref>     (CI: inspects
#                                                          the diff
#                                                          against a
#                                                          base ref,
#                                                          typically
#                                                          develop or
#                                                          main)
#   ./scripts/check-changelog-touched.sh --message=<msg>  (override the
#                                                          commit-msg
#                                                          source for
#                                                          opt-out
#                                                          detection;
#                                                          used in CI
#                                                          when the
#                                                          message
#                                                          isn't a git
#                                                          commit-msg
#                                                          file)

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || {
    echo "❌ failed to cd to repo root" >&2
    exit 2
}

# --- Arg parsing -------------------------------------------------------

MODE="pre-commit"
BASE_REF=""
EXTERNAL_MSG=""

for arg in "$@"; do
    case "$arg" in
        --base=*)
            MODE="ci"
            BASE_REF="${arg#--base=}"
            ;;
        --message=*)
            EXTERNAL_MSG="${arg#--message=}"
            ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# //;s/^#//'
            exit 0
            ;;
        *)
            printf '❌ unknown arg: %s\n' "$arg" >&2
            exit 2
            ;;
    esac
done

# --- Collect the change set -------------------------------------------

if [ "$MODE" = "ci" ]; then
    # CI mode: diff against the base branch.
    if [ -z "$BASE_REF" ]; then
        echo "❌ --base=<ref> required in CI mode" >&2
        exit 2
    fi
    # `git diff --name-only base..HEAD` works for both PR and push events
    # provided the CI workflow checked out enough history.
    CHANGED=$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null || true)
else
    # Pre-commit mode: inspect what's staged for the in-progress commit.
    CHANGED=$(git diff --cached --name-only 2>/dev/null || true)
fi

if [ -z "$CHANGED" ]; then
    # Nothing to check — typical for `git commit --allow-empty` or for
    # CI runs against a fork where the diff couldn't be computed.
    exit 0
fi

# --- Decide whether the change set requires CHANGELOG -----------------

# Files matching ANY of these patterns mean a CHANGELOG entry is needed.
# Conservative — covers all production source. Add patterns when new
# source-bearing directories are introduced.
NEEDS_CHANGELOG_PATTERNS=(
    '^Packages/Sources/.*\.swift$'
    '^Apps/.*\.swift$'
    '^Package\.swift$'
    '^Packages/Package\.swift$'
)

# Files matching any of these are "trivial" — touching only these files
# does NOT require a CHANGELOG entry. Order matters: a file matched by
# NEEDS_CHANGELOG above will require CHANGELOG even if it also matches
# something here.
TRIVIAL_PATTERNS=(
    '^docs/'
    '^README\.md$'
    '^CONTRIBUTING\.md$'
    '^CLAUDE\.md$'
    '^AGENTS\.md$'
    '^MEMORY\.md$'
    '^LICENSE'
    '^\.github/'
    '^\.gitignore$'
    '^\.gitattributes$'
    '^\.swiftformat$'
    '^\.swiftlint\.yml$'
    '^\.pre-commit-config\.yaml$'
    '^scripts/.*\.sh$'
    '^scripts/[^/]+$'
    '^Packages/Tests/.*\.swift$'
)

needs_changelog=false
trivial_only=true
problem_files=""

while IFS= read -r file; do
    [ -z "$file" ] && continue
    # Skip CHANGELOG itself — touching it is what we're checking for.
    [ "$file" = "CHANGELOG.md" ] && continue

    is_source=false
    for pat in "${NEEDS_CHANGELOG_PATTERNS[@]}"; do
        if [[ "$file" =~ $pat ]]; then
            is_source=true
            break
        fi
    done

    is_trivial=false
    for pat in "${TRIVIAL_PATTERNS[@]}"; do
        if [[ "$file" =~ $pat ]]; then
            is_trivial=true
            break
        fi
    done

    if $is_source && ! $is_trivial; then
        needs_changelog=true
        trivial_only=false
        problem_files="${problem_files}  - ${file}"$'\n'
    elif ! $is_trivial; then
        # Unmatched file — neither clearly source nor clearly trivial.
        # Lean toward requiring CHANGELOG (the conservative bias). The
        # developer can opt out with `[no-changelog]` if the case is
        # genuinely trivial.
        needs_changelog=true
        trivial_only=false
        problem_files="${problem_files}  - ${file} (unclassified — see TRIVIAL_PATTERNS in the script)"$'\n'
    fi
done <<<"$CHANGED"

if ! $needs_changelog; then
    # Every changed file was trivial. No CHANGELOG required.
    exit 0
fi

# --- Did the change set include CHANGELOG.md? --------------------------

if grep -qE '^CHANGELOG\.md$' <<<"$CHANGED"; then
    # CHANGELOG was touched. Done.
    exit 0
fi

# --- Opt-out path: [no-changelog] token in the commit message ---------

# In pre-commit mode, the commit message is at .git/COMMIT_EDITMSG.
# In CI mode (or when --message=… is passed), use the external source.
MSG=""
if [ -n "$EXTERNAL_MSG" ]; then
    MSG="$EXTERNAL_MSG"
elif [ "$MODE" = "ci" ]; then
    # CI: pull the merge commit message (or the PR title via env).
    MSG=$(git log --format='%B' -1 HEAD 2>/dev/null || true)
elif [ -f "$REPO_ROOT/.git/COMMIT_EDITMSG" ]; then
    MSG=$(cat "$REPO_ROOT/.git/COMMIT_EDITMSG" 2>/dev/null || true)
fi

if grep -qiE '\[no-changelog\]' <<<"$MSG"; then
    # Developer explicitly opted out. Allow.
    exit 0
fi

# --- Refuse the commit ------------------------------------------------

cat >&2 <<EOF
❌ CHANGELOG.md not updated, but source files were touched.

Files that look like they need a CHANGELOG entry:
$problem_files

Options:
  1. Add a CHANGELOG.md entry under "Unreleased — staged for <version>"
     and re-stage / re-commit.
  2. If the change genuinely doesn't need a CHANGELOG entry (e.g.
     refactor that compiles to identical output, or a typo-fix in a
     comment), include the literal token "[no-changelog]" in the
     commit message body.
  3. Bypass for emergency only: \`git commit --no-verify\`.

Why this guard exists:
  Whole-CHANGELOG audit on 2026-05-17 found 7 PRs over 3 days that
  merged without CHANGELOG entries — all chore / refactor / test PRs.
  The class-of-bug was "substance ships, description trails." Pre-fix
  was a methodology doc (docs/audits/methodology.md) — prose-only,
  not enforced. This script is the mechanical layer that makes the
  discipline impossible to forget at commit time.
EOF

exit 1
