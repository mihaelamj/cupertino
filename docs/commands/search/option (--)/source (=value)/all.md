# all

Force fan-out across every available source

## Synopsis

```bash
cupertino search <query> --source all
```

## Description

Equivalent to running `cupertino search <query>` with **no** `--source` filter — fans the query out across every database that exists locally and merges the per-source candidate lists with reciprocal-rank fusion (`k = 60`, source-weighted) into a single chunked result list.

`--source all` is provided so a script can ask for fan-out behavior **explicitly** rather than relying on the default. Scripts that always pass `--source <something>` benefit from a value that means "every source" without removing the flag.

## Behavior

- Sources participating: `apple-docs`, `samples`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `hig` (and `apple-archive` if `--include-archive` is passed).
- Each source contributes up to `--per-source <N>` candidates (default 10).
- Final result list is RRF-fused, then chunked excerpts are emitted in the configured `--format`.

## Examples

### Explicit fan-out
```bash
cupertino search "actor reentrancy" --source all
```

### With per-source cap
```bash
cupertino search "Observable" --source all --per-source 5
```

## Notes

- Identical to omitting `--source` entirely — provided for script clarity.
- Use `--skip-docs` / `--skip-packages` / `--skip-samples` to prune the fan-out without picking a single source.
- Apple Archive is excluded unless you also pass `--include-archive`.
