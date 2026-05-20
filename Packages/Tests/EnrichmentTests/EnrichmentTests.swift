import Enrichment
import EnrichmentModels
import Testing

@Suite("Enrichment.LiveRunner")
struct EnrichmentLiveRunnerTests {
    private struct StubPass: EnrichmentPass {
        let identifier: String
        let dependsOn: [String]
        let target: EnrichmentModels.Target
        let schemaVersion = 1
        let shouldThrow: Bool

        init(_ identifier: String, dependsOn: [String] = [], target: EnrichmentModels.Target = .search, shouldThrow: Bool = false) {
            self.identifier = identifier
            self.dependsOn = dependsOn
            self.target = target
            self.shouldThrow = shouldThrow
        }

        func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            if shouldThrow {
                struct Boom: Error {}
                throw Boom()
            }
            return EnrichmentModels.Result(passIdentifier: identifier, rowsAffected: 1, rowsSkipped: 0, durationMs: 0)
        }
    }

    @Test("Empty registry returns empty results")
    func emptyRegistry() async throws {
        let runner = Enrichment.LiveRunner()
        let results = try await runner.run(target: .search)
        #expect(results.isEmpty)
    }

    @Test("Passes run in dependsOn topological order")
    func topologicalOrder() async throws {
        let passes: [any EnrichmentPass] = [
            StubPass("hierarchy", dependsOn: ["constraints"]),
            StubPass("synonyms"),
            StubPass("constraints"),
        ]
        let runner = Enrichment.LiveRunner(passes: passes)
        let results = try await runner.run(target: .search)
        let order = results.map(\.passIdentifier)
        #expect(order.firstIndex(of: "constraints")! < order.firstIndex(of: "hierarchy")!)
        #expect(order.contains("synonyms"))
    }

    @Test("Target filter scopes passes")
    func targetFilter() async throws {
        let passes: [any EnrichmentPass] = [
            StubPass("a", target: .search),
            StubPass("b", target: .samples),
            StubPass("c", target: .packages),
        ]
        let runner = Enrichment.LiveRunner(passes: passes)
        let search = try await runner.run(target: .search).map(\.passIdentifier)
        let samples = try await runner.run(target: .samples).map(\.passIdentifier)
        let packages = try await runner.run(target: .packages).map(\.passIdentifier)
        #expect(search == ["a"])
        #expect(samples == ["b"])
        #expect(packages == ["c"])
    }

    @Test("Thrown pass is recorded but does not abort siblings")
    func throwingPassDoesNotAbort() async throws {
        let passes: [any EnrichmentPass] = [
            StubPass("ok-before"),
            StubPass("boom", shouldThrow: true),
            StubPass("ok-after"),
        ]
        let runner = Enrichment.LiveRunner(passes: passes)
        let results = try await runner.run(target: .search)
        #expect(results.count == 3)
        let okAfter = results.first { $0.passIdentifier == "ok-after" }
        #expect(okAfter?.rowsAffected == 1)
    }

    @Test("Dependent pass is skipped when its dependency failed")
    func dependencyFailure() async throws {
        let passes: [any EnrichmentPass] = [
            StubPass("base", shouldThrow: true),
            StubPass("dependent", dependsOn: ["base"]),
        ]
        let runner = Enrichment.LiveRunner(passes: passes)
        let results = try await runner.run(target: .search)
        let dependent = results.first { $0.passIdentifier == "dependent" }
        #expect(dependent?.rowsAffected == 0)
    }

    @Test("Cycle in dependsOn throws")
    func cycleThrows() async {
        let passes: [any EnrichmentPass] = [
            StubPass("a", dependsOn: ["b"]),
            StubPass("b", dependsOn: ["a"]),
        ]
        let runner = Enrichment.LiveRunner(passes: passes)
        await #expect(throws: Enrichment.LiveRunner.RegistryError.self) {
            _ = try await runner.run(target: .search)
        }
    }
}
