# --skip-metadata

Skip the Swift Package Index metadata refresh stage of `--type packages`

## Synopsis

```bash
cupertino fetch --type packages --skip-metadata
```

## Description

`--type packages` runs three stages: metadata refresh (Swift Package Index API → `packages-metadata.json`), GitHub archive download, and (optional) availability annotation. `--skip-metadata` bypasses stage 1, so the run only downloads + extracts archives or annotates availability. ([#217](https://github.com/mihaelamj/cupertino/issues/217))

## Default

`false`

## Example

```bash
# Just re-download archives, no metadata refresh
cupertino fetch --type packages --skip-metadata

# Re-annotate availability without re-fetching anything
cupertino fetch --type packages --skip-metadata --skip-archives --annotate-availability
```

## Notes

- Mutually-required with at least one of `--skip-archives` / `--annotate-availability`. Passing both `--skip-metadata` AND `--skip-archives` without `--annotate-availability` errors with "nothing to do".
- Stage 1 hits Swift Package Index API; skipping keeps the run offline-ish.
