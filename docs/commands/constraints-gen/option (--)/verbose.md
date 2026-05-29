# --verbose

Print per-file entry counts as files are processed.

## Synopsis

```bash
cupertino-constraints-gen generate ... --verbose
```

## Description

Emits one line per input file to stderr: the file name and the number of constraint entries extracted, plus a warning for any file skipped as unreadable or unparseable. Useful when diagnosing why a directory scan produced fewer entries than expected.

## Type

Flag. Default: `false`.

## Example

```bash
cupertino-constraints-gen generate --from-directory /tmp/symbolgraphs -o apple-constraints.json --verbose
```
