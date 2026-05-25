import ArgumentParser
@testable import CLI
import Foundation
import SharedConstants
import Testing

// MARK: - cupertino save `--source` + `--all` resolver tests

/// Tests for `CLIImpl.Command.Save.resolveSelectedSourceIDs(source:all:)`,
/// the static helper that validates the post-#1037 per-source CLI
/// surface (`--source <id>` repeatable + `--all`).
///
/// The triplet `--docs / --packages / --samples` was removed; pre-#1037
/// `cupertino save` with no flag built every DB by default, post-#1037
/// scope is explicit (per the "each source needs its own option, docs
/// cannot be for 4" direction).
@Suite("CLIImpl.Command.Save: --source + --all resolver")
struct SaveSourceResolverTests {
    @Test("`--all` returns every valid source id (registry-derived list + `packages`)")
    func allReturnsEveryValidID() throws {
        let resolved = try CLIImpl.Command.Save.resolveSelectedSourceIDs(source: [], all: true)
        let valid = CLIImpl.Command.Save.validSourceIDs()
        #expect(resolved == valid, "--all must select every id in validSourceIDs()")
        // Sanity: the expected canonical ids appear.
        #expect(resolved.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.hig))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.swiftEvolution))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.appleArchive))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.swiftOrg))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.swiftBook))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.samples))
        #expect(resolved.contains(Shared.Constants.SourcePrefix.packages))
    }

    @Test("Single `--source apple-docs` returns just that id")
    func singleSourceSelected() throws {
        let resolved = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
            source: [Shared.Constants.SourcePrefix.appleDocs],
            all: false
        )
        #expect(resolved == [Shared.Constants.SourcePrefix.appleDocs])
    }

    @Test("Multiple `--source` values combine into a set")
    func multipleSourcesSelected() throws {
        let resolved = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
            source: [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.hig,
                Shared.Constants.SourcePrefix.samples,
            ],
            all: false
        )
        #expect(resolved == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
        ])
    }

    @Test("Duplicate `--source` values collapse (Set semantics)")
    func duplicateSourceCollapses() throws {
        let resolved = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
            source: [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.hig,
            ],
            all: false
        )
        #expect(resolved == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
        ])
    }

    @Test("Both `--source` and `--all` is a usage error (mutual exclusion)")
    func sourceAndAllMutuallyExclusive() throws {
        #expect(throws: ExitCode.self) {
            _ = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
                source: [Shared.Constants.SourcePrefix.appleDocs],
                all: true
            )
        }
    }

    @Test("Bare `cupertino save` (neither flag) is a usage error (post-#1037 explicit scope)")
    func neitherFlagIsUsageError() throws {
        #expect(throws: ExitCode.self) {
            _ = try CLIImpl.Command.Save.resolveSelectedSourceIDs(source: [], all: false)
        }
    }

    @Test("Unknown `--source` id is a usage error")
    func unknownSourceIDIsUsageError() throws {
        #expect(throws: ExitCode.self) {
            _ = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
                source: ["not-a-real-source"],
                all: false
            )
        }
    }

    @Test("Mix of valid + invalid ids is a usage error (no partial selection)")
    func partialUnknownIsUsageError() throws {
        #expect(throws: ExitCode.self) {
            _ = try CLIImpl.Command.Save.resolveSelectedSourceIDs(
                source: [Shared.Constants.SourcePrefix.appleDocs, "bogus-id"],
                all: false
            )
        }
    }

    // MARK: - Docs-bucket classifier

    @Test("isDocsBucketSource maps every non-packages source to the docs bucket")
    func docsBucketClassifier() {
        // Every registry-enabled source EXCEPT `packages` falls into
        // the docs runner today. `samples` is in the docs bucket via
        // SampleCodeSource (FTS rows) AND triggers the standalone
        // samples runner (rich Sample.Index schema); both fire when
        // samples is selected.
        for id in CLIImpl.Command.Save.validSourceIDs() where id != Shared.Constants.SourcePrefix.packages {
            #expect(
                CLIImpl.Command.Save.isDocsBucketSource(id) == true,
                "Source id '\(id)' should map to the docs bucket"
            )
        }
        #expect(
            CLIImpl.Command.Save.isDocsBucketSource(Shared.Constants.SourcePrefix.packages) == false,
            "packages is its own bucket (PackagesService); NOT in the docs runner"
        )
    }
}
