# TODO

## High Priority

- [x] Add info in README about bundled resources (packages catalog, sample code catalog)
- [x] Add info in README about SQLite not working on network drives (NFS/SMB)

### Complete `cupertino save` Implementation ✅ DONE

**Priority 1: Make metadata.json optional** ✅ COMPLETED
- [x] Write tests for directory scanning without metadata.json
- [x] Make metadata optional in SearchIndexBuilder (CrawlMetadata → CrawlMetadata?)
- [x] Add scanDocsDirectory() method to scan docs/ folder structure
- [x] Update SaveCommand to not require metadata.json
- [x] Extract framework from folder path (docs/{framework}/{page}.md)
- [x] Generate URIs, content hashes, and timestamps on-the-fly

**Priority 2: Sample Code Indexing** ✅ COMPLETED
- [x] Write tests for sample code catalog indexing
- [x] Add indexSampleCodeCatalog() to SearchIndexBuilder
- [x] Wire up in buildIndex()
- [x] Add sampleCodeCount() and searchSampleCode() methods
- **Result:** 606 sample code entries indexed from bundled catalog

**Priority 3: Package Catalog Indexing** ✅ COMPLETED
- [x] Write tests for package catalog indexing
- [x] Add indexPackage() method to SearchIndex.swift
- [x] Add indexPackagesCatalog() to SearchIndexBuilder
- [x] Wire up in buildIndex()
- [x] Add packageCount() and searchPackages() methods
- **Result:** 9,699 Swift packages indexed from bundled catalog

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

## Search & Indexing

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
