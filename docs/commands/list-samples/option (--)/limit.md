# --limit

Maximum number of samples to return

## Synopsis

```bash
cupertino list-samples --limit <number>
```

## Description

Cap the number of projects returned. Use to keep output short when listing samples in shells or piping to other tools.

## Default

`50`

## Examples

### Top 10 samples
```bash
cupertino list-samples --limit 10
```

### Combined with framework filter
```bash
cupertino list-samples --framework swiftui --limit 5
```

### Show everything
```bash
cupertino list-samples --limit 1000
```

## Notes

- The order is project-name ascending; `--limit N` returns the first N entries in that order.
- Setting `--limit` larger than the indexed sample count returns all of them without padding.
