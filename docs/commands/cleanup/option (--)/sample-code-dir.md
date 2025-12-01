# --sample-code-dir

Sample code directory to clean

## Synopsis

```bash
cupertino cleanup --sample-code-dir <directory>
```

## Description

Specifies a custom directory containing sample code ZIP archives to clean. If not provided, uses the default sample code directory.

## Default

`~/.cupertino/sample-code`

## Examples

### Custom Directory
```bash
cupertino cleanup --sample-code-dir ~/Downloads/sample-code
```

### Absolute Path
```bash
cupertino cleanup --sample-code-dir /Volumes/External/samples
```

## Notes

- Directory must exist
- Should contain `.zip` files
- Supports tilde expansion (`~`)
