# --base-dir

Directory holding the per-source databases.

## Synopsis

```bash
cupertino search-symbols --query <substring> --kind <kind> --base-dir <path>
```

## Description

Points the command at the folder that holds the per-source databases (the same
folder `cupertino save` / `cupertino setup` operate on, e.g. `apple-documentation.db`,
`swift-org.db`, `swift-book.db`). Defaults to the configured base directory
(`baseDirectory` in `cupertino.config.json`, or `~/.cupertino`).

## Default

The configured base directory.

## Example

```bash
cupertino search-symbols --query Task --kind struct --base-dir ~/.cupertino-dev
```
