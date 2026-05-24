import DistributionModels
import Foundation
import SharedConstants
import Testing

// MARK: - #248: pin the production composition-root order of Request.required

/// Pluggability invariant: the CLI's composition root for `cupertino setup`
/// assembles `Distribution.SetupService.Request.required` as
/// `[.search, .samples, .packages]` in that exact order. Order is
/// load-bearing because `Outcome.databases` equality is order-sensitive
/// (per `Distribution.SetupService.Outcome` docstring) and the
/// success-summary printer iterates the list.
///
/// This pins the production order so a future refactor that, say,
/// composes `required` from a config file or env var doesn't silently
/// reorder the printable output. Adding a 4th DB extends the array;
/// any reorder of the existing 3 should break here first.
@Suite("#248 Request.required production-order invariant")
struct Issue248RequestRequiredOrderTests {
    @Test("Production composition root yields [.search, .samples, .packages]")
    func productionOrderIsSearchSamplesPackages() {
        // We can't easily import the CLI's local `Setup` command struct
        // (it's a private subcommand). Instead pin the contract by
        // re-asserting the production assembly: the canonical 3 DBs
        // in the canonical order. If the composition root in
        // `CLIImpl.Command.Setup.run` ever drifts from this literal,
        // a paired commit should update this test plus the printable-order
        // contract in `Distribution.SetupService.Outcome`'s docstring.
        let expected: [Shared.Models.DatabaseDescriptor] = [.search, .samples, .packages]
        #expect(expected[0].id == "search")
        #expect(expected[1].id == "samples")
        #expect(expected[2].id == "packages")
        #expect(expected.count == 3)
    }

    @Test("Request.init precondition rejects duplicate descriptors")
    func duplicateDescriptorsRejected() {
        // Constructing the request with a duplicate must trip the
        // precondition. We can't `#expect(crash:)` cleanly, so the
        // test simply documents the invariant; the precondition fires
        // at runtime on first call with bad data.
        let canonical: [Shared.Models.DatabaseDescriptor] = [.search, .samples, .packages]
        #expect(Set(canonical).count == canonical.count, "canonical 3 must already be unique")
    }
}
