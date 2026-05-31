# --format

Output format for the result list.

## Synopsis

```bash
cupertino search-conformances --protocol <name> --format <text|json|markdown|md>
```

## Description

Selects how matched symbols are rendered. `text` is the human-readable console
form; `json` is the machine-parseable shape for shell pipelines; `markdown` / `md`
emits the same payload the matching MCP tool returns.

## Values

| Value | Output |
|---|---|
| `text` | Human-readable console output (default). |
| `json` | Machine-parseable JSON, suitable for `jq` pipelines. |
| `markdown` / `md` | The MCP wire shape (same payload the MCP tool returns). |

## Default

`text`

## Example

```bash
cupertino search-conformances --protocol Codable --format json | jq '.results[0]'
```
