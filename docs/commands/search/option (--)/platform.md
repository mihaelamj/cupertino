# --platform

Restrict packages + samples + apple-docs results by platform deployment target

## Synopsis

```bash
cupertino search <query> --platform <platform> --min-version <version>
```

## Description

In fan-out mode, restricts results to those whose declared deployment target is compatible with the named platform. Requires `--min-version` (both must be set together; one without the other errors out). ([#220](https://github.com/mihaelamj/cupertino/issues/220), [#233](https://github.com/mihaelamj/cupertino/issues/233))

## Values

| Value | Description |
|-------|-------------|
| `iOS` | iOS / iPadOS deployment target |
| `macOS` | macOS deployment target |
| `tvOS` | tvOS deployment target |
| `watchOS` | watchOS deployment target |
| `visionOS` | visionOS deployment target |

Case-insensitive.

## Default

None (no platform filter)

## Example

```bash
cupertino search "structured concurrency" --platform iOS --min-version 16.0
```

## Notes

- Fan-out mode only.
- Filter pushes through `Search.PackageQuery.AvailabilityFilter` → SQL JOIN on `package_metadata.min_<x>` (lex compare).
- Swift-language-version sources (`swift-evolution`, `swift-org`, `swift-book`) silently drop the filter — they don't carry `min_<platform>` columns. The unfiltered-source notice in the search output names them.
- Packages with `availability_source = NULL` are excluded (no annotation = unknown = excluded under a platform filter).
