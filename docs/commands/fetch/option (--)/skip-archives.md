# --skip-archives

Skip the GitHub archive download stage of `--source packages`

## Synopsis

```bash
cupertino fetch --source packages --skip-archives
```

## Description

Bypasses stage 2 of `--source packages` (the GitHub source-archive download for each priority package). Use with `--annotate-availability` to re-annotate the existing on-disk corpus without re-downloading. ([#217](https://github.com/mihaelamj/cupertino/issues/217))

Post-[#1108](https://github.com/mihaelamj/cupertino/issues/1108), stage 1 (Swift Package Index metadata + star-count refresh) is opt-in via `--refresh-metadata`. Combining `--skip-archives` with `--refresh-metadata` runs only stage 1.

## Default

`false`

## Example

```bash
# Refresh SPI metadata + stars only (TUI use case), no archive download
cupertino fetch --source packages --refresh-metadata --skip-archives

# Re-annotate availability against an existing on-disk corpus, no network
cupertino fetch --source packages --skip-archives --annotate-availability
```

## Notes

- Stage 2 is the dominant cost of `--source packages` when network is the bottleneck.
- Skipping it is safe when archives already exist on disk and you only need a metadata or annotation refresh.
