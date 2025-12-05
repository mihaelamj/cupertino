# --base-dir

Custom directory for database storage.

## Synopsis

```bash
cupertino setup --base-dir <path>
```

## Description

Specifies where to store the downloaded databases. If not provided, defaults to `~/.cupertino/`.

## Examples

```bash
# Use custom location
cupertino setup --base-dir ~/my-docs

# Use absolute path
cupertino setup --base-dir /opt/cupertino
```

## Default

`~/.cupertino/`
