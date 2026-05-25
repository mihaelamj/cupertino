import DistributionModels
import Foundation
import SharedConstants
import Testing

// MARK: - Per-source DatabaseDescriptor pin tests

//
// Step 1 of the per-source DB split epic (see
// `docs/design/per-source-db-split.md`): 5 new descriptors split out
// of search.db plus 2 renames of samples / packages. This suite pins
// the public surface of each new static so a rename, deletion, or id
// drift breaks CI at this seam instead of downstream at runtime.
//
// Naming policy settled with the user 2026-05-25 (see
// `cupertino-per-source-db-names-agreed` memory):
//
//   - Verbose names by default (`apple-documentation`, not
//     `apple-docs`).
//   - Initialism kept where industry-standard (`hig`, not
//     `human-interface-guidelines`).
//   - swift-book co-located in `swift-documentation.db` via the
//     SwiftOrgStrategy path-based view-source pattern: at index time
//     the strategy inspects the file-system path of each crawled doc
//     (Search.StrategyHelpers.extractFrameworkFromPath) and tags rows
//     with the first path component under the base directory. Today's
//     corpus has only `swift-book/` and `swift-org/` subdirs so the
//     emitted source-ids are "swift-book" and "swift-org"; a future
//     corpus snapshot adding a third subdirectory would emit that name
//     verbatim. No separate swift-book.db.
//
// These pins are additive: the legacy `.search`, `.samples`,
// `.packages` descriptors keep their existing pins in
// `DistributionModelsTests.swift` until step 6 lands.

@Suite("Per-source DatabaseDescriptor: 5 search.db splits + 2 renames")
struct PerSourceDBDescriptorTests {
    @Test("appleDocumentation descriptor: id + filename + displayName")
    func appleDocumentation() {
        let descriptor = Shared.Models.DatabaseDescriptor.appleDocumentation
        #expect(descriptor.id == "apple-documentation")
        #expect(descriptor.filename == "apple-documentation.db")
        #expect(descriptor.displayName == "Apple Developer Documentation")
    }

    @Test("hig descriptor (initialism kept per agreed naming): id + filename + displayName")
    func hig() {
        let descriptor = Shared.Models.DatabaseDescriptor.hig
        #expect(descriptor.id == "hig")
        #expect(descriptor.filename == "hig.db")
        #expect(descriptor.displayName == "Human Interface Guidelines")
    }

    @Test("appleArchive descriptor: id + filename + displayName")
    func appleArchive() {
        let descriptor = Shared.Models.DatabaseDescriptor.appleArchive
        #expect(descriptor.id == "apple-archive")
        #expect(descriptor.filename == "apple-archive.db")
        #expect(descriptor.displayName == "Apple Archive")
    }

    @Test("swiftEvolution descriptor: id + filename + displayName")
    func swiftEvolution() {
        let descriptor = Shared.Models.DatabaseDescriptor.swiftEvolution
        #expect(descriptor.id == "swift-evolution")
        #expect(descriptor.filename == "swift-evolution.db")
        #expect(descriptor.displayName == "Swift Evolution")
    }

    @Test("swiftDocumentation descriptor (swift-org + swift-book co-located): id + filename + displayName")
    func swiftDocumentation() {
        let descriptor = Shared.Models.DatabaseDescriptor.swiftDocumentation
        #expect(descriptor.id == "swift-documentation")
        #expect(descriptor.filename == "swift-documentation.db")
        #expect(descriptor.displayName == "Swift Documentation")
    }

    @Test("appleSampleCode descriptor (rename of .samples): id + filename + displayName")
    func appleSampleCode() {
        let descriptor = Shared.Models.DatabaseDescriptor.appleSampleCode
        #expect(descriptor.id == "apple-sample-code")
        #expect(descriptor.filename == "apple-sample-code.db")
        #expect(descriptor.displayName == "Apple Sample Code")
    }

    @Test("swiftPackages descriptor (rename of .packages): id + filename + displayName")
    func swiftPackages() {
        let descriptor = Shared.Models.DatabaseDescriptor.swiftPackages
        #expect(descriptor.id == "swift-packages")
        #expect(descriptor.filename == "swift-packages.db")
        #expect(descriptor.displayName == "Swift Packages")
    }

    @Test("All 7 per-source descriptors are distinct (no duplicate ids or filenames)")
    func allDistinct() {
        let descriptors = Self.newDescriptors
        #expect(Set(descriptors.map(\.id)).count == descriptors.count, "Duplicate id detected")
        #expect(Set(descriptors.map(\.filename)).count == descriptors.count, "Duplicate filename detected")
    }

    @Test("The 7 per-source ids match their kebab-case file stem (id + '.db' == filename)")
    func idMatchesFileStem() {
        for descriptor in Self.newDescriptors {
            #expect(descriptor.filename == descriptor.id + ".db", "id/filename mismatch on \(descriptor.id)")
        }
    }

    /// Source-of-truth references to the three legacy descriptors, so this
    /// suite's assertions stay coupled to production rather than to literal
    /// strings. If a legacy descriptor's id or filename is renamed in step 6
    /// the migration, these tests catch the collision automatically.
    private static let legacyDescriptors: [Shared.Models.DatabaseDescriptor] = [
        .search,
        .samples,
        .packages,
    ]

    private static let newDescriptors: [Shared.Models.DatabaseDescriptor] = [
        .appleDocumentation,
        .hig,
        .appleArchive,
        .swiftEvolution,
        .swiftDocumentation,
        .appleSampleCode,
        .swiftPackages,
    ]

    @Test("Per-source descriptors do not collide with legacy .search / .samples / .packages ids")
    func noLegacyCollision() {
        let legacyIDs = Set(Self.legacyDescriptors.map(\.id))
        for descriptor in Self.newDescriptors {
            #expect(!legacyIDs.contains(descriptor.id), "new descriptor '\(descriptor.id)' collides with a legacy id")
        }
    }

    @Test("Per-source descriptors do not collide with legacy filenames")
    func noLegacyFilenameCollision() {
        let legacyFilenames = Set(Self.legacyDescriptors.map(\.filename))
        for descriptor in Self.newDescriptors {
            #expect(
                !legacyFilenames.contains(descriptor.filename),
                "new descriptor '\(descriptor.id)' shadows the legacy filename '\(descriptor.filename)' (step 4 flip would silently corrupt bundle layout)"
            )
        }
    }

    @Test("Per-source descriptor + legacy union is 10 unique ids and 10 unique filenames")
    func unionDistinctness() {
        let allDescriptors = Self.legacyDescriptors + Self.newDescriptors
        #expect(Set(allDescriptors.map(\.id)).count == allDescriptors.count, "Duplicate id across legacy+new union")
        #expect(Set(allDescriptors.map(\.filename)).count == allDescriptors.count, "Duplicate filename across legacy+new union")
    }
}
