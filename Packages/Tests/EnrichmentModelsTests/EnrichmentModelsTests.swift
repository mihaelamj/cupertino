import EnrichmentModels
import Testing

@Suite("EnrichmentModels")
struct EnrichmentModelsTests {
    @Test("Target.allCases covers the three cupertino DBs")
    func targetAllCases() {
        let targets = EnrichmentModels.Target.allCases
        #expect(targets.count == 3)
        #expect(targets.contains(.search))
        #expect(targets.contains(.samples))
        #expect(targets.contains(.packages))
    }

    @Test("Target raw values are stable identifiers")
    func targetRawValues() {
        #expect(EnrichmentModels.Target.search.rawValue == "search")
        #expect(EnrichmentModels.Target.samples.rawValue == "samples")
        #expect(EnrichmentModels.Target.packages.rawValue == "packages")
    }

    @Test("Result is value-equal on identical fields")
    func resultEquality() {
        let lhs = EnrichmentModels.Result(passIdentifier: "synonyms", rowsAffected: 42, rowsSkipped: 7, durationMs: 12)
        let rhs = EnrichmentModels.Result(passIdentifier: "synonyms", rowsAffected: 42, rowsSkipped: 7, durationMs: 12)
        #expect(lhs == rhs)
    }

    @Test("EnrichmentPass conformance compiles and exposes the required surface")
    func conformanceCompiles() {
        struct DummyPass: EnrichmentPass {
            let identifier = "dummy"
            let schemaVersion = 1
            let dependsOn: [String] = []
            let target = EnrichmentModels.Target.search

            func run(database: OpaquePointer) async throws -> EnrichmentModels.Result {
                EnrichmentModels.Result(passIdentifier: identifier, rowsAffected: 0, rowsSkipped: 0, durationMs: 0)
            }
        }

        let pass: any EnrichmentPass = DummyPass()
        #expect(pass.identifier == "dummy")
        #expect(pass.schemaVersion == 1)
        #expect(pass.dependsOn.isEmpty)
        #expect(pass.target == .search)
    }
}
