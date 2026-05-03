# Default Type Behavior

When no `--type` is specified

## Synopsis

```bash
cupertino fetch
```

## Default Behavior

When you run `cupertino fetch` without the `--type` option, it defaults to:

```bash
cupertino fetch --type docs
```

This fetches **Apple Developer Documentation** from developer.apple.com.

## Why `docs` is the Default

- **Most commonly used** - Apple's documentation is the primary use case
- **Largest dataset** - ~13,000 pages of comprehensive API docs
- **Foundation for MCP server** - Core documentation for AI assistants
- **Best starting point** - Recommended for first-time setup

## Equivalent Commands

These commands are identical:

```bash
cupertino fetch
cupertino fetch --type docs
cupertino fetch --type docs --max-pages 1000000
```

## Other Type Options

To fetch different types, explicitly specify `--type`:

```bash
# Swift.org documentation
cupertino fetch --type swift

# Swift Evolution proposals
cupertino fetch --type evolution

# Swift packages metadata
cupertino fetch --type packages

# Apple sample code
cupertino fetch --type code

# Everything
cupertino fetch --type all
```

## Default Settings Summary

| Setting | Default Value |
|---------|---------------|
| Type | `docs` |
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
# Still uses docs type, but with options
cupertino fetch --max-pages 5000
cupertino fetch --start-clean   # discard saved session, start fresh
cupertino fetch --force         # re-fetch even unchanged pages
```

### Explicit Type
```bash
# Explicitly specify type
cupertino fetch --type evolution
```

## Notes

- Default can be overridden with `--type`
- All other options still apply with default type
- Use `cupertino fetch --help` to see all available types
- Default behavior matches most common use case
