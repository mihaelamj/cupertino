# release-corpus-smoke

Run a repo-built `cupertino` binary against a prepared release corpus without
touching the Homebrew-installed binary and without invoking `setup`, `fetch`,
`save`, or reindexing.

```bash
scripts/eval/release-corpus-smoke.sh ~/.cupertino
```

## Syntax

```text
scripts/eval/release-corpus-smoke.sh [<corpus-dir>]
scripts/eval/release-corpus-smoke.sh --help
```

## Arguments

| Argument | Description |
|----------|-------------|
| [`<corpus-dir>`](<argument (<>)/corpus-dir.md>) | Optional prepared release corpus directory |

## Options

| Option | Description |
|--------|-------------|
| [`--help`](<option (--)/help.md>) | Print usage and exit |

## Environment

| Variable | Description |
|----------|-------------|
| `CUPERTINO_RELEASE_CORPUS` | Default corpus directory when `<corpus-dir>` is omitted |

## Checks

The smoke validates:

- All eight release DB files are present and non-empty.
- `doctor` reports healthy schema and core DBs.
- Search, read, browse, sample, package, semantic, generic, conformance, and
  inheritance surfaces return non-empty expected output.
- Release DB file size/mtime and sidecar presence/size remain stable.

See also: [release corpus smoke gate](../../../release/release-corpus-smoke.md).
