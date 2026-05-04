# --skip-archives

Skip the GitHub archive download stage of `--type packages`

## Synopsis

```bash
cupertino fetch --type packages --skip-archives
```

## Description

Bypasses stage 2 of `--type packages` (the GitHub source-archive download for each priority package). Use with `--annotate-availability` to re-annotate the existing on-disk corpus without re-downloading. ([#217](https://github.com/mihaelamj/cupertino/issues/217))

## Default

`false`

## Example

```bash
# Just refresh metadata
cupertino fetch --type packages --skip-archives

# Just annotate availability, no fetch
cupertino fetch --type packages --skip-metadata --skip-archives --annotate-availability
```

## Notes

- Stage 2 is the slowest part of `--type packages` (downloads many MB per priority package).
- Skipping it is safe when archives already exist on disk and you only need a metadata or annotation refresh.
