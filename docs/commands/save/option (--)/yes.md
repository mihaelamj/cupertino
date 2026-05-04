# -y, --yes

Skip the preflight summary's confirmation prompt

## Synopsis

```bash
cupertino save --yes
cupertino save -y
```

## Description

`cupertino save` prints a per-scope preflight summary (sources present, availability sidecar coverage, etc.) and prompts `Continue? [Y/n]` before any DB write. `--yes` / `-y` skips the prompt and proceeds. ([#232](https://github.com/mihaelamj/cupertino/issues/232))

The prompt is also auto-skipped when stdin isn't a TTY (CI / pipes), so this flag is only needed for interactive shells where you want to bypass the prompt.

## Default

`false` (prompt shown when on a TTY)

## Example

```bash
cupertino save --yes
cupertino save --packages --samples -y
```

## Notes

- The preflight summary still prints — only the prompt is skipped.
- Use `cupertino doctor --save` to read-only check what the preflight would say without committing to a run.
- Backed by `Indexer.Preflight.preflightLines(...)` (lifted to the `Indexer` package in #244).
