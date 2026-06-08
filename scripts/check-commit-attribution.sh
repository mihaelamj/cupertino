#!/usr/bin/env bash
# Scan commit messages in a range for AI-attribution tells. Tool-agnostic.
#
# Complements the local commit-msg hook. Attribution trailers live in commit
# messages, not files, so a file-content style scan cannot catch them.
#
# Usage:
#   scripts/check-commit-attribution.sh [<range>]
# Range resolution:
#   1. explicit "<range>" argument, e.g. origin/main..HEAD
#   2. BASE_SHA and HEAD_SHA environment variables, as BASE_SHA..HEAD_SHA
#   3. fallback: HEAD only

set -u

RANGE="${1:-}"
if [ -z "$RANGE" ]; then
  if [ -n "${BASE_SHA:-}" ] && [ -n "${HEAD_SHA:-}" ]; then
    RANGE="${BASE_SHA}..${HEAD_SHA}"
  else
    RANGE="HEAD~0..HEAD"
  fi
fi

COMMITS=$(git rev-list "$RANGE" 2>/dev/null || true)
[ -z "$COMMITS" ] && COMMITS=$(git rev-parse HEAD)

AI_TOOLS='Claude|Anthropic|Codex|OpenAI|ChatGPT|GPT-[0-9]|Cursor|Copilot|Gemini|Google AI'
ATTRIB_REGEX="^(Co-Authored-By|Co-authored-with|Generated (with|by)|Created (with|by)|Powered by|with help from|written by|authored by)[: ].*(${AI_TOOLS})"

GENERIC_PATTERNS=(
  'as an AI'
  'this commit was generated'
  'this change was generated'
)

EMOJI_TELLS=$(printf '\xf0\x9f\xa4\x96\n\xe2\x9c\xa8\n\xf0\x9f\xaa\x84\n\xf0\x9f\xa7\xa0\n\xf0\x9f\xa6\xbe\n\xf0\x9f\xa4\x9d')
EMDASH=$(printf '\xe2\x80\x94')

FAIL=0
for sha in $COMMITS; do
  MSG=$(git log -1 --format='%B' "$sha")
  short=$(git rev-parse --short "$sha")

  if printf '%s\n' "$MSG" | grep -qiE -- "$ATTRIB_REGEX"; then
    printf 'commit-attribution: %s names an AI tool/vendor in attribution context.\n' "$short" >&2
    printf '%s\n' "$MSG" | grep -niE -- "$ATTRIB_REGEX" | sed 's/^/    /' >&2
    FAIL=1
  fi

  for p in "${GENERIC_PATTERNS[@]}"; do
    if printf '%s' "$MSG" | grep -qiF -- "$p"; then
      printf 'commit-attribution: %s contains forbidden phrase: %s\n' "$short" "$p" >&2
      FAIL=1
    fi
  done

  if LC_ALL=C printf '%s' "$MSG" | grep -qF -- "$EMDASH"; then
    printf 'commit-attribution: %s contains an em dash (U+2014).\n' "$short" >&2
    FAIL=1
  fi

  while IFS= read -r emoji; do
    [ -z "$emoji" ] && continue
    if LC_ALL=C printf '%s' "$MSG" | grep -qF -- "$emoji"; then
      printf 'commit-attribution: %s contains an AI-signature emoji.\n' "$short" >&2
      FAIL=1
      break
    fi
  done <<<"$EMOJI_TELLS"
done

if [ "$FAIL" -ne 0 ]; then
  printf 'commit-attribution: gate failed. Rules: github-discipline.md Rule 5.1 / 5.2.\n' >&2
fi
exit "$FAIL"
