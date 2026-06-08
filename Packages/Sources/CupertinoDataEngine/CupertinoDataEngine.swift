import Foundation
import SampleIndexModels
import SearchModels

// MARK: - CupertinoDataEngine

/// Read-only backend facade for embedded Cupertino clients.
///
/// UI layers should consume the protocol-typed readers this actor returns and
/// must not know about Cupertino's storage files. Concrete readers are supplied
/// by a Cupertino composition root through internal factory protocols, keeping
/// this package free of concrete SQLite producer imports.
public actor CupertinoDataEngine {
    nonisolated let configuration: Configuration

    private let sourceReaderFactory: (any Search.DatabaseFactory)?
    private let sampleReaderFactory: (any Sample.Index.DatabaseFactory)?
    private let packageReaderFactory: (any PackageReaderFactory)?
    private var sourceReaders: [String: any Search.Database] = [:]
    private var sampleReader: (any Sample.Index.Reader)?
    private var packageReader: (any PackageReader)?

    @_spi(CupertinoInternal)
    public init(
        configuration: Configuration,
        sourceReaderFactory: (any Search.DatabaseFactory)? = nil,
        sampleReaderFactory: (any Sample.Index.DatabaseFactory)? = nil,
        packageReaderFactory: (any PackageReaderFactory)? = nil
    ) async throws {
        self.configuration = configuration
        self.sourceReaderFactory = sourceReaderFactory
        self.sampleReaderFactory = sampleReaderFactory
        self.packageReaderFactory = packageReaderFactory

        let duplicateIDs = Dictionary(grouping: configuration.sourceCorpusResources, by: \.id)
            .filter { $0.value.count > 1 }
            .keys
        guard duplicateIDs.isEmpty else {
            throw Error.duplicateSourceID(duplicateIDs.sorted().joined(separator: ", "))
        }

        try await openSourceCorpusResources(configuration.sourceCorpusResources)
        try await openSampleResource(configuration.sampleResource)
        try await openPackageResource(configuration.packagesResource)
    }

    /// Stable list of configured source identifiers in corpus order.
    public nonisolated var sourceIDs: [String] {
        configuration.sourceCorpusResources.map(\.id)
    }

    /// Return a search/document/code-intelligence reader by source ID.
    public func sourceReader(id: String) throws -> any SourceReader {
        guard let reader = sourceReaders[id] else {
            throw Error.sourceNotConfigured(id)
        }
        return SourceReaderBox(base: reader)
    }

    /// Return the document-browser refinement for a configured source.
    public func documentBrowser(id: String) throws -> any SourceBrowser {
        guard let reader = sourceReaders[id] else {
            throw Error.sourceNotConfigured(id)
        }
        guard let browser = reader as? any Search.Database & Search.DocumentBrowsing else {
            throw Error.documentBrowserUnavailable(id)
        }
        return SourceBrowserBox(base: browser)
    }

    /// Return the sample-code reader, when configured.
    public func samples() throws -> any Sample.Index.Reader {
        guard let sampleReader else {
            throw Error.samplesNotConfigured
        }
        return SampleReaderBox(base: sampleReader)
    }

    /// Return the packages reader, when configured.
    public func packages() throws -> any Search.PackagesSearcher {
        guard let packageReader else {
            throw Error.packagesNotConfigured
        }
        return packageReader
    }

    /// Close every opened reader. Idempotent.
    public func disconnect() async {
        for reader in sourceReaders.values {
            await reader.disconnect()
        }
        sourceReaders.removeAll()

        if let sampleReader {
            await sampleReader.disconnect()
            self.sampleReader = nil
        }

        if let packageReader {
            await packageReader.disconnect()
            self.packageReader = nil
        }
    }

    private func openSourceCorpusResources(_ configurations: [SourceCorpusResource]) async throws {
        guard !configurations.isEmpty else { return }
        guard let sourceReaderFactory else {
            throw Error.sourceReaderFactoryNotConfigured
        }
        for configuration in configurations {
            try Self.requireCorpusResource(configuration.url, role: configuration.role)
            try SchemaProbe.assertPragmaUserVersion(
                at: configuration.url,
                expected: configuration.expectedSchemaVersion,
                role: configuration.role
            )
            sourceReaders[configuration.id] = try await sourceReaderFactory.openDatabase(at: configuration.url)
        }
    }

    private func openSampleResource(_ configuration: SampleResource?) async throws {
        guard let configuration else { return }
        guard let sampleReaderFactory else {
            throw Error.sampleReaderFactoryNotConfigured
        }
        try Self.requireCorpusResource(configuration.url, role: configuration.role)
        try SchemaProbe.assertSamplesSchemaVersion(
            at: configuration.url,
            expected: configuration.expectedSchemaVersion,
            role: configuration.role
        )
        sampleReader = try await sampleReaderFactory.openDatabase(at: configuration.url)
    }

    private func openPackageResource(_ configuration: PackageResource?) async throws {
        guard let configuration else { return }
        guard let packageReaderFactory else {
            throw Error.packageReaderFactoryNotConfigured
        }
        try Self.requireCorpusResource(configuration.url, role: configuration.role)
        try SchemaProbe.assertPragmaUserVersion(
            at: configuration.url,
            expected: configuration.expectedSchemaVersion,
            role: configuration.role
        )
        packageReader = try await packageReaderFactory.openPackageReader(at: configuration.url)
    }

    private static func requireCorpusResource(
        _ url: URL,
        role: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw Error.missingCorpusResource(role: role, path: url.path)
        }
    }
}
