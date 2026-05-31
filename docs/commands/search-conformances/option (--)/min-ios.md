# --min-ios

Minimum iOS version filter.

## Synopsis

```bash
cupertino search-conformances --protocol <name> --min-ios <version>
```

## Description

Keeps only symbols available on iOS `<version>` or later, using the symbol's
indexed platform-availability metadata. Applies to sources whose data carries an
availability axis.

## Default

None (no iOS floor).

## Example

```bash
cupertino search-conformances --protocol Codable --min-ios 17.0
```

## Notes

- The five `--min-*` filters AND-combine: passing `--min-ios 17.0 --min-macos 14.0`
  keeps only symbols available on both platforms.
