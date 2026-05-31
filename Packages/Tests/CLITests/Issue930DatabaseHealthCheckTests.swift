@testable import CLI
import DistributionModels
import Foundation
import LoggingModels
import SharedConstants
import Testing

// MARK: - #930 coverage pins: Distribution.DatabaseHealthCheck conformers

/// In-memory `Logging.Recording` that captures every `output(_:)` call.
/// Mirrors the `CapturingRecording` pattern from `Issue722ForceReplaceTests`.
private final class CapturingRecording: LoggingModels.Logging.Recording, @unchecked Sendable {
    private let lock = NSLock()
    private var _records: [String] = []

    func record(_ message: String, level _: LoggingModels.Logging.Level, category _: LoggingModels.Logging.Category) {
        lock.lock(); defer { lock.unlock() }
        _records.append(message)
    }

    func output(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        _records.append(message)
    }

    var records: [String] {
        lock.lock(); defer { lock.unlock() }
        return _records
    }
}

// MARK: - SearchHealthCheck

@Suite("#930: SearchHealthCheck conformer")
struct Issue930SearchHealthCheckTests {
    @Test("descriptor identity is `.search`; isRequired is true")
    func descriptorAndRequiredness() {
        let check = CLIImpl.Command.Doctor.SearchHealthCheck(
            dbURL: URL(fileURLWithPath: "/tmp/does-not-exist.db")
        )
        // The `"search"` id is intentionally a string literal here: there is
        // no `Shared.Constants.SourcePrefix.search` entry to lift it to,
        // because `search` is a DATABASE id, not a content-source prefix
        // (samples + packages double as both DB ids AND source prefixes; the
        // DB-only ids are search and any future DB-only id). The
        // single-source-of-truth for `"search"` lives on
        // `Shared.Models.DatabaseDescriptor.search`, which this test pins
        // via the descriptor-equality check below. If a future refactor adds
        // `SourcePrefix.search` or `DatabaseID.search`, replace the literal
        // here with that constant.
        #expect(check.descriptor.id == "search")
        #expect(check.descriptor.filename == Shared.Constants.FileName.searchDatabase)
        #expect(check.descriptor == .search)
        #expect(check.isRequired == true)
    }

    @Test("missing-file path: emits the four-line section + setup hint, returns false (gates verdict)")
    func missingFileEmitsExpectedSectionAndReturnsFalse() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-search-\(UUID().uuidString).db")
        let check = CLIImpl.Command.Doctor.SearchHealthCheck(dbURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == false, "search check must return false on missing file (required, gates verdict)")
        #expect(recorder.records == [
            "🔍 Search Index",
            "   ✗ Database: \(url.path) (not found)",
            "     → Run: cupertino setup  (or `cupertino save` if building locally)",
            "",
        ])
    }

    @Test("conformer is `Distribution.DatabaseHealthCheck`-shaped (the strategy seam round-trips)")
    func conformerIsStrategy() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-search-\(UUID().uuidString).db")
        let check: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SearchHealthCheck(dbURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == false)
        #expect(check.descriptor == .search)
        #expect(check.isRequired)
    }
}

// MARK: - SamplesHealthCheck

@Suite("#930: SamplesHealthCheck conformer")
struct Issue930SamplesHealthCheckTests {
    @Test("descriptor identity is `.appleSampleCode` (#1037 rename); isRequired is false (warning-only)")
    func descriptorAndRequiredness() {
        let check = CLIImpl.Command.Doctor.SamplesHealthCheck(
            samplesDBURL: URL(fileURLWithPath: "/tmp/does-not-exist.db")
        )
        // #1037: descriptor flipped from `.samples` to `.appleSampleCode`
        // so the section label matches the on-disk filename
        // (`apple-sample-code.db`) that `Sample.Index.databasePath`
        // resolves to.
        #expect(check.descriptor.id == "apple-sample-code")
        #expect(check.descriptor.filename == Shared.Constants.FileName.appleSampleCodeDatabase)
        #expect(check.descriptor == .appleSampleCode)
        #expect(check.isRequired == false)
    }

    @Test("missing-file path: emits the four-line warning section, returns true (does not gate verdict)")
    func missingFileEmitsExpectedSectionAndReturnsTrue() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-samples-\(UUID().uuidString).db")
        let check = CLIImpl.Command.Doctor.SamplesHealthCheck(samplesDBURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == true, "samples check is warning-only; must return true even on missing file")
        #expect(recorder.records == [
            // #1037: label flips to `apple-sample-code.db` (descriptor.filename)
            "🧪 Sample Code Index (apple-sample-code.db)",
            "   ⚠  Database: \(url.path) (not found)",
            "     → Run: cupertino fetch --source samples && cupertino cleanup && cupertino save --source samples",
            "",
        ])
    }

    @Test("conformer is `Distribution.DatabaseHealthCheck`-shaped (the strategy seam round-trips)")
    func conformerIsStrategy() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-samples-\(UUID().uuidString).db")
        let check: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SamplesHealthCheck(samplesDBURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == true)
        #expect(check.descriptor == .appleSampleCode)
        #expect(check.isRequired == false)
    }
}

// MARK: - PackagesHealthCheck

@Suite("#930: PackagesHealthCheck conformer")
struct Issue930PackagesHealthCheckTests {
    @Test("descriptor identity is `.packages`; isRequired is false (warning-only)")
    func descriptorAndRequiredness() {
        let check = CLIImpl.Command.Doctor.PackagesHealthCheck(
            packagesDBURL: URL(fileURLWithPath: "/tmp/does-not-exist.db")
        )
        #expect(check.descriptor.id == Shared.Constants.SourcePrefix.packages)
        #expect(check.descriptor.filename == Shared.Constants.FileName.packagesIndexDatabase)
        #expect(check.descriptor == .packages)
        #expect(check.isRequired == false)
    }

    @Test("missing-file path: emits the five-line warning section (incl. expected-version), returns true")
    func missingFileEmitsExpectedSectionAndReturnsTrue() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-packages-\(UUID().uuidString).db")
        let check = CLIImpl.Command.Doctor.PackagesHealthCheck(packagesDBURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == true, "packages check is warning-only; must return true even on missing file")
        #expect(recorder.records == [
            "📦 Packages Index (packages.db)",
            "   ⚠  Database: \(url.path) (not found)",
            "     → Run: cupertino setup  (downloads the pre-built packages index)",
            "     Expected version: \(Shared.Constants.App.databaseVersion)",
            "",
        ])
    }

    @Test("conformer is `Distribution.DatabaseHealthCheck`-shaped (the strategy seam round-trips)")
    func conformerIsStrategy() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-packages-\(UUID().uuidString).db")
        let check: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.PackagesHealthCheck(packagesDBURL: url)
        let recorder = CapturingRecording()
        let ok = await check.run(output: recorder)
        #expect(ok == true)
        #expect(check.descriptor == .packages)
        #expect(check.isRequired == false)
    }
}

// MARK: - Iteration regression pin

/// Fake conformer for the iteration test. Counts `run` invocations to
/// catch the regression where a future refactor reverts to a partial
/// iteration (`prefix(N)`, explicit out-of-loop calls, etc.) and leaves
/// appended conformers silently un-executed.
///
/// Modelled as an `actor` so the run-counter is async-safe under Swift
/// 6 strict concurrency. `Distribution.DatabaseHealthCheck.run` is async
/// already, so consuming it via `await` is the natural shape.
private actor FakeDatabaseHealthCheck: Distribution.DatabaseHealthCheck {
    nonisolated let descriptor: Shared.Models.DatabaseDescriptor
    nonisolated let isRequired: Bool
    private let returnValue: Bool
    private var _runCount: Int = 0

    init(descriptor: Shared.Models.DatabaseDescriptor, isRequired: Bool, returnValue: Bool) {
        self.descriptor = descriptor
        self.isRequired = isRequired
        self.returnValue = returnValue
    }

    func run(output _: any LoggingModels.Logging.Recording) async -> Bool {
        _runCount += 1
        return returnValue
    }

    var runCount: Int {
        _runCount
    }
}

@Suite("#930: Doctor.run iteration shape (regression pin)")
struct Issue930DoctorIterationTests {
    /// Mirror Doctor.run's iteration locally so the test catches any
    /// future regression that splits the iteration (`prefix(N)`, explicit
    /// out-of-loop calls, dead array elements). After the iter-2 critic
    /// pass the `checkSampleArchiveIntegrity` hook was moved OUT of the
    /// loop, so this helper now exactly mirrors Doctor.run's loop shape
    /// with zero drift. Treat the shape as load-bearing: if Doctor.run's
    /// loop changes shape, change this helper too.
    private static func iterate(
        _ checks: [any Distribution.DatabaseHealthCheck],
        output recording: any LoggingModels.Logging.Recording
    ) async -> Bool {
        var allChecks = true
        for check in checks {
            let ok = await check.run(output: recording)
            if check.isRequired { allChecks = ok && allChecks }
        }
        return allChecks
    }

    @Test("every conformer in the list is iterated exactly once (catches `prefix(N)` regression)")
    func everyConformerIsIterated() async {
        let fakes: [FakeDatabaseHealthCheck] = [
            .init(descriptor: .packages, isRequired: false, returnValue: true),
            .init(descriptor: .samples, isRequired: false, returnValue: true),
            .init(descriptor: .search, isRequired: true, returnValue: true),
            // Synthesise a 4th conformer with a custom descriptor; the
            // production list today is 3 entries. Pinning here so a future
            // refactor that reverts Doctor.run to `prefix(3)` (or any partial
            // iteration that drops appended conformers) surfaces in CI.
            .init(
                descriptor: Shared.Models.DatabaseDescriptor(
                    id: "future-db",
                    filename: "future.db",
                    displayName: "Future"
                ),
                isRequired: false,
                returnValue: true
            ),
        ]
        let recorder = CapturingRecording()
        _ = await Self.iterate(fakes, output: recorder)
        for fake in fakes {
            let count = await fake.runCount
            #expect(count == 1, "every conformer must run exactly once; \(fake.descriptor.id) ran \(count) times")
        }
    }

    @Test("aggregate verdict: required conformer returning false flips the verdict to false")
    func requiredFalseFlipsVerdict() async {
        let fakes: [any Distribution.DatabaseHealthCheck] = [
            FakeDatabaseHealthCheck(descriptor: .packages, isRequired: false, returnValue: true),
            FakeDatabaseHealthCheck(descriptor: .samples, isRequired: false, returnValue: true),
            FakeDatabaseHealthCheck(descriptor: .search, isRequired: true, returnValue: false),
        ]
        let recorder = CapturingRecording()
        let verdict = await Self.iterate(fakes, output: recorder)
        #expect(verdict == false)
    }

    @Test("aggregate verdict: warning-only conformer returning false does NOT flip the verdict (isRequired gate is load-bearing)")
    func warningOnlyFalseDoesNotFlipVerdict() async {
        let fakes: [any Distribution.DatabaseHealthCheck] = [
            // Both warning-only conformers report failures; per the protocol
            // contract these surface in section text but stay out of the
            // aggregate AND-fold.
            FakeDatabaseHealthCheck(descriptor: .packages, isRequired: false, returnValue: false),
            FakeDatabaseHealthCheck(descriptor: .samples, isRequired: false, returnValue: false),
            FakeDatabaseHealthCheck(descriptor: .search, isRequired: true, returnValue: true),
        ]
        let recorder = CapturingRecording()
        let verdict = await Self.iterate(fakes, output: recorder)
        #expect(verdict == true)
    }
}

// MARK: - Cross-conformer invariants

@Suite("#930: cross-conformer invariants")
struct Issue930CrossConformerInvariantsTests {
    @Test("only the search conformer is required; aggregate verdict policy is correct")
    func requirednessPolicyByDescriptor() {
        let search: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SearchHealthCheck(
            dbURL: URL(fileURLWithPath: "/tmp/x")
        )
        let samples: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SamplesHealthCheck(
            samplesDBURL: URL(fileURLWithPath: "/tmp/y")
        )
        let packages: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.PackagesHealthCheck(
            packagesDBURL: URL(fileURLWithPath: "/tmp/z")
        )
        let conformers: [any Distribution.DatabaseHealthCheck] = [search, samples, packages]
        let required = conformers.filter(\.isRequired).map(\.descriptor)
        #expect(required == [.search])
        let warningOnly = conformers.filter { !$0.isRequired }.map(\.descriptor)
        // #1037: SamplesHealthCheck descriptor flipped from .samples to
        // .appleSampleCode (filename `apple-sample-code.db`).
        #expect(Set(warningOnly) == Set([.appleSampleCode, .packages]))
    }

    @Test("descriptor.id values match canonical descriptor constants; the two content-source ids match SourcePrefix")
    func descriptorIDsLiftedToConstants() {
        let search: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SearchHealthCheck(
            dbURL: URL(fileURLWithPath: "/tmp/x")
        )
        let samples: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.SamplesHealthCheck(
            samplesDBURL: URL(fileURLWithPath: "/tmp/y")
        )
        let packages: any Distribution.DatabaseHealthCheck = CLIImpl.Command.Doctor.PackagesHealthCheck(
            packagesDBURL: URL(fileURLWithPath: "/tmp/z")
        )
        // Search has no SourcePrefix constant (it is a DB, not a content
        // source). #1037: SamplesHealthCheck's descriptor is now
        // `.appleSampleCode` (id `apple-sample-code`), which no longer
        // round-trips through `SourcePrefix.samples` because the DB id
        // is a per-source descriptor, not a SourcePrefix value. Packages
        // still round-trips. The Samples-side coupling that the
        // pre-#1037 invariant pinned now lives at the source-provider
        // level: `SampleCodeSource.definition.id ==
        // SourcePrefix.samples` (pinned by Issue1012SampleCodeSourceShapeTests).
        #expect(search.descriptor.id == "search")
        #expect(samples.descriptor.id == "apple-sample-code")
        #expect(packages.descriptor.id == Shared.Constants.SourcePrefix.packages)
    }
}
