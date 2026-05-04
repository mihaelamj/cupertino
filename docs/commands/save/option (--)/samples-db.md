# --samples-db

samples.db output path for `--samples`

## Synopsis

```bash
cupertino save --samples --samples-db <path>
```

## Description

Override the default `~/.cupertino/samples.db` location. ([#231](https://github.com/mihaelamj/cupertino/issues/231))

## Default

`~/.cupertino/samples.db`

## Example

```bash
cupertino save --samples --samples-db ~/dev/samples.db
```

## Notes

- Tilde (`~`) expansion supported.
- Always wipes and rebuilds — schema mismatches between binary and on-disk DB are resolved by re-creation, not migration.
