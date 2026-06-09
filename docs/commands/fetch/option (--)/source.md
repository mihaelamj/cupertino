# --source

Source to fetch (canonical id from the per-source registry post-#1007 source-unification).

## Synopsis

```bash
cupertino fetch --source <id>
```

## Description

Specifies which source to fetch. Each canonical id matches one of the per-source SPM targets (`AppleDocsSource`, `HIGSource`, etc.) plus a small set of special tokens that aren't registered providers.

## Values

| Value | Description |
|-------|-------------|
| `apple-docs` | Apple Developer Documentation (default) |
| `swift-org` | Swift.org documentation |
| `swift-book` | The Swift Programming Language (independent Swift Book crawl) |
| `swift-evolution` | Swift Evolution proposals |
| `packages` | Swift package source archives (#217). Stage 2 by default; pass `--refresh-metadata` for the SPI metadata + stars (#1108). See `--skip-archives`. |
| `apple-sample-code` | Apple sample code, legacy bundle download (prefer `samples`) |
| `samples` | Apple sample code from GitHub (recommended) |
| `apple-archive` | Apple Archive legacy programming guides |
| `hig` | Human Interface Guidelines |
| `availability` | Platform availability data for docs (maintenance pass; not a registry source) |
| `all` | All sources in parallel |

## Default

`apple-docs`

## Examples

### Fetch Apple Documentation (Default)
```bash
cupertino fetch --source apple-docs
cupertino fetch  # same as above
```

### Fetch Swift Evolution
```bash
cupertino fetch --source swift-evolution
```

### Fetch All Sources
```bash
cupertino fetch --source all
```

## Value Details

- [apple-docs](source%20(=value)/apple-docs.md) - Apple Developer Documentation
- [swift-org](source%20(=value)/swift-org.md) - Swift.org documentation
- [swift-book](source%20(=value)/swift-book.md) - The Swift Programming Language
- [swift-evolution](source%20(=value)/swift-evolution.md) - Swift Evolution proposals
- [packages](source%20(=value)/packages.md) - Swift package metadata + source archives
- [apple-sample-code](source%20(=value)/apple-sample-code.md) - Apple sample code (Apple bundle)
- [samples](source%20(=value)/samples.md) - Apple sample code (GitHub)
- [apple-archive](source%20(=value)/apple-archive.md) - Apple Archive legacy guides
- [hig](source%20(=value)/hig.md) - Human Interface Guidelines
- [availability](source%20(=value)/availability.md) - Platform availability data
- [all](source%20(=value)/all.md) - All sources

## Notes

- Default is `apple-docs` if not specified.
- Each source has its own fetch strategy (web crawl, git clone, API + archive download, or maintenance pass).
- Use `--source all` for comprehensive local documentation.
- Pre-#1031 flag name was `--type` with shorter value names (`docs` / `swift` / `evolution` / `archive` / `code`); the rename came from the source-unification epic (#1007). Shell scripts referencing `--type` need to be updated to `--source` with the corresponding canonical id (mapping: `docs` to `apple-docs`, `swift` to `swift-org`, `evolution` to `swift-evolution`, `archive` to `apple-archive`, `code` to `apple-sample-code`; `packages` / `samples` / `hig` / `availability` / `all` unchanged).
