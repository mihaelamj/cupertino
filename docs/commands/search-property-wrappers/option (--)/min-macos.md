# --min-macos

Minimum macOS version filter.

## Synopsis

```bash
cupertino search-property-wrappers --wrapper <name> --min-macos <version>
```

## Description

Keeps only symbols available on macOS `<version>` or later, using the symbol's
indexed platform-availability metadata. Applies to sources whose data carries an
availability axis.

## Default

None (no macOS floor).

## Example

```bash
cupertino search-property-wrappers --wrapper State --min-macos 14.0
```

## Notes

- The five `--min-*` filters AND-combine: passing `--min-ios 17.0 --min-macos 14.0`
  keeps only symbols available on both platforms.
