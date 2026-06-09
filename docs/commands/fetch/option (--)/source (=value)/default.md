# Default Source Behavior

When no `--source` is specified

## Synopsis

```bash
cupertino fetch
```

## Default Behavior

When you run `cupertino fetch` without the `--source` option, it defaults to:

```bash
cupertino fetch --source apple-docs
```

This fetches **Apple Developer Documentation** from developer.apple.com.

## Why `apple-docs` is the Default

- **Most commonly used** - Apple's documentation is the primary use case
- **Largest dataset** - ~404,000+ pages of comprehensive API docs
- **Foundation for MCP server** - Core documentation for AI assistants
- **Best starting point** - Recommended for first-time setup

## Equivalent Commands

These commands are identical:

```bash
cupertino fetch
cupertino fetch --source apple-docs
cupertino fetch --source apple-docs --max-pages 1000000
```

## Other Source Options

To fetch different sources, explicitly specify `--source`:

```bash
# Swift.org documentation
cupertino fetch --source swift-org

# Swift Evolution proposals
cupertino fetch --source swift-evolution

# Swift packages metadata
cupertino fetch --source packages

# Apple sample code
cupertino fetch --source apple-sample-code

# Everything
cupertino fetch --source all
```

## Default Settings Summary

| Setting | Default Value |
|---------|---------------|
| Source | `apple-docs` |
| Start URL | `https://developer.apple.com/documentation/` |
| Output Directory | `~/.cupertino/docs` |
| Max Pages | 1,000,000 (effectively uncapped) |
| Max Depth | 15 |

## Common Workflows

### Quick Start (Default)
```bash
# Uses all defaults
cupertino fetch
```

### With Custom Options
```bash
# Still uses the default apple-docs source, but with options
cupertino fetch --max-pages 5000
cupertino fetch --start-clean   # discard saved session, start fresh
cupertino fetch --force         # re-fetch even unchanged pages
```

### Explicit Source
```bash
# Explicitly specify source
cupertino fetch --source swift-evolution
```

## Notes

- Default can be overridden with `--source`
- All other options still apply with the default source
- Use `cupertino fetch --help` to see all available sources
- Default behavior matches most common use case
