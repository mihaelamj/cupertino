# --remote

Stream documentation from GitHub instead of reading local files

## Synopsis

```bash
cupertino save --remote
```

## Description

Builds `search.db` by streaming raw documentation pages from the public `mihaelamj/cupertino-docs` GitHub repository instead of reading them from a local `~/.cupertino/docs/` tree. Useful for instant first-time setup — no `cupertino fetch` step required.

Pairs with `RemoteSync` (the GitHub-streamed indexing helper package) under the hood.

## Default

Local mode (off). Without `--remote`, `cupertino save` reads from `~/.cupertino/docs/` and the other configured directories.

## Examples

### Build search.db without crawling first
```bash
cupertino save --remote
```

### Local mode (default — uses ~/.cupertino/docs/)
```bash
cupertino save
```

## Notes

- Network-bound; depends on github.com reachability.
- Slower than local mode for repeated builds (no local cache reuse).
- For most users the prebuilt bundle distributed by `cupertino setup` is the fastest path. `--remote` is for cases where the bundle isn't current and a fresh corpus is wanted without the fetch+save cycle.
- Doesn't apply to `--samples` or `--packages` builds — those still read local extracted archives.
