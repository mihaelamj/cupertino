# Cupertino Binaries

Executable binaries included in the Cupertino package.

## Binaries

| Binary | Description |
|--------|-------------|
| [cupertino-tui](cupertino-tui/) | Terminal UI for browsing packages, archives, and settings |
| [mock-ai-agent](mock-ai-agent/) | MCP testing tool for debugging server communication |
| [cupertino-rel](cupertino-rel/) | Release automation tool (maintainers only) |

## Installation

All binaries are built when you run:

```bash
cd Packages
swift build -c release
```

The binaries are located in `.build/release/`:
- `.build/release/cupertino`
- `.build/release/cupertino-tui`
- `.build/release/mock-ai-agent`
- `.build/release/cupertino-rel`

## Dev binary base directory ([#218](https://github.com/mihaelamj/cupertino/issues/218), [#675](https://github.com/mihaelamj/cupertino/issues/675))

### How it works (post-#675)

Every cupertino binary classifies itself at startup based on its install location:

| Binary location | Default `baseDirectory` |
|---|---|
| `/opt/homebrew/bin/cupertino` or any path under `/opt/homebrew/Cellar/` | `~/.cupertino/` (brew production) |
| `/usr/local/bin/cupertino` or any path under `/usr/local/Cellar/` | `~/.cupertino/` (Intel brew production) |
| `/home/linuxbrew/.linuxbrew/...` | `~/.cupertino/` (Linux brew production) |
| Anywhere else — `.build/`-relative dev build, CI workspace, manually copied binary, `/tmp/`, etc. | **`~/.cupertino-dev/`** (isolated) |

The dev-isolated default is the safety property: a binary you built locally cannot silently corrupt your brew install just by running a `save` / `setup` / `fetch` command. This is enforced by the binary itself at startup, not by any external build-step or Makefile drop, so it cannot be bypassed by skipping `make build-release` and using raw `swift build -c release` directly. ([#675](https://github.com/mihaelamj/cupertino/issues/675))

### Optional explicit override

If you need to target a different path (e.g. for testing the production code path against a sandbox copy, or running multiple dev binaries against different data), drop a `cupertino.config.json` next to the binary:

```bash
printf '{"baseDirectory":"~/some-other-dir"}\n' > .build/release/cupertino.config.json
```

The conf-file override wins over both default cases. `make build-debug DEV_BASE_DIR=~/some-other-dir` is the canonical way to specify this at build time.

### Brew bottle behaviour

Brew bottles ship only the binary (the `bottle:` Makefile target doesn't copy `cupertino.config.json`). Brew-installed binaries land at `/opt/homebrew/bin/cupertino` or `/usr/local/bin/cupertino`, which the provenance check classifies as `.brewInstalled`, and they resolve to `~/.cupertino/` as before — unchanged behaviour for end users.

### Migration note (pre-#675 conf files)

The `make build-debug` / `make build-release` targets continue to drop the `cupertino.config.json` for backwards compatibility, but it's no longer load-bearing for isolation. Old binaries built with the conf-drop continue to work identically. New binaries built without it now isolate correctly via the provenance default.

## See Also

- [Commands](../commands/) - Main CLI commands (`cupertino`)
- [Tools](../tools/) - MCP tools provided by the server
