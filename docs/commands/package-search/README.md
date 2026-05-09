# package-search

Smart query over the packages index (packages source only).

> **Hidden command.** `package-search` is functional but does **not** show up in `cupertino --help`. It exists as a focused entry point against `packages.db` only. For a unified surface across docs + samples + HIG + packages + Swift Evolution / Swift.org / Swift Book, use [`search`](../search/) (the default fan-out mode replaces what was `cupertino ask` pre-1.0; see [#239](https://github.com/mihaelamj/cupertino/issues/239)).

## Synopsis

```bash
cupertino package-search "<question>" [--limit <n>] [--db <path>] [--platform <name>] [--min-version <ver>]
```

## Description

`package-search` is a thin wrapper on `Search.SmartQuery` configured with a single fetcher: the packages-FTS candidate fetcher. Same ranking infrastructure as `cupertino search`'s default fan-out mode (reciprocal-rank fusion, k=60), just scoped to one source.

Use it when you want results from `packages.db` only and want to bypass the multi-source fan-out cost of the default `cupertino search`. For everything else, prefer `cupertino search` (the default no-`--source` invocation runs the fan-out).

## Options

| Option | Description |
|--------|-------------|
| `<question>` (positional, required) | Plain-text question |
| `--limit` | Max number of chunks to return. Default `3`. |
| `--db` | Override `packages.db` path. Defaults to the configured packages database. |
| `--platform` | Restrict to packages whose declared deployment target is compatible with the named platform. Values: `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS` (case-insensitive). Requires `--min-version`. ([#220](https://github.com/mihaelamj/cupertino/issues/220)) |
| `--min-version` | Minimum version for `--platform`, e.g. `16.0` / `13.0` / `10.15`. Lexicographic compare in SQL — works for current Apple platform versions. |

## Examples

```bash
cupertino package-search "swift-collections deque API"
cupertino package-search "vapor middleware composition" --limit 5
cupertino package-search "swift-syntax visitor pattern" --db /tmp/packages.db

# Packages whose declared iOS deployment target is at or below 16.0
# (i.e. they install and run on iOS 16).
cupertino package-search "websocket" --platform iOS --min-version 16.0

# Broader: packages whose declared iOS deployment target is at or below 13.0.
cupertino package-search "json codable" --platform iOS --min-version 13.0
```

## Platform filter notes (#220)

- Both `--platform` and `--min-version` must be passed; one without the other errors out.
- Packages with no annotation source are dropped from results when the filter is active. To populate annotation, run `cupertino fetch --type packages --annotate-availability` followed by `cupertino save --packages` (#219).
- Comparison is lexicographic on the dotted-decimal `min_<platform>` column — correct for current Apple platforms (iOS 13+, macOS 11+, tvOS 13+, watchOS 6+, visionOS 1+). macOS 10.x with multi-digit minors (`10.15` vs `10.5`) would mis-order; not currently a concern for the priority package set.

## Relationship to `search`

`search` (in its default fan-out mode) and `package-search` share the `SmartQuery` core. The default `cupertino search "<question>"` runs every available `CandidateFetcher` in parallel and fuses the rankings; `package-search` runs only `PackageFTSCandidateFetcher`. Ranking tweaks land in one place because both go through `SmartQuery`. Pre-1.0, the fan-out was a separate `cupertino ask` command; it was absorbed into `search` in [#239](https://github.com/mihaelamj/cupertino/issues/239).

## See Also

- [search](../search/) — unified fan-out across all sources (default mode), or single-source FTS with `--source` filter
- [setup](../setup/) — provisions `packages.db` (bundled in the `cupertino-databases-v<version>.zip` release artifact alongside `search.db` and `samples.db`)
