# --brief

Trim each result's excerpt to its first ~12 non-blank lines for triage

## Synopsis

```bash
cupertino search <query> --brief
```

## Description

Default fan-out output prints each result's full chunk (often a multi-paragraph README, doc body, or code block). `--brief` collapses each chunk to its first ~12 non-blank lines with a `…` ellipsis. The per-result `▶ Read full: cupertino read <id> --source <name>` hint, the `See also` footer, and tips still print, so an LLM consumer can drill into any candidate without re-running search.

Fan-out mode + text/markdown only. JSON output keeps full chunks for programmatic consumers (truncation is a presentation choice). ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up)

## Default

`false` (full chunks)

## When to use

- **Triage**: skim ~5 candidates without burning token budget on full READMEs.
- **Terminal scrolling**: full chunks + `--limit 5` produces hundreds of lines; `--brief` keeps it scannable.
- **LLM agent passes**: when the agent will follow up with `cupertino read` on the chosen result anyway, the chunk is just for "is this even relevant?".

## When to leave off

- Single-pass LLM context where the agent answers directly from the chunk and won't drill in.
- Code-block-heavy results where the truncation cuts mid-snippet.

## Examples

### Brief triage across all sources
```bash
cupertino search "swiftui list animation" --brief --limit 5
```

### Brief, packages only, with a follow-up read
```bash
cupertino search "actor reentrancy" --skip-docs --skip-samples --brief --limit 3
# pick a result, then:
cupertino read pointfreeco/swift-concurrency-extras/Sources/.../File.swift --source packages
```

### JSON ignores --brief
```bash
cupertino search "View" --format json --brief   # full chunks anyway
```

## Notes

- Backed by `SearchCommand+SmartReport.briefExcerpt(of:lines:)` — first N non-blank lines, default N=12.
- The threshold (12) was chosen to surface a doc's overview paragraph + first heading, not single-sentence triage.
