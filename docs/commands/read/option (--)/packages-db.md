# --packages-db

Path to packages database (`packages.db`)

## Synopsis

```bash
cupertino read <identifier> --packages-db <path>
```

## Description

Override the default `~/.cupertino/packages.db` location. Used when `--source packages` (or auto-source falling through to packages) needs to query.

## Default

`~/.cupertino/packages.db`

## Example

```bash
cupertino read pointfreeco/swift-navigation/Sources/foo.swift --source packages --packages-db ~/dev/packages.db
```

## Notes

- Tilde (`~`) expansion supported.
- Honours `Shared.BinaryConfig.baseDirectory` overrides (#211).
- Reads file content from `package_files_fts.content` (no on-disk packages tree required).
