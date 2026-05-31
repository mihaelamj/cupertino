# --base-dir

Directory holding the per-source databases.

## Synopsis

```bash
cupertino search-concurrency --pattern <pattern> --base-dir <path>
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
cupertino search-concurrency --pattern actor --base-dir ~/.cupertino-dev
```
