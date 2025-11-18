# swift-org/ - Swift.org Documentation

Crawled Swift.org documentation including The Swift Programming Language book.

## Location

**Default**: `~/.cupertino/swift-org/`

## Created By

```bash
cupertino crawl --type swift
```

## Structure

```
~/.cupertino/swift-org/
├── metadata.json                                                                        # Crawl metadata
├── swift-book/                                                                          # The Swift Programming Language
│   ├── swift-book_documentation_the-swift-programming-language.md
│   ├── swift-book_documentation_the-swift-programming-language_aboutswift.md
│   ├── swift-book_documentation_the-swift-programming-language_compatibility.md
│   ├── swift-book_documentation_the-swift-programming-language_guidedtour.md
│   └── ...
└── swift-org/                                                                           # Swift.org content
    ├── blog_diversity-in-swift.md
    ├── blog_additional-linux-distros.md
    ├── blog_swift-atomics.md
    ├── blog_argument-parser.md
    ├── documentation_lldb.md
    ├── documentation_articles_swift-sdk-for-android-getting-started.html.md
    ├── documentation_articles_zero-to-swift-emacs.html.md
    ├── documentation_articles_static-linux-getting-started.html.md
    ├── packages_showcase-july-2024.html.md
    ├── packages_showcase-june-2024.html.md
    ├── packages_logging.html.md
    ├── swiftpm_documentation_packageplugin.md
    └── ...
```

## Contents

### Folder Organization
- **swift-book/** = The Swift Programming Language book
- **swift-org/** = Other Swift.org content (blogs, articles, packages)

### Filename Formats

**Swift Book:**
```
swift-book_documentation_the-swift-programming-language_{chapter}.md
```

**Swift.org Content:**
```
blog_{title}.md
documentation_{topic}.md
documentation_articles_{title}.html.md
packages_{name}.html.md
swiftpm_documentation_{topic}.md
```

### Example Paths
```
swift-org/swift-book/swift-book_documentation_the-swift-programming-language_aboutswift.md
swift-org/swift-org/blog_argument-parser.md
swift-org/swift-org/documentation_lldb.md
swift-org/swift-org/packages_logging.html.md
```

### The Swift Programming Language
- Complete Swift language guide
- All chapters in Markdown
- Code examples preserved
- Navigation links maintained

### Other Swift.org Content
- Getting started guides
- Swift evolution overview pages
- Community resources
- Blog posts

## Files

### Markdown Files (.md)
- Converted from Swift.org HTML
- Preserves formatting and code blocks
- Includes navigation structure

### [metadata.json](../docs/metadata.json.md)
- Tracks crawled pages
- Content change detection
- URL mappings

## Size

- **~500-1000 pages**
- **~50-100 MB** total
- Smaller than Apple docs

## Usage

### Search This Documentation
```bash
# Build search index
cupertino index --docs-dir ~/.cupertino/swift-org --search-db ~/.cupertino/swift-search.db
```

### Read The Swift Book
```bash
# Browse locally
open ~/.cupertino/swift-org/swift-book/
```

## Customizing Location

```bash
# Use custom directory
cupertino crawl --type swift --output-dir ./swift-docs
```

## Notes

- Focused on Swift language, not frameworks
- Great for offline Swift language reference
- The Swift Programming Language is the main content
- Smaller and faster to crawl than Apple docs
