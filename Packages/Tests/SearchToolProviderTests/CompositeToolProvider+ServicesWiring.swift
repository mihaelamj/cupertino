import Foundation
import SampleIndex
import SampleIndexModels
import SearchModels
import SearchToolProvider
import Services
import ServicesModels
import SharedConstants

// MARK: - CompositeToolProvider convenience init for tests

/// Test-side convenience initializer that wraps a pair of indexes with
/// the default concrete service implementations and forwards to the
/// primary protocol-typed init. Lives in the test target so the
/// production `SearchToolProvider` target doesn't need `import Services`.
///
/// 27 existing test callsites (`CupertinoSearchToolProviderTests.swift`)
/// construct the provider with just `searchIndex:` + `sampleDatabase:`;
/// this helper preserves that two-argument shape while keeping the
/// architectural seam clean — production code (the CLI's `serve`
/// command) uses the 6-argument primary init.
public extension CompositeToolProvider {
    init(
        searchIndex: (any Search.Database)?,
        sampleDatabase: (any Sample.Index.Reader)?,
        searchIndexDisabledReason: String? = nil
    ) {
        let docs = searchIndex.map(Services.DocsSearchService.init(database:))
        let sample = sampleDatabase.map(Sample.Search.Service.init(database:))
        let teaser: (any Services.Teaser)? =
            (searchIndex == nil && sampleDatabase == nil)
                ? nil
                : Services.TeaserService(
                    searchIndex: searchIndex,
                    sampleDatabase: sampleDatabase
                )
        let unified: (any Services.UnifiedSearcher)? =
            (searchIndex == nil && sampleDatabase == nil)
                ? nil
                : Services.UnifiedSearchService(
                    searchIndex: searchIndex,
                    sampleDatabase: sampleDatabase
                )
        self.init(
            searchIndex: searchIndex,
            sampleDatabase: sampleDatabase,
            docsService: docs,
            sampleService: sample,
            teaserService: teaser,
            unifiedService: unified,
            documentResourceProvider: nil,
            searchIndexDisabledReason: searchIndexDisabledReason
        )
    }
}
