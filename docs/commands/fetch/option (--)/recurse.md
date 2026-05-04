# --recurse / --no-recurse

Resolve transitive package dependencies during `--type packages` (hidden default)

## Synopsis

```bash
cupertino fetch --type packages --recurse
cupertino fetch --type packages --no-recurse
```

## Description

When fetching priority packages, walk each seed's `Package.swift` (and `Package.resolved` as fallback) and add transitive GitHub dependencies to the fetch queue. Non-GitHub URLs, missing manifests, and malformed manifests are counted and skipped. Terminates via canonical-name dedupe. ([#184](https://github.com/mihaelamj/cupertino/issues/184))

## Default

`true`

## Example

```bash
# Default: priorities + transitives
cupertino fetch --type packages

# Just priorities, no recursion
cupertino fetch --type packages --no-recurse
```

## Notes

- Hidden flag in `--help` (still functional).
- A 200-package closure resolves in ~tens of seconds via the parallel resolver.
- Cross-references against `~/.cupertino/excluded-packages.json` (hand-edited) so the user can drop discovered-via-dep packages.
