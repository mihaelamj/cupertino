# --docs

Build search.db (Apple docs + Swift Evolution + HIG + Archive + Swift.org + Swift Book)

## Synopsis

```bash
cupertino save --docs
```

## Description

Scope flag — selects the docs subset of `cupertino save`. Build only `search.db` from on-disk corpus directories; skip packages.db and samples.db. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

When **no** scope flag is passed (`--docs` / `--packages` / `--samples`), all three are built in order. With any scope flag set, only the requested subset is built.

## Example

```bash
cupertino save --docs
```

## Notes

- Combinable: `cupertino save --docs --samples` builds two of three.
- Pre-1.0 clean break — replaces the legacy "build everything" default.
- Backed by `Indexer.DocsService` (lifted in #244).
