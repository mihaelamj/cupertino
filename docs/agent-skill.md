# Use Cupertino as an Agent Skill (no server required)

Cupertino can be used as a stateless CLI skill without running an MCP server. This is useful for agents that support the [Agent Skills](https://agentskills.io) specification.

For MCP-server setup instead, see [docs/mcp-clients.md](mcp-clients.md).

## Prerequisites

Install cupertino and download the databases first:

```bash
# Install via Homebrew or from source (see the README Installation section)
cupertino setup
```

## Option A: Install with OpenSkills (recommended)

[OpenSkills](https://github.com/numman-ali/openskills) is a universal skills loader that works with Claude Code, Cursor, Windsurf, Aider, and other AI coding agents.

```bash
# Install the cupertino skill from GitHub
npx openskills install mihaelamj/cupertino

# Sync to update AGENTS.md
npx openskills sync
```

For global installation (available in all projects):

```bash
npx openskills install mihaelamj/cupertino --global
```

For multi-agent setups (installs to `.agent/skills/` instead of `.claude/skills/`):

```bash
npx openskills install mihaelamj/cupertino --universal
```

## Option B: Install as a Claude Code plugin

Inside a Claude Code session, add the cupertino marketplace:

```
/plugin marketplace add mihaelamj/cupertino
```

Then enable the plugin from the marketplace.

## Option C: Manual installation

Copy the skill definition to your project or global skills directory:

```bash
# Clone this repo
git clone https://github.com/mihaelamj/cupertino.git

# For a single project
mkdir -p .claude/skills/cupertino
cp cupertino/skills/cupertino/SKILL.md .claude/skills/cupertino/

# Or for global use with Claude Code
mkdir -p ~/.claude/skills/cupertino
cp cupertino/skills/cupertino/SKILL.md ~/.claude/skills/cupertino/
```

## How it works

The skill uses the CLI directly with JSON output, no server process needed:

```bash
# Search documentation
cupertino search "SwiftUI View" --format json

# Filter by source
cupertino search "NavigationStack" --source apple-docs --format json
cupertino search "button styles" --source samples --format json

# Read a document
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format json

# List frameworks
cupertino list-frameworks --format json

# List sample projects
cupertino list-samples --framework swiftui --format json
```

All commands support `--format json` for structured output that agents can parse.

## Available sources

- `apple-docs` - Official Apple documentation (~351,505 pages indexed in v1.3.0)
- `samples` - Apple sample code projects
- `hig` - Human Interface Guidelines
- `swift-evolution` - Swift Evolution proposals
- `swift-org` - Swift.org documentation
- `swift-book` - The Swift Programming Language book
- `apple-archive` - Legacy programming guides
- `packages` - Swift package documentation
