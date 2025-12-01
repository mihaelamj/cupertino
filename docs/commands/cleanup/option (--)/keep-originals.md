# --keep-originals

Keep original ZIP files after cleaning

## Synopsis

```bash
cupertino cleanup --keep-originals
```

## Description

Instead of replacing original ZIP files, saves cleaned versions with a `.cleaned.zip` suffix. Original files remain untouched.

## Default

`false` (originals are replaced)

## Examples

### Keep Originals
```bash
cupertino cleanup --keep-originals
```

### Combine with Dry Run First
```bash
cupertino cleanup --dry-run
cupertino cleanup --keep-originals
```

## Output Files

| Original | Cleaned |
|----------|---------|
| `Sample.zip` | `Sample.cleaned.zip` |

## Notes

- Uses more disk space (both versions kept)
- Safer for first cleanup
- Can delete originals manually after verification
