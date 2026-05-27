# --refresh-metadata

Opt into the Swift Package Index metadata + star-count refresh stage of `--source packages`.

## Synopsis

```bash
cupertino fetch --source packages --refresh-metadata
```

## Description

`cupertino fetch --source packages` runs a curated archive download from `codeload.github.com` (stage 2, ~5 min for the 135 priority packages + their transitive deps). Stage 1 is a separate, much slower step that walks all 10,995 packages tracked by the Swift Package Index, pulls metadata + star counts per package, and writes `swift-packages-with-stars.json`. Without `GITHUB_TOKEN` set, the per-package throttle (`Shared.Constants.Delay.packageFetchNormal = 1.2 s`) adds up to roughly 4 hours.

The output of stage 1 is consumed only by the TUI's popularity-sort view. The indexing pipeline (`packages.db`) does not need it. So as of [#1108](https://github.com/mihaelamj/cupertino/issues/1108) stage 1 is opt-in via this flag; `cupertino fetch --source packages` runs stage 2 only by default. Pass `--refresh-metadata` when you actually want to refresh the stars list.

## Default

`false` (do not run the SPI metadata refresh; download archives only)

## Example

```bash
# Default: download the curated priority archives (fast).
cupertino fetch --source packages

# Also refresh the Swift Package Index metadata + star counts (slow,
# typically only needed before a TUI session that uses stars-sort).
cupertino fetch --source packages --refresh-metadata
```

## Notes

- `--refresh-metadata` and `--skip-archives` compose: pass both to run **only** stage 1.
- Replaces the pre-#1108 `--skip-metadata` flag, which was an opt-out on a step that should not have been the default.
