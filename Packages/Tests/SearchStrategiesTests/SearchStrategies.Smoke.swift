import AppleArchiveStrategy
import AppleDocsSource
import HIGStrategy
import SampleCodeStrategy
import SearchModels
import SwiftEvolutionStrategy
import SwiftOrgStrategy
import Testing

@Suite("SearchStrategies smoke")
struct SearchStrategiesSmokeTests {
    @Test("the 6 concrete strategy metatypes are reachable from SearchStrategies")
    func strategyMetatypesAreReachable() {
        // Compile-time evidence that each of the 6 lifted strategy concretes
        // is exported by SearchStrategies. If any strategy is renamed or
        // its access level drops below `public`, the build fails here.
        _ = Search.AppleArchiveStrategy.self
        _ = Search.AppleDocsStrategy.self
        _ = Search.HIGStrategy.self
        _ = Search.SampleCodeStrategy.self
        _ = Search.SwiftEvolutionStrategy.self
        _ = Search.SwiftOrgStrategy.self
        _ = Search.StrategyHelpers.self
        #expect(Bool(true))
    }
}
