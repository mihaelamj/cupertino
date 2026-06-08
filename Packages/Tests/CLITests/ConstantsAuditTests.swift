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

    private static func manifestText(forSourceFolder folder: String) throws -> String {
        let url = repoRoot().appendingPathComponent("docs/sources/\(folder)/manifest.yaml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Parse a YAML list under a named key inside a parent block. The
    /// manifests use:
    ///   capabilities:
    ///     searchers:
    ///       - text
    ///       - symbols
    /// This helper finds the `<parentKey>:` line, scans forward to the
    /// `<listKey>:` line (indented one level deeper), then collects the
    /// subsequent `  - <value>` lines until the indent drops. Returns
    /// the values as a `Set<String>` for order-insensitive comparison.
    ///
    /// Lightweight (no Yams dep); sufficient for the capability-matrix
    /// pin tests. If the YAML loader lands in a future commit
    /// (corpus-structure.md §8 open question), these tests migrate
    /// to it; until then, this parser closes the YAML ↔ Swift loop.
    private static func parseYAMLList(
        underParent parentKey: String,
        nestedKey listKey: String,
        in yaml: String
    ) -> Set<String> {
        let lines = yaml.components(separatedBy: .newlines)
        var inParent = false
        var inList = false
        var listIndent = -1
        var values: [String] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let leading = rawLine.prefix(while: { $0 == " " }).count

            if !inParent {
                if trimmed.hasPrefix("\(parentKey):") {
                    inParent = true
                }
                continue
            }
            if !inList {
                if trimmed.hasPrefix("\(listKey):") {
                    inList = true
                    continue
                }
                // A peer key of the parent (same indent or shallower) means
                // we left the parent block without finding listKey.
                if leading == 0 {
                    return Set(values)
                }
                continue
            }
            // In the list. Items start with `- `.
            if trimmed.hasPrefix("- ") {
                if listIndent < 0 {
                    listIndent = leading
                }
                if leading == listIndent {
                    // Strip optional inline `# comment` + surrounding
                    // quotes, symmetric with extractFetcherKind. Future
                    // YAML edits using quoted or commented list values
                    // would otherwise return the raw text including
                    // those markers and break the YAML-Swift pin.
                    let raw = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    let beforeComment: String = if let hashIndex = raw.firstIndex(of: "#") {
                        String(raw[..<hashIndex]).trimmingCharacters(in: .whitespaces)
                    } else {
                        raw
                    }
                    values.append(beforeComment.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                    continue
                }
            }
            // Anything else at shallower or equal indent ends the list.
            if leading <= listIndent || leading == 0 {
                break
            }
        }
        return Set(values)
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

    // MARK: - DatabaseDescriptor ↔ canonical literal pin

    //
    // Critic-fix: the prior version compared descriptor.filename against
    // the FileName constant the descriptor was BUILT FROM (tautology;
    // both sides update together). The real pin is "the value users
    // see on disk + in the bundle manifest". Comparing against an
    // explicit literal string is what catches a future rename of the
    // FileName constant (which would silently propagate to the
    // descriptor without breaking any test that compares them).

    @Test("DatabaseDescriptor.allKnown.count is at least the 10 descriptors that exist today (catches accidental deletion)")
    func descriptorRegistryFloor() {
        #expect(
            Shared.Models.DatabaseDescriptor.allKnown.count >= 10,
            "DatabaseDescriptor.allKnown must include all declared descriptors; a future addition append; never delete a still-shipping descriptor"
        )
    }

    @Test("Every DatabaseDescriptor.id + '.db' == filename (iterates allKnown; new descriptors join automatically)")
    func descriptorIDMatchesFilenameStem() {
        for descriptor in Shared.Models.DatabaseDescriptor.allKnown {
            #expect(descriptor.filename == "\(descriptor.id).db", "descriptor id '\(descriptor.id)' and filename '\(descriptor.filename)' diverged")
        }
    }

    @Test("Every DatabaseDescriptor.filename matches the canonical on-disk literal (drift sweep; iterates allKnown)")
    func descriptorFilenamePinnedAgainstCanonicalLiteral() {
        // The expected-filename lookup uses descriptor.id as key (NOT
        // the FileName constant, which would be tautological). The
        // table is what future code-readers grep for when asking
        // "what filename does cupertino ship for source X?".
        // Adding a new descriptor REQUIRES extending this table; the
        // test fails on a missing entry.
        let expectedByID: [String: String] = [
            "apple-documentation": "apple-documentation.db",
            "hig": "hig.db",
            "apple-archive": "apple-archive.db",
            "swift-evolution": "swift-evolution.db",
            // Pre-#1038 view-source descriptor (kept for migration
            // detection of legacy bundles).
            "swift-documentation": "swift-documentation.db",
            // Post #1038 ("diff db for each source"): swift-org and
            // swift-book each own their own DB.
            "swift-org": "swift-org.db",
            "swift-book": "swift-book.db",
            "apple-sample-code": "apple-sample-code.db",
            "swift-packages": "swift-packages.db",
            "search": "search.db",
            "samples": "samples.db",
            "packages": "packages.db",
        ]
        for descriptor in Shared.Models.DatabaseDescriptor.allKnown {
            let expected = expectedByID[descriptor.id]
            #expect(expected != nil, "DatabaseDescriptor.allKnown has descriptor '\(descriptor.id)' not in the canonical-filename map; extend expectedByID with the new entry")
            if let expected {
                #expect(
                    descriptor.filename == expected,
                    "descriptor '\(descriptor.id)' filename '\(descriptor.filename)' drifted from the canonical bundle filename '\(expected)'"
                )
            }
        }
    }

    // MARK: - SourceProvider.definition.id ↔ SourcePrefix consistency

    @Test("Built-in SourceProvider definition.ids have matching SourcePrefix constants")
    func builtInDefinitionIDsAreInSourcePrefix() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let registryIDs = Set(registry.allEnabled.map(\.definition.id))
        let prefixes = Set(Shared.Constants.SourcePrefix.allPrefixes)
        let builtInIDs: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ]
        for id in builtInIDs {
            #expect(
                registryIDs.contains(id),
                "built-in source '\(id)' is not registered in the production registry"
            )
            #expect(
                prefixes.contains(id),
                "built-in source '\(id)' is not in Shared.Constants.SourcePrefix.allPrefixes"
            )
        }
    }

    @Test("Production registry SourceProviders have unique definition.ids (no aliasing)")
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

    @Test("Every manifest declares a fetcher.kind that is in shell ALLOWED_FETCHER_KINDS (structural per-manifest pin)")
    func everyManifestFetcherKindIsInAllowedSet() throws {
        let script = try Self.shellScriptText()
        let allowedKinds = Self.parseAllowedSet("ALLOWED_FETCHER_KINDS", from: script)
        let sourcesDir = Self.repoRoot().appendingPathComponent("docs/sources")
        let folders = try FileManager.default.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil)
        var manifestsFound = 0
        var manifestsParsed = 0
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let manifest = folder.appendingPathComponent("manifest.yaml")
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
            manifestsFound += 1
            let yaml = try String(contentsOf: manifest, encoding: .utf8)
            // Structural: locate the column-0 `fetcher:` key, then scan
            // subsequent indented lines for `kind:`. Avoids the naive-
            // substring trap where a description block or sibling key
            // could match "kind:".
            let kindValue = Self.extractFetcherKind(from: yaml)
            #expect(
                kindValue != nil,
                "manifest \(folder.lastPathComponent) has no parseable fetcher.kind line"
            )
            if let kindRaw = kindValue {
                #expect(
                    allowedKinds.contains(kindRaw),
                    "manifest \(folder.lastPathComponent) declares fetcher.kind '\(kindRaw)' but it is NOT in shell ALLOWED_FETCHER_KINDS=\(allowedKinds.sorted())"
                )
                manifestsParsed += 1
            }
        }
        #expect(manifestsFound > 0, "expected at least one manifest under docs/sources/")
        #expect(
            manifestsParsed == manifestsFound,
            "drift: parsed fetcher.kind from \(manifestsParsed) of \(manifestsFound) manifests; missing manifests slip past the test silently"
        )
    }

    /// Structural extraction of `fetcher.kind` value. Anchors to the
    /// column-0 `fetcher:` key, scans subsequent lines whose leading
    /// indent > 0 for `kind:`, returns the trimmed value (stripping
    /// quotes + inline comments). Returns nil if no fetcher block or
    /// no kind line. Replaces the naive `range(of: "kind:")` lookup
    /// that could match unrelated `*Kind:` keys or "kind:" inside a
    /// description block.
    private static func extractFetcherKind(from yaml: String) -> String? {
        let lines = yaml.components(separatedBy: .newlines)
        var inFetcher = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let leading = line.prefix(while: { $0 == " " }).count
            if !inFetcher {
                if leading == 0, trimmed.hasPrefix("fetcher:") {
                    inFetcher = true
                }
                continue
            }
            if leading == 0 {
                return nil
            }
            if trimmed.hasPrefix("kind:") {
                let raw = String(trimmed.dropFirst("kind:".count)).trimmingCharacters(in: .whitespaces)
                let beforeComment: String = if let hashIndex = raw.firstIndex(of: "#") {
                    String(raw[..<hashIndex]).trimmingCharacters(in: .whitespaces)
                } else {
                    raw
                }
                return beforeComment.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    // MARK: - PerSourceDBSplitMigrator.legacyRenameSuffix is a single source of truth

    @Test("PerSourceDBSplitMigrator.legacyRenameSuffix is .legacy-pre-per-source-split (load-bearing literal)")
    func legacyRenameSuffixIsCanonical() {
        #expect(Distribution.PerSourceDBSplitMigrator.legacyRenameSuffix == ".legacy-pre-per-source-split")
    }

    // MARK: - Per-source capability matrix Swift ↔ YAML consistency

    //
    // True YAML ↔ Swift pin: for each registered SourceProvider that
    // has a manifest in docs/sources/<folder>/, the test reads the
    // YAML at runtime via the inline parser and compares the parsed
    // searchers + operations sets against the Swift property's set.
    // Drift in either side fails the test loudly with both sets
    // printed.
    //
    // The previous version of these tests hardcoded the expected
    // set as a Swift literal, creating a 3-way drift risk (YAML /
    // Swift property / test literal). The current version reads the
    // YAML directly + asserts against the Swift property only,
    // collapsing to a 2-way pin.

    /// A provider is a view-source (no fetcher of its own; rows
    /// emitted by another source's strategy) iff `fetchInfo == nil`.
    /// Today's only view-source is SwiftBookSource; the contract is
    /// the protocol shape rather than a hardcoded source-id check.
    /// View-sources do NOT have their own manifest.yaml.
    private func isViewSource(_ provider: any Search.SourceProvider) -> Bool {
        provider.fetchInfo == nil
    }

    @Test("Every non-view-source provider has a manifest AND its Swift capabilities.searchers matches the YAML (registry-iterated)")
    func swiftSearchersMatchManifestYAML() throws {
        let registry = CLIImpl.makeProductionSourceRegistry()
        var checked = 0
        for provider in registry.allEnabled {
            if isViewSource(provider) { continue }
            let folder = manifestFolderName(forSourceID: provider.definition.id)
            // Non-view-source providers MUST have a manifest. A missing
            // file is a real failure, not a silent skip.
            let yaml = try Self.manifestText(forSourceFolder: folder)
            let yamlSearchers = Self.parseYAMLList(underParent: "capabilities", nestedKey: "searchers", in: yaml)
            let swiftSearchers = Set(provider.capabilities.searchers.map(\.rawValue))
            #expect(
                yamlSearchers == swiftSearchers,
                "drift in source '\(provider.definition.id)': YAML searchers = \(yamlSearchers.sorted()); Swift = \(swiftSearchers.sorted())"
            )
            checked += 1
        }
        #expect(checked > 0, "expected at least one non-view-source provider to verify")
    }

    @Test("Every non-view-source provider's Swift capabilities.operations matches the YAML (registry-iterated)")
    func swiftOperationsMatchManifestYAML() throws {
        let registry = CLIImpl.makeProductionSourceRegistry()
        for provider in registry.allEnabled {
            if isViewSource(provider) { continue }
            let folder = manifestFolderName(forSourceID: provider.definition.id)
            let yaml = try Self.manifestText(forSourceFolder: folder)
            let yamlOperations = Self.parseYAMLList(underParent: "capabilities", nestedKey: "operations", in: yaml)
            let swiftOperations = Set(provider.capabilities.operations.map(\.rawValue))
            #expect(
                yamlOperations == swiftOperations,
                "drift in source '\(provider.definition.id)': YAML operations = \(yamlOperations.sorted()); Swift = \(swiftOperations.sorted())"
            )
        }
    }

    @Test("HIG operations MUST NOT contain list-frameworks (production CandidateFetcher.frameworkScopedSources contract; pinned on both sides)")
    func higHasNoListFrameworksOperation() throws {
        // The YAML-iterating tests above catch drift but not "both
        // sides incorrectly gain list-frameworks". This explicit pin
        // catches the failure where someone edits both files at once
        // without realising HIG rows carry framework="" at index time.
        let provider = providerForSourceID(Shared.Constants.SourcePrefix.hig)
        let swiftOperations = Set(provider.capabilities.operations.map(\.rawValue))
        #expect(
            !swiftOperations.contains("list-frameworks"),
            "HIG MUST NOT advertise list-frameworks (frameworkScopedSources = {appleDocs, appleArchive}; HIG rows carry framework=\"\")"
        )
        let yaml = try Self.manifestText(forSourceFolder: "hig")
        let yamlOperations = Self.parseYAMLList(underParent: "capabilities", nestedKey: "operations", in: yaml)
        #expect(!yamlOperations.contains("list-frameworks"), "docs/sources/hig/manifest.yaml MUST NOT declare list-frameworks")
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

    /// Map a SourceProvider.definition.id to its docs/sources/ folder
    /// name. Convention: folder name == sourceID. (Per #932 candidate
    /// work, a future runtime YAML loader would derive this from the
    /// manifest's `corpusFolder` field; today's convention matches the
    /// folder name to the id.)
    private func manifestFolderName(forSourceID sourceID: String) -> String {
        sourceID
    }
}
