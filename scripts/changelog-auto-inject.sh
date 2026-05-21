#!/usr/bin/env bash
# changelog-auto-inject.sh: pre-commit-msg companion to
# scripts/check-changelog-touched.sh. When a non-trivial commit doesn't
# already touch CHANGELOG.md, this hook reads the commit message subject,
# maps the conventional-commit type to a CHANGELOG section, and injects a
# TODO placeholder line under `## Unreleased > <section>`. The author
# fleshes out the TODO before pushing.
#
# Why a separate hook (rather than extending check-changelog-touched.sh):
# pre-commit hooks at stage `commit` run against the staged index, before
# the commit message is finalized. To read the commit message we need
# stage `prepare-commit-msg`, which receives the message file as $1.
# Keeping the two hooks separate also lets the user opt into auto-inject
# without changing the enforcement behavior of the original hook.
#
# Order vs. check-changelog-touched.sh:
#   1. prepare-commit-msg: this script runs. If it injects an entry,
#      CHANGELOG.md is auto-staged.
#   2. pre-commit: check-changelog-touched.sh runs. With the auto-staged
#      CHANGELOG.md, it passes. If this script bailed out (amend, merge,
#      docs-only, etc.), the enforcement hook still applies normally.
#
# Bail-out conditions (exit 0 without injecting):
#   - Amending an existing commit (avoid rewriting history mid-amend).
#   - Merge commit, revert, squash, or commit on a detached HEAD.
#   - The author already touched CHANGELOG.md in this commit.
#   - Commit message body contains `[no-changelog]` (same opt-out as the
#     enforcement hook).
#   - The conventional-commit type is in the docs/test/chore family that
#     the enforcement hook itself exempts (no CHANGELOG required).
#   - The commit message subject is empty / doesn't match the
#     conventional-commit shape (can't decide which section).
#
# Exit codes:
#   0  hook ran successfully (injected an entry OR bailed out cleanly)
#   1  hook hit an error (shouldn't happen; fail loud)

set -uo pipefail

COMMIT_MSG_FILE="${1:-}"
COMMIT_SOURCE="${2:-}"
COMMIT_SHA="${3:-}"

# Bail-out: pre-commit invokes this without the standard args during
# self-test or `pre-commit run` without a real commit; nothing to inject.
if [[ -z "$COMMIT_MSG_FILE" || ! -f "$COMMIT_MSG_FILE" ]]; then
    exit 0
fi

# Bail-out: amend, merge, squash, template (preserve user intent).
case "$COMMIT_SOURCE" in
    merge|squash|commit|template)
        exit 0
        ;;
esac
if [[ -n "$COMMIT_SHA" ]]; then
    exit 0  # amending an existing commit
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 1

# Skip if CHANGELOG.md is already in the staged diff (the user wrote one
# manually, no need to inject).
if git diff --cached --name-only | grep -qx 'CHANGELOG.md'; then
    exit 0
fi

# Skip on the `[no-changelog]` opt-out (matches the enforcement hook).
if grep -q '\[no-changelog\]' "$COMMIT_MSG_FILE"; then
    exit 0
fi

# Read the subject line (first non-comment line).
SUBJECT=$(grep -v '^#' "$COMMIT_MSG_FILE" | sed '/^$/d' | head -n1)
if [[ -z "$SUBJECT" ]]; then
    exit 0
fi

# Parse conventional-commit shape: `<type>(<scope>): <description>` or
# `<type>: <description>`. Capture type only; scope is optional.
TYPE=$(echo "$SUBJECT" | sed -nE 's/^([a-z]+)(\([^)]+\))?(!)?:[[:space:]].*$/\1/p')
if [[ -z "$TYPE" ]]; then
    exit 0
fi

# Map type to CHANGELOG section. Types that don't require a CHANGELOG
# entry (docs, test, chore, ci, style) bail out so the enforcement hook
# can apply its own exemption logic without conflict.
case "$TYPE" in
    fix)            SECTION="### Fixed" ;;
    feat|feature)   SECTION="### Added" ;;
    refactor|perf)  SECTION="### Changed" ;;
    revert)         SECTION="### Changed" ;;
    docs|test|chore|ci|style|build)
        exit 0
        ;;
    *)
        # Unknown type: don't risk a wrong section, let enforcement handle it.
        exit 0
        ;;
esac

# Extract subject without the type prefix for the entry text.
ENTRY_TEXT=$(echo "$SUBJECT" | sed -E 's/^[a-z]+(\([^)]+\))?(!)?:[[:space:]]+//')

# Find issue number from branch name (e.g. fix/754-foo → #754) or from
# subject (e.g. "fix(install): drop --force (#883)" → #883).
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
ISSUE_REF=""
if [[ "$BRANCH" =~ /([0-9]+)- ]]; then
    ISSUE_REF=" (refs #${BASH_REMATCH[1]})"
elif [[ "$SUBJECT" =~ \#([0-9]+) ]]; then
    ISSUE_REF=" (refs #${BASH_REMATCH[1]})"
fi

CHANGELOG=CHANGELOG.md
if [[ ! -f "$CHANGELOG" ]]; then
    # No CHANGELOG to update; let the enforcement hook flag it.
    exit 0
fi

# Build the new line.
NEW_LINE="- **TODO: ${ENTRY_TEXT}**${ISSUE_REF}. Auto-injected from commit subject by changelog-auto-inject.sh; expand this entry with context, root cause, fix details, and test results before pushing."

# Inject the line:
#   Case 1: CHANGELOG already has `## Unreleased` at the top. Find the
#           target section under it (### Fixed / ### Added / ### Changed).
#           If the section exists, insert NEW_LINE as the first bullet.
#           If the section is absent, add the section + NEW_LINE under it.
#   Case 2: CHANGELOG doesn't have `## Unreleased` at the top. Prepend
#           `## Unreleased\n\n<section>\n\n<NEW_LINE>\n\n` before the
#           first existing `## ` header.

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

python3 - "$CHANGELOG" "$SECTION" "$NEW_LINE" "$TMP" <<'PYEOF'
import sys, re
changelog_path, section, new_line, tmp_path = sys.argv[1:]
with open(changelog_path) as f:
    src = f.read()
unreleased_match = re.match(r'^## Unreleased\s*\n', src)
if unreleased_match:
    # Case 1: find or create the target section under Unreleased.
    # Find the bounds of the Unreleased block (up to next `## ` header).
    next_header = re.search(r'\n## [^U]', src[unreleased_match.end():])
    block_end = unreleased_match.end() + next_header.start() if next_header else len(src)
    unreleased_block = src[unreleased_match.end():block_end]
    section_re = re.compile(r'^' + re.escape(section) + r'\s*\n', re.M)
    section_match = section_re.search(unreleased_block)
    if section_match:
        # Insert new_line as the first bullet under the section.
        insert_at = unreleased_match.end() + section_match.end()
        new_src = src[:insert_at] + '\n' + new_line + '\n' + src[insert_at:]
    else:
        # Section absent: append section + line to the end of Unreleased block.
        # Need a blank line before, and the new section before the next `## `.
        prefix = src[:block_end].rstrip() + '\n\n' + section + '\n\n' + new_line + '\n\n'
        new_src = prefix + src[block_end:].lstrip('\n')
else:
    # Case 2: prepend a new Unreleased block before the first `## ` header.
    first_header = re.search(r'^## ', src, re.M)
    if first_header:
        new_src = ('## Unreleased\n\n' + section + '\n\n' + new_line + '\n\n' +
                   src[first_header.start():])
    else:
        new_src = '## Unreleased\n\n' + section + '\n\n' + new_line + '\n\n' + src
with open(tmp_path, 'w') as f:
    f.write(new_src)
PYEOF

mv "$TMP" "$CHANGELOG"
trap - EXIT

# Stage the modified CHANGELOG so the about-to-be-created commit picks it
# up and the enforcement hook downstream sees it as touched.
git add "$CHANGELOG"

# Echo to the commit-msg comments so the author sees what happened.
{
    echo ""
    echo "# changelog-auto-inject.sh: prepended a TODO entry under '$SECTION'"
    echo "# in CHANGELOG.md based on this commit's subject. Flesh out the"
    echo "# entry before pushing (or include '[no-changelog]' to suppress)."
} >> "$COMMIT_MSG_FILE"

exit 0
