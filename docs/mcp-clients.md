# MCP client setup

Cupertino exposes its local documentation index over the [Model Context Protocol](https://modelcontextprotocol.io) via `cupertino serve`. Any MCP-capable client can connect. Setup snippets for each supported host are below.

> **Binary path:** All examples use `/opt/homebrew/bin/cupertino` (Homebrew on Apple Silicon). Use `/usr/local/bin/cupertino` for Intel Macs or manual installs. Run `which cupertino` to find your path.

For the prerequisite install + database download, see the [README](../README.md#installation).

## Claude Desktop

1. Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/usr/local/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

2. Restart Claude Desktop.
3. Ask Claude about Apple APIs:
   - "Search for SwiftUI documentation"
   - "What does Swift Evolution proposal SE-0001 propose?"
   - "List available frameworks"

## Claude Code

If you're using [Claude Code](https://code.claude.com/docs/en/overview), add Cupertino as an MCP server with a single command:

```bash
claude mcp add cupertino --scope user -- $(which cupertino)
```

This registers Cupertino globally for all your projects.

## OpenAI Codex

If you're using [OpenAI Codex](https://github.com/openai/codex), add Cupertino with:

```bash
codex mcp add cupertino -- $(which cupertino) serve --no-reap
```

Or add directly to `~/.codex/config.toml`:

```toml
[mcp_servers.cupertino]
command = "/opt/homebrew/bin/cupertino"  # Homebrew on Apple Silicon
# command = "/usr/local/bin/cupertino"   # Intel Mac or manual install
args = ["serve", "--no-reap"]
```

> **Why `--no-reap`?** Codex spawns a fresh `cupertino serve` per tool call. Without `--no-reap`, each new instance kills its predecessor as a stale sibling, and the in-flight transport closes (`Transport closed` error on every tool call; see [#280](https://github.com/mihaelamj/cupertino/issues/280)). Claude Desktop / Cursor users keep the default (reap on) so MCP-host config reloads don't leak orphan servers.
>
> Equivalent env-var form: `CUPERTINO_DISABLE_REAPER=1` in `[mcp_servers.cupertino.env]`.

## Cursor

Add to `.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` for global access):

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

## VS Code (GitHub Copilot)

Add to `.mcp.json` in your workspace:

```json
{
  "mcpServers": {
    "cupertino": {
      "type": "stdio",
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

## GitHub Copilot for Xcode

[GitHub Copilot for Xcode](https://github.com/github/CopilotForXcode) supports MCP servers via Agent Mode. In the app, go to the **Tools** tab → **MCP** sub-tab → **MCP Configuration** → **Edit Config**, or edit `~/.config/github-copilot/xcode/mcp.json` directly:

```json
{
  "servers": {
    "cupertino": {
      "type": "stdio",
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

## Zed

Add to your Zed `settings.json`:

```json
{
  "context_servers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

## Windsurf

Add to `~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "cupertino": {
      "command": "/opt/homebrew/bin/cupertino",
      "args": ["serve"]
    }
  }
}
```

## opencode

Add to `opencode.jsonc`:

```json
{
  "mcp": {
    "cupertino": {
      "type": "local",
      "command": ["/opt/homebrew/bin/cupertino", "serve"]
    }
  }
}
```

## No server: use as an Agent Skill

Cupertino can also run as a stateless CLI skill with no server process. See [docs/agent-skill.md](agent-skill.md).
