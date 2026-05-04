# --samples

Build samples.db from extracted sample-code zips

## Synopsis

```bash
cupertino save --samples
```

## Description

Scope flag — selects the samples subset. Build only `samples.db` from `~/.cupertino/sample-code/`. Replaces the removed `cupertino index` command. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

When no scope flag is passed, all three (docs, packages, samples) are built in order.

## Example

```bash
cupertino save --samples
cupertino save --samples --samples-dir ~/my-samples --samples-db ~/my-samples.db
```

## Notes

- Combinable with `--docs` and `--packages`.
- Backed by `Indexer.SamplesService` (lifted in #244) → `SampleIndex.Builder`.
- Always wipes and rebuilds samples.db (no migrations on schema bumps).
- Pre-1.0 clean break: the standalone `cupertino index` command is gone.
