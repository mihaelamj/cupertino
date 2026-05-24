// MARK: - Core Package

//
// HTML-to-Markdown / XML parser implementations for Apple documentation
// pages. Foundation-only post-#904; WebKit-backed concretes live in
// `CoreJSONParserWebKit` + `CoreSampleCodeWebKit` sibling targets. The
// Crawler concretes that drive these parsers live in the `Crawler` +
// `CrawlerWebKit` targets.
//
// Declared dependencies live in `Packages/Package.swift` and are
// tracked by `docs/package-import-contract.md`.

import SharedConstants
