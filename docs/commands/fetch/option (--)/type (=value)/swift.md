# --type swift

Fetch Swift.org Documentation

## Synopsis

```bash
cupertino fetch --type swift
```

## Description

Crawls and downloads Swift.org documentation, primarily focusing on The Swift Programming Language book and related Swift language documentation.

## Data Source

**Swift.org Documentation** - https://docs.swift.org/swift-book/documentation/the-swift-programming-language/

## Output

Creates Markdown files for each documentation page:
- One `.md` file per documentation page
- Hierarchical directory structure matching Swift.org organization
- Metadata tracking in `metadata.json`

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/swift-book` |
| Start URL | `https://docs.swift.org/swift-book/...` |
| Max Pages | 13,000 |
| Max Depth | 15 |
| Crawl Method | Web crawl via WKWebView |
| Authentication | Not required |
| Estimated Count | ~200-300 pages |

## Examples

### Fetch Swift.org Documentation
```bash
cupertino fetch --type swift
```

### Fetch with Custom Max Pages
```bash
cupertino fetch --type swift --max-pages 500
```

### Resume Interrupted Crawl
```bash
cupertino fetch --type swift --resume
```

### Force Recrawl All Pages
```bash
cupertino fetch --type swift --force
```

### Custom Output Directory
```bash
cupertino fetch --type swift --output-dir ./swift-docs
```

## Output Structure

```
~/.cupertino/swift-book/
├── metadata.json
├── TheBasics.md
├── BasicOperators.md
├── StringsAndCharacters.md
├── CollectionTypes.md
├── ControlFlow.md
├── Functions.md
├── Closures.md
├── Enumerations.md
├── StructuresAndClasses.md
└── ... (language guide chapters)
```

## Covered Content

### The Swift Programming Language
- **Language Guide** - Swift language fundamentals
  - The Basics
  - Basic Operators
  - Strings and Characters
  - Collection Types
  - Control Flow
  - Functions
  - Closures
  - Enumerations
  - Structures and Classes
  - Properties
  - Methods
  - Subscripts
  - Inheritance
  - Initialization
  - Deinitialization
  - Optional Chaining
  - Error Handling
  - Concurrency
  - Type Casting
  - Nested Types
  - Extensions
  - Protocols
  - Generics
  - Opaque Types
  - Automatic Reference Counting
  - Memory Safety
  - Access Control
  - Advanced Operators

- **Language Reference** - Formal language specification
  - Lexical Structure
  - Types
  - Expressions
  - Statements
  - Declarations
  - Attributes
  - Patterns
  - Generic Parameters and Arguments

## Crawl Behavior

1. **Respectful crawling** - 0.5 second delay between requests
2. **Change detection** - Only re-downloads changed pages (via content hash)
3. **Session persistence** - Can pause and resume crawls
4. **Auto-save** - Progress saved every 100 pages
5. **Error recovery** - Skips failed pages, continues crawling

## Performance

| Metric | Value |
|--------|-------|
| Initial crawl time | 15-30 minutes (200-300 pages) |
| Incremental update | Minutes (only changed) |
| Average page size | 20-100 KB (markdown) |
| Total storage | ~10-20 MB |
| Pages per minute | ~10-12 (with 0.5s delay) |

## Use Cases

- Offline Swift language reference
- Learning Swift programming
- Language feature lookup
- Full-text search of Swift docs
- AI-assisted Swift development
- Swift syntax reference

## Notes

- Focuses on Swift language documentation
- Does not include API documentation (use `--type docs` for APIs)
- No authentication required
- HTML automatically converted to Markdown
- Compatible with `cupertino save` for search indexing
- Updated with each Swift version release
