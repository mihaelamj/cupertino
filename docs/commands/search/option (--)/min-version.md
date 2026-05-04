# --min-version

Minimum platform version for `--platform` filter

## Synopsis

```bash
cupertino search <query> --platform <platform> --min-version <version>
```

## Description

Required when `--platform` is set. Lex compare in SQL; correct for all current Apple platforms (iOS 13+, macOS 11+, tvOS 13+, watchOS 6+, visionOS 1+). ([#220](https://github.com/mihaelamj/cupertino/issues/220))

## Format

Dotted decimal — `16.0`, `13.0`, `10.15`, etc.

## Default

None (required when `--platform` is passed; both flags must appear together).

## Example

```bash
cupertino search "swiftui list animation" --platform iOS --min-version 16.0
cupertino search "concurrency" --platform macOS --min-version 13.0
```

## Notes

- Fan-out mode only.
- `--min-version` without `--platform` (or vice versa) errors out.
- Lex compare correct for current Apple platforms; old macOS 10.x with multi-digit minors would mis-order but no priority package targets that.
