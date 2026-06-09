# docs/ - Apple Documentation

Crawled Apple developer documentation in DocC render-JSON format.

## Location

**Default**: `~/.cupertino/docs/`

## Created By

```bash
cupertino fetch --source apple-docs
```

## Structure

```
~/.cupertino/docs/
├── metadata.json                                    # Crawl metadata
├── swift/                                          # Swift framework
│   ├── documentation_swift_array.json
│   ├── documentation_swift_dictionary.json
│   ├── documentation_swift_string.json
│   └── ...
├── swiftui/                                        # SwiftUI framework
│   ├── documentation_swiftui_view.json
│   ├── documentation_swiftui_text.json
│   ├── documentation_swiftui_button.json
│   └── ...
├── uikit/                                          # UIKit framework
│   ├── documentation_uikit_uiviewcontroller.json
│   ├── documentation_uikit_uitableview.json
│   └── ...
├── foundation/                                     # Foundation framework
│   ├── documentation_foundation_url.json
│   ├── documentation_foundation_urlsession.json
│   └── ...
├── storekit/                                       # StoreKit framework
│   ├── documentation_storekit_product_subscriptionoffer_signature.json
│   ├── documentation_storekit_understanding-storekit-workflows.json
│   └── ...
└── ...                                             # 250+ framework folders
```

## Contents

### Folder Organization
- **Top-level folders** = Framework names (lowercase)
- **Files** = DocC render-JSON documentation pages with `documentation_framework_` prefix

### Filename Format
```
documentation_{framework}_{topic}.json
```

### Example Paths
```
docs/swift/documentation_swift_array.json
docs/swiftui/documentation_swiftui_view.json
docs/uikit/documentation_uikit_uiviewcontroller.json
docs/foundation/documentation_foundation_url.json
docs/storekit/documentation_storekit_product_subscriptionoffer_signature.json
```

## Files

### JSON Files (.json)
- One file per documentation page
- Preserves DocC metadata, topic sections, rawMarkdown, relationships, and availability
- Carries code examples and related-page links consumed by `cupertino save --source apple-docs`

### [metadata.json](metadata.json.md)
- Tracks all crawled pages
- Content hashes for change detection
- URL to file path mappings
- Last crawl timestamps

## Size

- **Hundreds of thousands of JSON pages** for a full maintainer Apple documentation crawl
- Several GB on disk for the current full corpus
- Varies based on crawl scope and source freshness

## Usage

### Search This Documentation
```bash
# Build search index
cupertino save --source apple-docs --docs-dir ~/.cupertino/docs

# Use with MCP
cupertino
```

### Read Directly
```bash
# Inspect a raw DocC JSON page
open ~/.cupertino/docs/swiftui/documentation_swiftui_view.json
```

## Customizing Location

```bash
# Use custom directory
cupertino fetch --source apple-docs --output-dir ./my-apple-docs
```

## Availability Data

After running `cupertino fetch --source availability`, JSON files are updated with platform availability:

```json
{
  "title": "View",
  "url": "...",
  "availability": [
    {"name": "iOS", "introducedAt": "13.0", "deprecated": false, "beta": false},
    {"name": "macOS", "introducedAt": "10.15", "deprecated": false, "beta": false}
  ]
}
```

This enables:
- Filtering search results by minimum OS version
- Identifying deprecated APIs
- Tracking platform support

**Recommended workflow:**
```bash
cupertino fetch --source apple-docs         # Fetch documentation
cupertino fetch --source availability       # Add availability data
cupertino save --source apple-docs          # Build search index
```

## Notes

- Framework folders match URL structure
- Content is DocC JSON with markdown-bearing fields for easy parsing
- metadata.json enables resume and change detection
- Can be version controlled (though large)
