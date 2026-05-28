# --output / -o

Output JSON path for the filtered constraints table.

## Synopsis

```bash
cupertino-constraints-gen generate ... -o <output>
cupertino-constraints-gen generate ... --output <output>
```

## Description

Destination path for the generated `apple-constraints.json`. Required. The file is written only when at least one constraint is extracted; on an empty or unparseable input set the command exits 1 and writes nothing, so a half-built run never leaves a degraded table behind.

## Type

String (file path). Required.

## Example

```bash
cupertino-constraints-gen generate --from-directory /tmp/symbolgraphs -o apple-constraints.json
```
