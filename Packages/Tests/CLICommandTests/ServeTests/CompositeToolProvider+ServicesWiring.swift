import Foundation
import SampleIndex
import SampleIndexModels
import SearchModels
import SearchToolProvider
import Services
import ServicesModels
import SharedConstants

// MARK: - CompositeToolProvider convenience init for ServeTests

/// Mirrors the same-named helper in SearchToolProviderTests. Lives here
/// because Swift test targets can't share extension files across
/// directories without playing path tricks. Kept identical to the
/// SearchToolProviderTests copy so the two test targets share the
/// same two-arg ergonomics while the production
/// `CompositeToolProvider` target stays free of `import Services`.
public extension CompositeToolProvider {
    init(
        searchIndex: (any Search.Database)?,
        sampleDatabase: (any Sample.Index.Reader)?
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
            unifiedService: unified
        )
    }
}
