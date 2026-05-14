import Foundation
import SharedConstants
@testable import SharedUtils
import Testing

// MARK: - SharedUtils Public API Smoke Tests

// SharedUtils sits one rung above SharedConstants — it imports Foundation +
// SharedConstants (data-only) and provides stateless utility functions:
// JSON coding presets, path-resolver helpers, formatting, FTS-query
// escaping, schema-version arithmetic, URL extensions.
//
// Per #383 independence acceptance: SharedUtils imports only Foundation +
// SharedConstants. No behavioural cross-package import.
// `grep -rln "^import " Packages/Sources/Shared/Utils/` returns exactly
// `Foundation` and `SharedConstants`.
//
// These tests guard the public surface against accidental renames during
// refactor passes; behavioural tests live alongside the producers that
// drive the utilities (the existing SharedCoreTests suite covers
// JSONCoding round-trips, PathResolver behaviour, etc. through the
// SharedCore integration path).

@Suite("SharedUtils public surface")
struct SharedUtilsPublicSurfaceTests {
    @Test("JSONCoding namespace reachable")
    func jsonCodingNamespace() {
        _ = Shared.Utils.JSONCoding.encoder()
        _ = Shared.Utils.JSONCoding.decoder()
        _ = Shared.Utils.JSONCoding.prettyEncoder()
    }

    @Test("JSONCoding round-trips simple Codable values")
    func jsonCodingRoundTrip() throws {
        struct Probe: Codable, Equatable {
            let name: String
            let value: Int
        }
        let original = Probe(name: "leaf-382", value: 42)
        let data = try Shared.Utils.JSONCoding.encode(original)
        let decoded = try Shared.Utils.JSONCoding.decode(Probe.self, from: data)
        #expect(decoded == original)
    }

    @Test("PathResolver namespace reachable")
    func pathResolverNamespace() {
        // Just verify the static surface compiles; behavioural tests against
        // real disk paths live in SharedCoreTests, where filesystem fixtures
        // are wired up.
        _ = Shared.Utils.PathResolver.self
    }

    @Test("Formatting namespace reachable")
    func formattingNamespace() {
        _ = Shared.Utils.Formatting.self
    }

    @Test("FTSQuery namespace reachable")
    func ftsQueryNamespace() {
        _ = Shared.Utils.FTSQuery.self
    }

    @Test("SchemaVersion namespace reachable")
    func schemaVersionNamespace() {
        _ = Shared.Utils.SchemaVersion.self
    }

    @Test("URL(knownGood:) produces a usable URL")
    func urlKnownGoodExtension() throws {
        // URL(knownGood:) is the canonical Cupertino way to assert a literal
        // URL is valid — used wherever a string literal is known to parse.
        let url = try URL(knownGood: "https://developer.apple.com/documentation/")
        #expect(url.scheme == "https")
    }
}
