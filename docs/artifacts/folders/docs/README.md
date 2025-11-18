# docs/ - Apple Documentation

Crawled Apple developer documentation in Markdown format.

## Location

**Default**: `~/.cupertino/docs/`

## Created By

```bash
cupertino crawl --type docs
```

## Structure

```
~/.cupertino/docs/
├── metadata.json                                    # Crawl metadata
├── swift/                                          # Swift framework
│   ├── documentation_swift_array.md
│   ├── documentation_swift_dictionary.md
│   ├── documentation_swift_string.md
│   └── ...
├── swiftui/                                        # SwiftUI framework
│   ├── documentation_swiftui_view.md
│   ├── documentation_swiftui_text.md
│   ├── documentation_swiftui_button.md
│   └── ...
├── uikit/                                          # UIKit framework
│   ├── documentation_uikit_uiviewcontroller.md
│   ├── documentation_uikit_uitableview.md
│   └── ...
├── foundation/                                     # Foundation framework
│   ├── documentation_foundation_url.md
│   ├── documentation_foundation_urlsession.md
│   └── ...
├── storekit/                                       # StoreKit framework
│   ├── documentation_storekit_product_subscriptionoffer_signature.md
│   ├── documentation_storekit_understanding-storekit-workflows.md
│   └── ...
└── ...                                             # 250+ framework folders
```

## Contents

### Folder Organization
- **Top-level folders** = Framework names (lowercase)
- **Files** = Markdown documentation pages with `documentation_framework_` prefix

### Filename Format
```
documentation_{framework}_{topic}.md
```

### Example Paths
```
docs/swift/documentation_swift_array.md
docs/swiftui/documentation_swiftui_view.md
docs/uikit/documentation_uikit_uiviewcontroller.md
docs/foundation/documentation_foundation_url.md
docs/storekit/documentation_storekit_product_subscriptionoffer_signature.md
```

## Files

### Markdown Files (.md)
- One file per documentation page
- Converted from HTML
- Preserves code examples
- Includes links to related pages

### [metadata.json](metadata.json.md)
- Tracks all crawled pages
- Content hashes for change detection
- URL to file path mappings
- Last crawl timestamps

## Size

- **~10,000-15,000 pages** for full Apple documentation crawl
- **~500 MB - 1 GB** total size
- Varies based on `--max-pages` setting

## Usage

### Search This Documentation
```bash
# Build search index
cupertino index --docs-dir ~/.cupertino/docs

# Use with MCP
cupertino-mcp serve
```

### Read Directly
```bash
# Browse with any Markdown viewer
open ~/.cupertino/docs/swiftui/view/index.md
```

## Customizing Location

```bash
# Use custom directory
cupertino crawl --type docs --output-dir ./my-apple-docs
```

## Notes

- Framework folders match URL structure
- All content is Markdown for easy parsing
- metadata.json enables resume and change detection
- Can be version controlled (though large)
