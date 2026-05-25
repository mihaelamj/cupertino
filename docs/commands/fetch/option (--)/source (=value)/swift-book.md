# --source swift-book

Fetch The Swift Programming Language book.

## Synopsis

```bash
cupertino fetch --source swift-book
```

## Description

`swift-book` is a **view-source**: it has no dedicated crawl pipeline. The actual fetch runs the `swift-org` crawl (`docs.swift.org` is in `SwiftOrgStrategy`'s default URL allowlist alongside `www.swift.org`); during emission, pages whose URLs match the swift-book prefix get tagged with `source = swift-book` instead of `source = swift-org`.

From a user perspective, `cupertino fetch --source swift-book` behaves identically to `cupertino fetch --source swift-org`: same crawl, same output directory, same pages on disk. The flag exists so users can use the canonical source-id consistently across `search` / `read` / `fetch` surfaces; pre-#1031 this was implicit (the `--type swift` flag covered both swift-org and swift-book sub-sources).

## Examples

### Equivalent invocations

```bash
cupertino fetch --source swift-book
cupertino fetch --source swift-org   # produces the same on-disk output
```

### Search swift-book pages post-fetch

```bash
cupertino search "optional binding" --source swift-book
cupertino search "optional binding" --source swift-org   # also covers swift-book pages
```

## Output

`~/.cupertino/swift-org/` (shared with `--source swift-org`)

## Notes

- swift-book is a registered `Search.SourceProvider` (`SwiftBookSource`) with `fetchInfo == nil` (no dedicated fetch endpoint) but `destinationDB == .search` (search.db rows post-indexing).
- The `--source` flag is the canonical post-#1031 entry point; pre-#1031 swift-book was implicit in the `--type swift` crawl.
- Per the pluggability epic (#1007), swift-book exemplifies the "view-source" pattern: a logically distinct source that piggybacks on another source's crawl via URL-prefix tagging.

## See also

- [--source swift-org](swift-org.md)
- [--source all](all.md)
