# --no-reap

Skip the sibling `cupertino serve` reap pass at startup.

## Synopsis

```bash
cupertino serve --no-reap
```

## Description

`cupertino serve` normally reaps stale sibling `cupertino serve` processes that share its resolved binary path (#242). MCP hosts that reload their config (Claude Desktop, Cursor, etc.) leave orphan servers behind otherwise — they pin SQLite read locks and stack RAM usage.

`--no-reap` disables that reap pass for **this invocation**. Use it when the MCP host that spawns `cupertino serve` is **per-tool-call-spawn**: each tool invocation launches a fresh server. Under that model the reap kills the predecessor as a stale sibling, and the in-flight transport closes (`Transport closed` error on every tool call). OpenAI Codex CLI is the canonical example (#280); see the `serve` README's *OpenAI Codex* section for the matching config snippet.

## Default

Off (`--no-reap` not set → reap on). The flag is a plain `@Flag` without an inversion pair, so `--reap` is **not** a valid invocation; just omit `--no-reap` to keep the default behaviour.

## Equivalent environment variable

`CUPERTINO_DISABLE_REAPER=1` has the same effect. Convenient for MCP host configurations that already support per-server `env` blocks (the per-server TOML / JSON / YAML shape most clients use):

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"
args = ["serve"]
[mcp_servers.cupertino.env]
CUPERTINO_DISABLE_REAPER = "1"
```

The CLI flag wins if both are set.

## When to use it

| Client | Recommendation |
|---|---|
| Claude Desktop | omit `--no-reap` (default reap on — config reload leaves orphans) |
| Cursor | omit `--no-reap` (same model as Claude Desktop) |
| Claude Code | omit `--no-reap` (one persistent server, never sibling-spawns) |
| **OpenAI Codex CLI** | **`--no-reap` required** — spawns a fresh server per tool call |
| Any per-call-spawn MCP client | `--no-reap` required |

If you're unsure: leave it off first. If you see `Transport closed` on every tool call against the same client, the reaper is the cause — switch to `--no-reap`.

## Examples

### Register Codex with `--no-reap`

```bash
codex mcp add cupertino -- $(which cupertino) serve --no-reap
```

### Or in `~/.codex/config.toml`

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"
args = ["serve", "--no-reap"]
```

### Or via env var

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"
args = ["serve"]
[mcp_servers.cupertino.env]
CUPERTINO_DISABLE_REAPER = "1"
```

## Related

- [#280](https://github.com/mihaelamj/cupertino/issues/280) — the bug report that produced this flag.
- [#242](https://github.com/mihaelamj/cupertino/issues/242) — original `ServeReaper` motivation (Claude Desktop / Cursor orphan cleanup).
