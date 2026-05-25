# --force

Force re-index of every sample under `--samples`

## Synopsis

```bash
cupertino save --source samples --force
```

## Description

Forces the samples indexer to re-index every project even if its rows already exist in `apple-sample-code.db`. Without `--force`, the indexer skips projects whose `id` already has rows.

## Default

`false`

## Example

```bash
cupertino save --source samples --force
```

## Notes

- Only meaningful with `--samples`. No effect on docs/packages scopes (those always wipe + rebuild).
- Use after upgrading the AST extractor or schema, when the on-disk samples haven't changed but the indexer logic has.
- Slower than the default no-force path on a populated DB; only run when re-indexing is actually needed.
