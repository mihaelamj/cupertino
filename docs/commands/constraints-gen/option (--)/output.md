# --output / -o

Output JSON path for the generated table.

## Synopsis

```bash
cupertino-constraints-gen generate ... -o <output>
cupertino-constraints-gen generate ... --output <output>
cupertino-constraints-gen conformances ... -o <output>
cupertino-constraints-gen conformances ... --output <output>
```

## Description

Destination path for the generated table. Use `apple-constraints.json` for `generate` and `apple-conformances.json` for `conformances`. Required. The file is written only when at least one entry is extracted; on an empty or unparseable input set the command exits 1 and writes nothing, so a half-built run never leaves a degraded table behind.

## Type

String (file path). Required.

## Example

```bash
cupertino-constraints-gen generate --from-directory /tmp/symbolgraphs -o apple-constraints.json
cupertino-constraints-gen conformances --from-directory /tmp/symbolgraphs -o apple-conformances.json
```
