# --metadata-file

Path to metadata.json file from crawl

## Synopsis

```bash
cupertino save --metadata-file <path>
```

## Description

Specifies the metadata file created during crawling. Contains additional information about crawled pages.

## Default

`~/.cupertino/docs/metadata.json`

## Examples

### Use Default Metadata
```bash
cupertino save
```

### Custom Metadata File
```bash
cupertino save --metadata-file ./my-docs/metadata.json
```

### No Metadata File
```bash
cupertino save --metadata-file ""
```

## Metadata File Contents

The metadata.json file includes:
- URL to file path mappings
- Content hashes
- Last crawl timestamps
- Framework associations

## Benefits

- Enriches search index with URL information
- Links indexed content back to source URLs
- Provides framework categorization
- Enables better search result metadata

## Notes

- Optional but recommended
- Created automatically by `cupertino fetch`
- JSON format
- If omitted, index still works but with less metadata
- Must match the docs directory being indexed
