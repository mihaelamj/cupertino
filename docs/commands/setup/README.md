# cupertino setup

Download pre-built search databases from GitHub.

## Synopsis

```bash
cupertino setup
```

## Description

The `setup` command downloads pre-built search databases from GitHub Releases, providing instant access to Apple documentation and sample code search without crawling or indexing.

This is the **fastest way to get started** with Cupertino.

## What Gets Downloaded

| Database | Contents | Size |
|----------|----------|------|
| `search.db` | 22,000+ documentation pages, 261 frameworks | ~150-200 MB |
| `samples.db` | 606 sample projects, 18,000+ source files | ~50-100 MB |

## Options

- `--base-dir` - Custom directory for databases (default: `~/.cupertino/`)
- `--force` - Re-download even if files exist

## Examples

### Quick Setup (Recommended)

```bash
cupertino setup
```

### Custom Location

```bash
cupertino setup --base-dir ~/my-docs
```

### Force Re-download

```bash
cupertino setup --force
```

## Output

```
📦 Cupertino Setup

⬇️  Downloading Documentation database...
   [████████████████████████████░░] 93% (186.2 MB/200.0 MB)
   ✓ Documentation database (200.0 MB)

⬇️  Downloading Sample code database...
   [██████████████████████████████] 100% (75.0 MB/75.0 MB)
   ✓ Sample code database (75.0 MB)

✅ Setup complete!
   Documentation: /Users/you/.cupertino/search.db
   Sample code:   /Users/you/.cupertino/samples.db

💡 Start the server with: cupertino serve
```

## Comparison

| Method | Time | Disk Space |
|--------|------|------------|
| `cupertino setup` | ~30 seconds | ~250 MB |
| `cupertino save --remote` | ~45 minutes | ~250 MB |
| `cupertino fetch && save` | ~20+ hours | ~3 GB + 250 MB |

## Next Steps

After setup, start the MCP server:

```bash
cupertino serve
```

Or simply:

```bash
cupertino
```

## See Also

- [serve](../serve/) - Start MCP server
- [save --remote](../save/option%20%28--%29/remote/) - Stream and build locally
- [fetch](../fetch/) - Download documentation manually
