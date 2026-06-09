# --source swift-book

Fetch The Swift Programming Language book.

## Synopsis

```bash
cupertino fetch --source swift-book
```

## Description

`swift-book` is an independently fetchable source. It crawls `https://docs.swift.org/swift-book/documentation/the-swift-programming-language/` and writes the Swift Book corpus under the `swift-book` output directory.

Pre-#1093, Swift Book pages piggybacked on the Swift.org crawl. Current Cupertino keeps Swift.org and the Swift Book separate: `cupertino fetch --source swift-org` crawls `www.swift.org`, and `cupertino fetch --source swift-book` crawls only the book.

## Examples

### Fetch the Book

```bash
cupertino fetch --source swift-book
```

### Search swift-book pages post-fetch

```bash
cupertino search "optional binding" --source swift-book
```

## Output

`~/.cupertino/swift-book/`

## Notes

- swift-book is a registered `Search.SourceProvider` (`SwiftBookSource`) with its own `fetchInfo`, crawl seed, corpus directory, and destination DB (`swift-book.db`).
- The `--source` flag is the canonical post-#1031 entry point; pre-#1031 swift-book was implicit in the `--type swift` crawl.
- Per #1093, swift-book is no longer a view-source over `swift-org`; the two sources can be fetched and indexed independently.

## See also

- [--source swift-org](swift-org.md)
- [--source all](all.md)
