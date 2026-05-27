import Foundation
@testable import SampleIndex
import SampleIndexModels
import SearchModels
import SharedConstants
import Testing

/// #1111 critic-pass: pin the tier ordering + MAX-merge inside
/// `Sample.Index.Builder.resolveSampleAvailability`. The unit tests
/// in `Issue1111SampleAvailableAggregationTests` exercise the
/// aggregator's pure-function shape; these tests pin the integration
/// path that wires the aggregator + framework lookup into the row's
/// final `min_<platform>` columns. Static method so no actor +
/// stub-database scaffolding is needed.
@Suite("#1111 resolveSampleAvailability tier ordering + MAX-merge")
struct Issue1111ResolveSampleAvailabilityTests {
    private typealias Versions = Search.PlatformVersions
    private typealias Resolver = Sample.Index.Builder

    @Test("Tier 1: Package.swift platforms wins outright")
    func packageSwiftWinsOutright() {
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: ["iOS": "16.0", "macOS": "13.0"],
            aggregatedAvailability: Versions(
                iOS: "14.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil
            ),
            frameworkProbe: "swiftui"
        )
        #expect(result.availabilitySource == "sample-swift")
        #expect(result.deploymentTargets["iOS"] == "16.0")
        #expect(result.deploymentTargets["macOS"] == "13.0")
    }

    @Test("Tier 2 MAX-merge: aggregator beats framework on iOS")
    func aggregatorBeatsFramework() {
        // SiriKit headline: source attr requires iOS 14.0, framework
        // table claims iOS 10.0; sample needs iOS 14 to compile.
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions(
                iOS: "14.0", macOS: nil, tvOS: nil, watchOS: "7.0", visionOS: nil
            ),
            frameworkProbe: "sirikit"
        )
        #expect(result.availabilitySource == "sample-available-aggregated")
        #expect(result.deploymentTargets["iOS"] == "14.0")
        // Framework's macOS 10.12 + visionOS 1.0 still get stamped where the aggregator was silent.
        #expect(result.deploymentTargets["macOS"] == "10.12")
        #expect(result.deploymentTargets["visionOS"] == "1.0")
        // Aggregator's watchOS 7.0 beats framework's 3.2.
        #expect(result.deploymentTargets["watchOS"] == "7.0")
    }

    @Test("Tier 2 MAX-merge: framework beats aggregator on iOS (back-port helper case)")
    func frameworkBeatsAggregator() {
        // SwiftUI sample (framework: iOS 13.0) with a single back-port helper marked `@available(iOS 11.0, *)`.
        // Aggregator's MAX iOS 11.0 must NOT lower SwiftUI's iOS 13.0 floor.
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions(
                iOS: "11.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil
            ),
            frameworkProbe: "swiftui"
        )
        // Tier label: aggregator didn't contribute the dominant value on any
        // platform, so the row is tagged `sample-framework-inferred`.
        #expect(result.availabilitySource == "sample-framework-inferred")
        #expect(result.deploymentTargets["iOS"] == "13.0") // from SwiftUI table, not the 11.0 attr
    }

    @Test("Tier 2: aggregator only (no framework) yields sample-available-aggregated")
    func aggregatorOnlyNoFramework() {
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions(
                iOS: "15.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil
            ),
            frameworkProbe: "unknown-framework-not-in-table"
        )
        #expect(result.availabilitySource == "sample-available-aggregated")
        #expect(result.deploymentTargets["iOS"] == "15.0")
        #expect(result.deploymentTargets["macOS"] == nil)
    }

    @Test("Tier 3: framework-only (no aggregator) yields sample-framework-inferred")
    func frameworkOnlyNoAggregator() {
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions?.none,
            frameworkProbe: "swiftui"
        )
        #expect(result.availabilitySource == "sample-framework-inferred")
        #expect(result.deploymentTargets["iOS"] == "13.0")
    }

    @Test("Tier 4: no signal at all yields nil source + empty dict")
    func noSignalYieldsNil() {
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions?.none,
            frameworkProbe: ""
        )
        #expect(result.availabilitySource == nil)
        #expect(result.deploymentTargets.isEmpty)
    }

    @Test("Unknown framework + nil aggregator yields NULL stamp (no universalApple)")
    func unknownFrameworkNoAggregatorYieldsNil() {
        let result = Resolver.resolveSampleAvailability(
            parsedDeploymentTargets: [:],
            aggregatedAvailability: Versions?.none,
            frameworkProbe: "totally-made-up-framework"
        )
        #expect(result.availabilitySource == nil)
        #expect(result.deploymentTargets.isEmpty)
    }
}
