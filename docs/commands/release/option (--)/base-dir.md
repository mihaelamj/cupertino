# --base-dir

Directory containing databases to package.

## Synopsis

```bash
cupertino release --base-dir <path>
```

## Description

Specifies where to find `search.db` and `samples.db` for packaging. If not provided, defaults to `~/.cupertino/`.

## Examples

```bash
# Use custom location
cupertino release --base-dir ~/my-docs

# Use absolute path
cupertino release --base-dir /opt/cupertino
```

## Default

`~/.cupertino/`
