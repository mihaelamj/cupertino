# --repo

GitHub repository for releases.

## Synopsis

```bash
cupertino release --repo <owner/repo>
```

## Description

Specifies the GitHub repository where databases will be uploaded. Must have write access via `GITHUB_TOKEN`.

## Examples

```bash
# Use custom repository
cupertino release --repo myorg/my-cupertino-docs

# Default repository
cupertino release --repo mihaelamj/cupertino-docs
```

## Default

`mihaelamj/cupertino-docs`
