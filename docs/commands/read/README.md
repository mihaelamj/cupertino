# cupertino read

Read a document from any indexed source (docs, samples, packages)

## Synopsis

```bash
cupertino read <identifier> [--source <name>] [options]
```

## Description

`cupertino read` is a unified front door that resolves an identifier to a full document across all three local databases — `search.db` (docs), `samples.db` (sample-code projects + files), and `packages.db` (package source files). Behaviour mirrors what every fan-out result in `cupertino search` emits:

```
▶ Read full: cupertino read <identifier> --source <name>
```

so an LLM consumer can drill into any candidate by copying that line verbatim.

Internally, dispatch is by either the `--source` flag (when the caller knows which DB to hit) or by inferring from the identifier shape (URI scheme → docs; otherwise tries samples then packages). The actual data lives in `Services/Commands/ReadService.swift`; this command is a thin CLI wrapper.

## Arguments

### identifier

The document identifier (required). Shape depends on the source:

| Source | Identifier shape | Example |
|---|---|---|
| docs (apple-docs / hig / archive / evolution / swift-org / swift-book) | URI scheme **or** Apple Developer web URL | `apple-docs://swiftui/view` _or_ `https://developer.apple.com/documentation/swiftui/view` |
| samples (project) | slugified id, no `/` | `swiftui-adopting-drag-and-drop-using-swiftui` |
| samples (file) | `<projectId>/<path>` | `swiftui-foo/Sources/main.swift` |
| packages | `<owner>/<repo>/<relpath>` | `pointfreeco/swift-navigation/Sources/UIKitNavigation/Documentation.docc/UIKitNavigation.md` |

Shape alone disambiguates URI vs. non-URI, but a sample-file path and a package path overlap. `--source` resolves it; `cupertino search` always emits the source so the hint is unambiguous.

#### Apple Developer web URLs (#587)

Canonical `https://developer.apple.com/documentation/<framework>/<path>` URLs are accepted directly — `cupertino read` rewrites them to the lossless `apple-docs://<framework>/<path>` URI at the entry point before dispatch. The MCP `read_document` tool applies the same rewrite so both transports accept the same input. Pasting a URL straight from the browser works without first knowing the URI scheme.

Non-Apple web URLs (`https://github.com/...`, `https://example.com/...`) pass through untouched; the per-source backends reject them as before.

## Options

### --source

Disambiguator for non-URI identifiers.

**Type:** String  
**Values:** `apple-docs`, `apple-archive`, `hig`, `swift-evolution`, `swift-org`, `swift-book`, `samples`, `packages`  
**Default:** auto-detected (URI scheme → docs; otherwise tries samples, then packages)

**Examples:**
```bash
cupertino read swiftui-controlling-the-timing-and-movements-of-your-animations --source samples
cupertino read pointfreeco/swift-navigation/Sources/.../UIKitNavigation.md --source packages
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --source apple-docs
```

### --format

Output format. Honoured by docs reads only; samples + packages return their stored content as-is.

**Type:** String  
**Values:** `json` (default), `markdown`

### --search-db

Path to the search database (`search.db`).

**Type:** String  
**Default:** `~/.cupertino/search.db`

### --sample-db

Path to the sample-code database (`samples.db`).

**Type:** String  
**Default:** `~/.cupertino/samples.db`

### --packages-db

Path to the packages database (`packages.db`).

**Type:** String  
**Default:** `~/.cupertino/packages.db`

## Examples

### Read a doc by URI

```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown
```

### Read a sample project's README

```bash
cupertino read swiftui-adopting-drag-and-drop-using-swiftui --source samples
```

### Read a sample file

```bash
cupertino read swiftui-food-truck/Sources/FoodTruck/Models/Order.swift --source samples
```

### Read a package source file

```bash
cupertino read pointfreeco/swift-navigation/Sources/UIKitNavigation/Documentation.docc/UIKitNavigation.md --source packages
```

### Workflow: search then drill in

```bash
# 1. Search across all sources, see candidates with read-full hints inline
cupertino search "swiftui list animation" --skip-docs --limit 3 --brief

# Output shows per-result:
#   ▶ Read full: cupertino read <id> --source <name>

# 2. Copy the line and run it
cupertino read swiftui-controlling-the-timing-and-movements-of-your-animations --source samples
```

### Pipe to other tools

```bash
cupertino read "apple-docs://swift/documentation_swift_array" --format json | jq '.declaration'
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown > view.md
```

## URI shapes (docs sources)

| Source | URI shape | Example |
|---|---|---|
| Apple Documentation | `apple-docs://<framework>/<path>` | `apple-docs://swiftui/documentation_swiftui_view` |
| Apple Archive | `apple-archive://<guide>/<page>` | `apple-archive://TP40014097/about-views` |
| HIG | `hig://<category>/<page>` | `hig://components/buttons` |
| Swift Evolution | `swift-evolution://<proposal-id>` | `swift-evolution://SE-0302` |
| Swift.org | `swift-org://<path>` | `swift-org://swift-org_documentation_articles_value-and-reference-types` |
| Swift Book | `swift-book://<path>` | `swift-book://swift-book_documentation_the-swift-programming-language_concurrency` |

## Output formats

### JSON (default for docs)

Structured document data: title, kind, module, declaration, abstract, overview, discussion, code examples, parameters, return values, conformance info, platform availability, deprecation notices. Best for AI agents and programmatic processing.

### Markdown (for docs)

Rendered markdown content with YAML front matter (source URL, crawl date), full body, code blocks with syntax highlighting, cross-references as `doc://` links.

### Samples + packages

Return their stored UTF-8 content as-is — README markdown for sample projects, file contents for sample files and package files. The `--format` flag is ignored on these paths.

## Error handling

### Document not found in search.db

```
Error: Document not found in search.db: apple-docs://invalid/path
```

**Solutions:** check spelling; run `cupertino search` to find valid URIs; ensure the doc is indexed (`cupertino save --docs`).

### Not found in samples.db

```
Error: Not found in samples.db: <projectId>
```

**Solutions:** verify the projectId via `cupertino list-samples`; rebuild via `cupertino save --samples`.

### Not found in packages.db

```
Error: Not found in packages.db: <owner>/<repo>/<relpath>
```

**Solutions:** verify the package was indexed (`cupertino doctor` shows package count); the file might be at a different path — search the package via `cupertino search --source packages`.

### Auto-source mode found nothing

```
Error: Tried docs, samples, and packages — no source matched. Identifier: <x>
```

**Solution:** pass `--source` explicitly so the error message is more specific.

### Database not found

Each backend has its own missing-DB error pointing at `cupertino setup` or the relevant `cupertino save --<scope>` rebuild command.

## See also

- [search](../search/) — fan-out search; emits `▶ Read full:` hints for every result
- [list-samples](../list-samples/) — enumerate sample projectIds
- [list-frameworks](../list-frameworks/) — enumerate docs frameworks
- [serve](../serve/) — start MCP server (mirror tool: `read_document`, `read_sample`, `read_sample_file`)
- [save](../save/) — build the three databases

## History

- [#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up: unified across docs / samples / packages. Pre-#239 this command only resolved docs URIs.
- Logic moved to `Services/Commands/ReadService.swift` so MCP tools and CLI share one implementation.
