# --force

Re-download databases even if they exist.

## Synopsis

```bash
cupertino setup --force
```

## Description

By default, `setup` skips downloading if `search.db` and `samples.db` already exist. Use `--force` to re-download and overwrite existing databases.

## Examples

```bash
# Update to latest databases
cupertino setup --force

# Force download to custom location
cupertino setup --base-dir ~/docs --force
```

## Default

`false` - Skip if databases exist
