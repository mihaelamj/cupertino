# --min-watchos

Minimum watchOS version filter.

## Synopsis

```bash
cupertino search-generics --constraint <type> --min-watchos <version>
```

## Description

Keeps only symbols available on watchOS `<version>` or later, using the symbol's
indexed platform-availability metadata. Applies to sources whose data carries an
availability axis.

## Default

None (no watchOS floor).

## Example

```bash
cupertino search-generics --constraint Hashable --min-watchos 10.0
```

## Notes

- The five `--min-*` filters AND-combine: passing `--min-ios 17.0 --min-macos 14.0`
  keeps only symbols available on both platforms.
