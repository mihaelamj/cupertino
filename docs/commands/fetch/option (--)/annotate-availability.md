# --annotate-availability

Stage 3 of `--type packages`: write per-package `availability.json` sidecars

## Synopsis

```bash
cupertino fetch --type packages --annotate-availability
```

## Description

Walks every `<owner>/<repo>/` subdir under `~/.cupertino/packages/` and writes a per-package `availability.json` capturing the `Package.swift` `platforms: [...]` deployment-target block plus every `@available(...)` attribute occurrence in `Sources/` and `Tests/` (file path + line + parsed platform list). Pure on-disk pass — no network. Idempotent. ([#219](https://github.com/mihaelamj/cupertino/issues/219))

`cupertino save --packages` then reads these sidecars and persists the data into `packages.db`'s `min_*` columns.

## Default

`false`

## Example

```bash
# Full packages pipeline including annotation
cupertino fetch --type packages --annotate-availability

# Re-annotate without re-fetching
cupertino fetch --type packages --skip-metadata --skip-archives --annotate-availability
```

## Notes

- Backed by `Core.PackageAvailabilityAnnotator`.
- Regex-based scanner — multi-line `@available` attributes aren't handled and hits aren't tied to specific declarations. AST upgrade tracked as a follow-up.
- Smoke run on the May 2026 priority closure: 183 packages, 13.5k attrs in 12s.
