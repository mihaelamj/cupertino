# --base-dir

Serve the indexes from a specific base directory instead of the configured default.

## Synopsis

```bash
cupertino serve --base-dir /path/to/bundle
```

## Description

`cupertino serve` normally resolves its database paths from the configured `baseDirectory` (a `cupertino.config.json` beside the binary) or, absent that, the default `~/.cupertino`. `--base-dir <path>` overrides that for **this invocation**: the per-source databases (`apple-documentation.db`, `swift-packages.db`, sample-code, HIG, …) are resolved as siblings under `<path>`.

Use it to point the MCP server at a specific bundle (a development snapshot, an alternate corpus, a CI fixture) without writing a config file or touching `~/.cupertino`. The per-source apple-docs index (`apple-documentation.db`) is the server's primary search index; it is resolved through the production source registry, not a hardcoded filename, so it tracks the source's `destinationDB` descriptor.

## Default

The configured `baseDirectory` (from `cupertino.config.json` beside the binary), else `~/.cupertino`.

## Notes

Path expansion: a leading `~` is expanded to the home directory. The directory must already contain a built bundle (run `cupertino save` / `cupertino setup` to produce one); serve does not create or modify it.
