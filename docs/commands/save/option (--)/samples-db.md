# --samples-db

apple-sample-code.db output path for `--samples`

## Synopsis

```bash
cupertino save --source samples --samples-db <path>
```

## Description

Override the default `~/.cupertino/apple-sample-code.db` location. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

`~/.cupertino/apple-sample-code.db`

## Example

```bash
cupertino save --source samples --samples-db ~/dev/apple-sample-code.db
```

## Notes

- Tilde (`~`) expansion supported.
- Always wipes and rebuilds, schema mismatches between binary and on-disk DB are resolved by re-creation, not migration.
