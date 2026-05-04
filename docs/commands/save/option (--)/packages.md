# --packages

Build packages.db from extracted package archives

## Synopsis

```bash
cupertino save --packages
```

## Description

Scope flag — selects the packages subset. Build only `packages.db` from `~/.cupertino/packages/<owner>/<repo>/`. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

When no scope flag is passed, all three (docs, packages, samples) are built in order.

## Example

```bash
cupertino save --packages
```

## Notes

- Combinable with `--docs` and `--samples`.
- Backed by `Indexer.PackagesService` (lifted in #244) → `Search.PackageIndexer`.
- Reads `availability.json` sidecars produced by `cupertino fetch --type packages --annotate-availability` (#219).
