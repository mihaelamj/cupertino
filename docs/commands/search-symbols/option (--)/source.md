# --source

Restrict the search to a single source id.

## Synopsis

```bash
cupertino search-symbols --query <substring> --kind <kind> --source <id>
```

## Description

By default the command searches every source whose database carries indexed
symbols. Pass `--source` to restrict to one: `apple-docs`, `swift-org`, or
`swift-book`. Post-#1037 each source owns its own per-source database under the
base directory.

## Default

None (every symbol-bearing source).

## Example

```bash
cupertino search-symbols --query Task --kind struct --source apple-docs
```
