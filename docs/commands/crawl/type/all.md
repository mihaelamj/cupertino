# --type all

Crawl all documentation types in parallel.

## Usage

```bash
cupertino crawl --type all
```

## What It Does

When you specify `--type all`, Cupertino will:

1. **Run all WEB-BASED crawl types in parallel**:
   - Apple Documentation (`docs`)
   - Swift.org Documentation (`swift`)
   - Swift Evolution Proposals (`evolution`)

2. **Execute concurrently** - All three crawl types run at the same time for maximum efficiency

3. **Save to separate directories** - Each type saves to its default location:
   - `~/.cupertino/docs/` - Apple docs
   - `~/.cupertino/swift-org/` - Swift.org
   - `~/.cupertino/swift-evolution/` - Evolution proposals

## What It Does NOT Include

The `all` type does **NOT** include:
- Swift Packages (`packages`) - This is fetched via API, not crawled. See [packages](packages.md).

To get package metadata, run separately:
```bash
cupertino crawl --type packages
# OR use fetch command
cupertino fetch --type packages
```

## Example

```bash
# Crawl everything
cupertino crawl --type all

# Crawl everything with custom max pages
cupertino crawl --type all --max-pages 1000

# Crawl everything and force recrawl
cupertino crawl --type all --force
```

## Output

```
📚 Crawling all documentation types in parallel:

🚀 Starting Apple Documentation...
🚀 Starting Swift.org Documentation...
🚀 Starting Swift Evolution...

✅ Completed Apple Documentation
✅ Completed Swift.org Documentation
✅ Completed Swift Evolution

🎉 All crawls completed successfully!
```

## Options That Apply

The following options work with `--type all`:

- `--max-pages` - Applies to each crawl type
- `--max-depth` - Applies to web-based crawls (docs, swift, evolution)
- `--force` - Force recrawl for all types
- `--resume` - Resume any interrupted crawls
- `--output-dir` - Custom base directory (each type creates subdirectory)
- `--only-accepted` - Only affects evolution type

## Options That DON'T Apply

- `--start-url` - Each type uses its own default URL
- `--allowed-prefixes` - Each type uses its own prefixes

## Time Estimate

Crawling all documentation types takes approximately:

- **With default settings**: 2-4 hours
- **With `--max-pages 1000`**: 30-60 minutes
- **With `--max-pages 100`**: 5-10 minutes

Time varies based on network speed and Apple's server response time.

## Storage Requirements

Full crawl of all included types requires approximately:

- **Apple Documentation**: ~500 MB - 1 GB
- **Swift.org**: ~50-100 MB
- **Swift Evolution**: ~50-100 MB
- **Total**: ~600 MB - 1.2 GB

(Packages not included - see note above)

## Error Handling

If any crawl type fails:
- Other types continue running
- Final status shows which succeeded and which failed
- Exit code indicates overall failure if any type failed
- Re-run with `--resume` to retry failed types

## See Also

- [docs](docs.md) - Apple Documentation only
- [swift](swift.md) - Swift.org only
- [evolution](evolution.md) - Evolution proposals only
- [packages](packages.md) - Swift packages only
