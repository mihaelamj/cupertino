# TODO

## High Priority

- [x] Add info in README about bundled resources (packages catalog, sample code catalog)
- [x] Add info in README about SQLite not working on network drives (NFS/SMB)


**Impact:**
- `cupertino save` now works WITHOUT metadata.json (uses directory scanning)
- Indexes 4 document sources instead of 2:
  - ✅ Apple documentation (directory scan: ~21,000 pages)
  - ✅ Swift Evolution proposals (~429 proposals)
  - ✅ Sample code catalog (606 entries)
  - ✅ Swift packages catalog (9,699 packages)
- Tests: 9/10 passing

**Production Validation:** ✅ VERIFIED
- Successfully indexed real documentation at `/Users/mm/Developer/cupertinodocs`
- **21,114 Apple docs** + **429 Evolution** + **606 Sample Code** + **9,699 Packages** = **31,848 total documents**
- 260 frameworks discovered
- Database size: 159.9 MB
- Zero files skipped - 100% success rate

### Other High Priority

- [ ] Add `--request-delay` parameter to FetchCommand (default 0.5s)
- [ ] Fix: fetch authenticate does not work (never opens Safari browser)
  - Investigate how other terminal commands handle browser auth
  - Search GitHub for code examples
  
- [ ] Add `cupertino-mcp` additional binary for compatibility with non-apple OS-es

## Search & Indexing

- [ ] Add vector/semantic search using sqlite-vec embeddings
- [ ] Implement search highlighting
- [ ] Implement fuzzy search
- [ ] Add filter by source_type
- [ ] Improve search ranking

## MCP Enhancements

- [ ] Resource templates for all types
- [ ] Streaming large docs
- [ ] Caching layer

## CLI Improvements

- [ ] Add `--verbose` flag
- [ ] Add progress bars
- [ ] Add colors to output
- [ ] Config file (.cupertinorc)

## Testing & Performance

- [ ] E2E MCP tests
- [ ] Search benchmarks
- [ ] Memory profiling
