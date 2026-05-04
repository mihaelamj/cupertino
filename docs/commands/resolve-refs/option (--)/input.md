# --input

Directory of saved page JSONs

## Synopsis

```bash
cupertino resolve-refs --input <path>
```

## Description

Path to a directory containing saved `StructuredDocumentationPage` JSON files (typically the output of `cupertino fetch --type docs --discovery-mode json-only`). `resolve-refs` walks every `.json`, harvests a global `identifier → title` map from each page's `sections[].items[]`, and rewrites every `doc://com.apple.<bundle>/...` marker in `rawMarkdown` to the readable title.

## Default

Required (no default).

## Example

```bash
cupertino resolve-refs --input ~/.cupertino/docs
```

## Notes

- Pure post-process: no network by default. Use `--use-network` / `--use-webview` to fetch titles for unresolved markers.
- Idempotent — running twice is a no-op for already-resolved pages.
- Only `.json` files are processed; markdown / other files ignored.
