@testable import CLI
import Distribution
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - Constants audit pin tests

//
// Cross-file consistency tests for constants added by the per-source
// DB split epic. The branch introduced several places where the same
// value is encoded in two locations (Swift enum + shell script, Swift
// descriptor + repo manifest YAML, FileName constant + descriptor
// filename field). This suite pins those cross-file equalities so a
// rename in one place fails CI loudly instead of silently shipping a
// mismatched pair.

@Suite("Constants audit: cross-file consistency for per-source DB split epic")
struct ConstantsAuditTests {
    // MARK: - Repo root resolution (mirrors Issue932IndexerInjectionTests pattern)

    private static func repoRoot() -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("scripts").path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: cwd)
    }

    private static func shellScriptText() throws -> String {
        let url = repoRoot().appendingPathComponent("scripts/check-source-manifests.sh")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Parse one of the `ALLOWED_*` arrays from check-source-manifests.sh.
    /// The arrays are multi-line bash arrays, e.g.:
    ///   ALLOWED_SEARCHERS=(
    ///       text symbols property-wrappers ...
    ///   )
    private static func parseAllowedSet(_ name: String, from script: String) -> Set<String> {
        // Find `<name>=(` and everything up to the next `)`.
        guard let startRange = script.range(of: "\(name)=(") else {
            return []
        }
        let afterStart = script[startRange.upperBound...]
        guard let endRange = afterStart.range(of: ")") else {
            return []
        }
        let body = afterStart[..<endRange.lowerBound]
        // Strip newlines + comments + extra whitespace; split on whitespace.
        let cleaned = body
            .components(separatedBy: .newlines)
            .map { line -> String in
                // Drop trailing # comments
                if let hashIndex = line.firstIndex(of: "#") {
                    return String(line[..<hashIndex])
                }
                return line
            }
            .joined(separator: " ")
        return Set(cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    // MARK: - DatabaseDescriptor ↔ FileName consistency

    @Test("Per-source DatabaseDescriptor filename matches its FileName constant exactly")
    func descriptorFilenameMatchesFileNameConstant() {
        let pairs: [(Shared.Models.DatabaseDescriptor, String)] = [
            (.appleDocumentation, Shared.Constants.FileName.appleDocumentationDatabase),
            (.hig, Shared.Constants.FileName.higDatabase),
            (.appleArchive, Shared.Constants.FileName.appleArchiveDatabase),
            (.swiftEvolution, Shared.Constants.FileName.swiftEvolutionDatabase),
            (.swiftDocumentation, Shared.Constants.FileName.swiftDocumentationDatabase),
            (.appleSampleCode, Shared.Constants.FileName.appleSampleCodeDatabase),
            (.swiftPackages, Shared.Constants.FileName.swiftPackagesDatabase),
        ]
        for (descriptor, fileName) in pairs {
            #expect(descriptor.filename == fileName, "descriptor '\(descriptor.id)' filename '\(descriptor.filename)' does not match FileName constant '\(fileName)'")
        }
    }

    @Test("Per-source DatabaseDescriptor.id equals filename's kebab-case stem (id + '.db' == filename)")
    func descriptorIDMatchesFilenameStem() {
        let descriptors: [Shared.Models.DatabaseDescriptor] = [
            .appleDocumentation, .hig, .appleArchive, .swiftEvolution,
            .swiftDocumentation, .appleSampleCode, .swiftPackages,
        ]
        for descriptor in descriptors {
            #expect(descriptor.filename == "\(descriptor.id).db", "descriptor id '\(descriptor.id)' and filename '\(descriptor.filename)' diverged")
        }
    }

    // MARK: - SourceProvider.definition.id ↔ SourcePrefix consistency

    @Test("Every production SourceProvider's definition.id has a matching SourcePrefix constant")
    func definitionIDsAreInSourcePrefix() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let prefixes = Set(Shared.Constants.SourcePrefix.allPrefixes)
        for provider in registry.allEnabled {
            #expect(
                prefixes.contains(provider.definition.id),
                "source '\(provider.definition.id)' is not in Shared.Constants.SourcePrefix.allPrefixes; pluggability gap (#932 candidate)"
            )
        }
    }

    @Test("Production registry's 8 SourceProviders have unique definition.ids (no aliasing)")
    func registryDefinitionIDsUnique() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let ids = registry.allEnabled.map(\.definition.id)
        #expect(Set(ids).count == ids.count, "duplicate source-ids: \(ids)")
    }

    // MARK: - Swift Capabilities enum ↔ shell validator allowed-sets

    @Test("Search.Capabilities.Searcher rawValues == ALLOWED_SEARCHERS in check-source-manifests.sh")
    func searcherEnumMatchesShellAllowedSet() throws {
        let script = try Self.shellScriptText()
        let shellSet = Self.parseAllowedSet("ALLOWED_SEARCHERS", from: script)
        let swiftSet = Set(Search.Capabilities.Searcher.allCases.map(\.rawValue))
        #expect(swiftSet == shellSet, "drift: Swift Searcher cases = \(swiftSet.sorted()); shell ALLOWED_SEARCHERS = \(shellSet.sorted())")
    }

    @Test("Search.Capabilities.Operation rawValues == ALLOWED_OPERATIONS in check-source-manifests.sh")
    func operationEnumMatchesShellAllowedSet() throws {
        let script = try Self.shellScriptText()
        let shellSet = Self.parseAllowedSet("ALLOWED_OPERATIONS", from: script)
        let swiftSet = Set(Search.Capabilities.Operation.allCases.map(\.rawValue))
        #expect(swiftSet == shellSet, "drift: Swift Operation cases = \(swiftSet.sorted()); shell ALLOWED_OPERATIONS = \(shellSet.sorted())")
    }

    @Test("Shell ALLOWED_FETCHER_KINDS is a superset of every manifest's fetcher.kind value")
    func everyManifestFetcherKindIsInAllowedSet() throws {
        let script = try Self.shellScriptText()
        let allowedKinds = Self.parseAllowedSet("ALLOWED_FETCHER_KINDS", from: script)
        let sourcesDir = Self.repoRoot().appendingPathComponent("docs/sources")
        let folders = try FileManager.default.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil)
        var anyFound = false
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let manifest = folder.appendingPathComponent("manifest.yaml")
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
            let yaml = try String(contentsOf: manifest, encoding: .utf8)
            // Naive regex: find `kind: <value>` under the fetcher block.
            // The manifests use single-key kind lines; this matches both
            // `  kind: web-crawl` and `  kind: github-api`.
            if let kindRange = yaml.range(of: "kind:", options: .literal) {
                let lineEnd = yaml[kindRange.upperBound...].firstIndex(of: "\n") ?? yaml.endIndex
                let kindRaw = yaml[kindRange.upperBound..<lineEnd]
                    .trimmingCharacters(in: .whitespaces)
                #expect(
                    allowedKinds.contains(kindRaw),
                    "manifest \(folder.lastPathComponent) declares fetcher.kind '\(kindRaw)' but it is NOT in shell ALLOWED_FETCHER_KINDS=\(allowedKinds.sorted())"
                )
                anyFound = true
            }
        }
        #expect(anyFound, "expected at least one manifest with a fetcher.kind declaration")
    }

    // MARK: - PerSourceDBSplitMigrator.legacyRenameSuffix is a single source of truth

    @Test("PerSourceDBSplitMigrator.legacyRenameSuffix is .legacy-pre-per-source-split (load-bearing literal)")
    func legacyRenameSuffixIsCanonical() {
        #expect(Distribution.PerSourceDBSplitMigrator.legacyRenameSuffix == ".legacy-pre-per-source-split")
    }

    // MARK: - Per-source capability matrix Swift ↔ YAML consistency

    //
    // Without a runtime YAML loader (deferred per corpus-structure.md §8),
    // we check the Swift declaration against a hardcoded snapshot of
    // what each manifest declares. If these drift, either Swift or
    // YAML is wrong; the test surfaces which.

    @Test("AppleDocsSource.capabilities.searchers matches docs/sources/apple-docs/manifest.yaml")
    func appleDocsCapabilitiesMatchManifest() {
        // YAML at docs/sources/apple-docs/manifest.yaml declares:
        //   searchers: [text, symbols, property-wrappers, concurrency, conformances, generics]
        //   operations: [read-by-uri, list-frameworks, resolve-refs]
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.appleDocs)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        let operations = Set(provider.capabilities.operations.map(\.rawValue))
        #expect(searchers == ["text", "symbols", "property-wrappers", "concurrency", "conformances", "generics"])
        #expect(operations == ["read-by-uri", "list-frameworks", "resolve-refs"])
    }

    @Test("HIGSource.capabilities.searchers matches docs/sources/hig/manifest.yaml")
    func higCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.hig)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        let operations = Set(provider.capabilities.operations.map(\.rawValue))
        #expect(searchers == ["text"])
        #expect(operations == ["read-by-uri"])
        // Critical contract pin: HIG must NOT advertise list-frameworks
        // (HIG rows carry framework="" at index time per CandidateFetcher).
        #expect(!operations.contains("list-frameworks"))
    }

    @Test("AppleArchiveSource.capabilities matches docs/sources/apple-archive/manifest.yaml")
    func appleArchiveCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.appleArchive)
        let operations = Set(provider.capabilities.operations.map(\.rawValue))
        // apple-archive IS in frameworkScopedSources so it DOES advertise list-frameworks.
        #expect(operations == ["read-by-uri", "list-frameworks"])
    }

    @Test("SwiftEvolutionSource.capabilities matches docs/sources/swift-evolution/manifest.yaml")
    func swiftEvolutionCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.swiftEvolution)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        let metadata = provider.capabilities.metadata
        #expect(searchers == ["text"])
        #expect(metadata[.hasMinSwiftVersion] == true)
        #expect(metadata[.hasProposalNumber] == true)
    }

    @Test("SwiftOrgSource.capabilities matches docs/sources/swift-org/manifest.yaml")
    func swiftOrgCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.swiftOrg)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        #expect(searchers == ["text", "symbols", "generics"])
    }

    @Test("SampleCodeSource.capabilities matches docs/sources/samples/manifest.yaml")
    func sampleCodeCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.samples)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        let operations = Set(provider.capabilities.operations.map(\.rawValue))
        let metadata = provider.capabilities.metadata
        #expect(searchers == ["text", "sample-files"])
        #expect(operations == ["read-by-uri", "list-samples"])
        #expect(metadata[.hasSampleCode] == true)
    }

    @Test("PackagesSource.capabilities matches docs/sources/packages/manifest.yaml")
    func packagesCapabilitiesMatchManifest() {
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.packages)
        let searchers = Set(provider.capabilities.searchers.map(\.rawValue))
        let metadata = provider.capabilities.metadata
        #expect(searchers == ["text", "package-search"])
        #expect(metadata[.hasPackageMetadata] == true)
        #expect(metadata[.hasMinSwiftVersion] == true)
    }

    // MARK: - Helpers

    private func providerForSourceID(_ sourceID: String) -> any Search.SourceProvider {
        let registry = CLIImpl.makeProductionSourceRegistry()
        guard let provider = registry.entry(for: sourceID)?.provider else {
            Issue.record("source-id '\(sourceID)' not in production registry")
            fatalError("source-id '\(sourceID)' missing")
        }
        return provider
    }
}
