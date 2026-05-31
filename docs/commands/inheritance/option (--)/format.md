# --format

Output format for the inheritance walk.

## Synopsis

```bash
cupertino inheritance <symbol> --format <text|json|markdown|md>
```

## Description

Selects how the walked chain is rendered. `text` is the human-readable console
tree; `json` is the machine-parseable shape; `markdown` / `md` emits the same
payload the `get_inheritance` MCP tool returns.

## Values

| Value | Output |
|---|---|
| `text` | Human-readable console tree (default). |
| `json` | Machine-parseable JSON, suitable for `jq` pipelines. |
| `markdown` / `md` | The MCP wire shape (same payload the MCP tool returns). |

## Default

`text`

## Example

```bash
cupertino inheritance UIButton --format json | jq '.chain'
```
