# --min-tvos

Minimum tvOS version filter.

## Synopsis

```bash
cupertino search-conformances --protocol <name> --min-tvos <version>
```

## Description

Keeps only symbols available on tvOS `<version>` or later, using the symbol's
indexed platform-availability metadata. Applies to sources whose data carries an
availability axis.

## Default

None (no tvOS floor).

## Example

```bash
cupertino search-conformances --protocol Codable --min-tvos 17.0
```

## Notes

- The five `--min-*` filters AND-combine: passing `--min-ios 17.0 --min-macos 14.0`
  keeps only symbols available on both platforms.
