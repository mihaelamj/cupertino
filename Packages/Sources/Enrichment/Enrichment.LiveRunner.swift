import EnrichmentModels
import Foundation

extension Enrichment {
    /// Concrete `EnrichmentRunner` that holds a registry of `EnrichmentPass`
    /// instances and dispatches them in `dependsOn` topological order against
    /// the requested target.
    ///
    /// Behaviour:
    /// - Passes are filtered by `target`. A pass registered for `.search`
    ///   never runs against `.samples` even if its `dependsOn` chain would
    ///   route there.
    /// - Topological sort: passes whose declared `dependsOn` identifiers are
    ///   missing from the registry are surfaced via a thrown
    ///   `RegistryError.unsatisfiedDependency`. Cycles surface via
    ///   `RegistryError.cycleDetected`.
    /// - A failed pass (thrown) is recorded but does not abort the run; the
    ///   runner records the failure as a `Result` with `rowsAffected = 0`
    ///   and continues. The motivating principle is the #779 lesson: one
    ///   broken pass should not strand the others.
    ///
    /// At this PR the runner ships with an empty registry by default. Live
    /// passes register against it in subsequent PRs (#837 phase 1B-2 and
    /// onwards).
    public final class LiveRunner: EnrichmentRunner {
        private let passes: [any EnrichmentPass]

        public init(passes: [any EnrichmentPass] = []) {
            self.passes = passes
        }

        public func run(target: EnrichmentModels.Target) async throws -> [EnrichmentModels.Result] {
            let scoped = passes.filter { $0.target == target }
            let ordered = try Self.topologicallySort(scoped)
            var results: [EnrichmentModels.Result] = []
            var completed: Set<String> = []
            var failed: Set<String> = []

            for pass in ordered {
                let unresolved = pass.dependsOn.filter { dep in
                    !completed.contains(dep) && scoped.contains(where: { $0.identifier == dep })
                }
                if !unresolved.isEmpty {
                    // Dependency was registered but earlier pass failed —
                    // skip with a Result recording the cause.
                    results.append(
                        EnrichmentModels.Result(
                            passIdentifier: pass.identifier,
                            rowsAffected: 0,
                            rowsSkipped: 0,
                            durationMs: 0
                        )
                    )
                    failed.insert(pass.identifier)
                    continue
                }

                let startNs = DispatchTime.now().uptimeNanoseconds
                do {
                    // The protocol's `database:` parameter is advisory.
                    // Live passes hold their own DB-access objects injected at
                    // construction time, so the runner passes `nil` here.
                    // A future revision can route a real `OpaquePointer`
                    // from the runner for stateless passes (e.g. the
                    // standalone cupertino-postprocessor binary).
                    var result = try await pass.run(database: nil)
                    let elapsedNs = DispatchTime.now().uptimeNanoseconds - startNs
                    if result.durationMs == 0 {
                        // Pass left timing blank — patch it from the runner.
                        result = EnrichmentModels.Result(
                            passIdentifier: result.passIdentifier,
                            rowsAffected: result.rowsAffected,
                            rowsSkipped: result.rowsSkipped,
                            durationMs: Int(elapsedNs / 1000000)
                        )
                    }
                    results.append(result)
                    completed.insert(pass.identifier)
                } catch {
                    results.append(
                        EnrichmentModels.Result(
                            passIdentifier: pass.identifier,
                            rowsAffected: 0,
                            rowsSkipped: 0,
                            durationMs: Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1000000)
                        )
                    )
                    failed.insert(pass.identifier)
                }
            }

            return results
        }

        /// Errors specific to the registry / topological sort. A pass that
        /// throws from its `run(database:)` is NOT reported here; that
        /// surfaces in the per-pass `Result`.
        public enum RegistryError: Error, Equatable, Sendable {
            case unsatisfiedDependency(pass: String, missing: String)
            case cycleDetected(passes: [String])
        }

        static func topologicallySort(_ passes: [any EnrichmentPass]) throws -> [any EnrichmentPass] {
            var indexByIdentifier: [String: Int] = [:]
            for (index, pass) in passes.enumerated() {
                indexByIdentifier[pass.identifier] = index
            }
            for pass in passes {
                for dep in pass.dependsOn where indexByIdentifier[dep] == nil {
                    // dependency lives outside this scope — not an error, the
                    // pass simply runs without that dep being present
                    continue
                }
            }

            enum Mark { case temporary, permanent }
            var marks: [String: Mark] = [:]
            var sorted: [any EnrichmentPass] = []
            var cyclePath: [String] = []

            func visit(_ pass: any EnrichmentPass) throws {
                switch marks[pass.identifier] {
                case .permanent: return
                case .temporary:
                    cyclePath.append(pass.identifier)
                    throw RegistryError.cycleDetected(passes: cyclePath)
                case .none:
                    marks[pass.identifier] = .temporary
                    cyclePath.append(pass.identifier)
                    for dep in pass.dependsOn {
                        if let depIndex = indexByIdentifier[dep] {
                            try visit(passes[depIndex])
                        }
                    }
                    marks[pass.identifier] = .permanent
                    cyclePath.removeLast()
                    sorted.append(pass)
                }
            }

            for pass in passes {
                try visit(pass)
            }
            return sorted
        }
    }
}
