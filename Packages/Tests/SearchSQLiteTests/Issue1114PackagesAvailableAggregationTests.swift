import Foundation
import SearchModels
@testable import SearchSQLite
import Testing

/// #1114: packages.db's `package_metadata.min_<platform>` columns
/// now stamp from a MAX-merge of (per-file `@available` aggregator,
/// `Package.swift` deployment targets) instead of Package.swift only.
/// Parallel to #1111 for apple-sample-code. These tests pin the
/// MAX-merge helpers on `Search.PackageIndexer` directly without
/// going through the full availability.json load.
@Suite("#1114 packages MAX-merge aggregation helpers")
struct Issue1114PackagesAvailableAggregationTests {
    private typealias Versions = Search.PlatformVersions
    private typealias Indexer = Search.PackageIndexer

    @Test("MAX-merge: aggregator beats Package.swift on iOS")
    func aggregatorBeatsPackageSwift() {
        // swift-argument-parser headline: Package.swift says iOS 13,
        // but some @available attr in the source requires iOS 15.0.
        // Sample needs iOS 15 to compile.
        let aggregated = Versions(iOS: "15.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil)
        let packageSwift = Versions(iOS: "13.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil)
        let merged = Indexer.maxMergePlatformVersions(aggregated, packageSwift)
        #expect(merged?.versions.iOS == "15.0")
        #expect(merged?.versions.macOS == "10.15") // from Package.swift (aggregator was nil here)
        #expect(merged?.aggregatedContributed == true)
    }

    @Test("MAX-merge: Package.swift wins when aggregator's value is lower")
    func packageSwiftBeatsAggregator() {
        // Back-port case: package's main code uses iOS 16 APIs unconditionally
        // (Package.swift says iOS 16), but one helper is `@available(iOS 11.0, *)`.
        // Aggregator picks up 11.0 but Package.swift says 16.0; floor is 16.0.
        let aggregated = Versions(iOS: "11.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil)
        let packageSwift = Versions(iOS: "16.0", macOS: "13.0", tvOS: nil, watchOS: nil, visionOS: nil)
        let merged = Indexer.maxMergePlatformVersions(aggregated, packageSwift)
        #expect(merged?.versions.iOS == "16.0")
        #expect(merged?.aggregatedContributed == false)
    }

    @Test("MAX-merge: equal values don't flip the aggregator tag")
    func equalValuesKeepPackageSwiftTag() {
        let aggregated = Versions(iOS: "13.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil)
        let packageSwift = Versions(iOS: "13.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil)
        let merged = Indexer.maxMergePlatformVersions(aggregated, packageSwift)
        #expect(merged?.versions.iOS == "13.0")
        #expect(merged?.aggregatedContributed == false)
    }

    @Test("MAX-merge: only aggregator value (no Package.swift) tags aggregated")
    func aggregatorOnlyTagsAggregated() {
        let aggregated = Versions(iOS: "14.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil)
        let merged = Indexer.maxMergePlatformVersions(aggregated, nil)
        #expect(merged?.versions.iOS == "14.0")
        #expect(merged?.aggregatedContributed == true)
    }

    @Test("MAX-merge: only Package.swift (no aggregator) keeps package-swift tag")
    func packageSwiftOnlyTagsPackageSwift() {
        let packageSwift = Versions(iOS: "13.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil)
        let merged = Indexer.maxMergePlatformVersions(nil, packageSwift)
        #expect(merged?.versions.iOS == "13.0")
        #expect(merged?.versions.macOS == "10.15")
        #expect(merged?.aggregatedContributed == false)
    }

    @Test("MAX-merge: both nil returns nil")
    func bothNilReturnsNil() {
        #expect(Indexer.maxMergePlatformVersions(nil, nil) == nil)
    }

    @Test("compareDottedVersions: missing components are 0")
    func dottedCompareMissingComponents() {
        #expect(Indexer.compareDottedVersions("14", "14.0") == 0)
        #expect(Indexer.compareDottedVersions("14.0.1", "14.0") > 0)
        #expect(Indexer.compareDottedVersions("13.5", "14") < 0)
    }

    @Test("platformVersionsFromDict + dictFromPlatformVersions round-trip")
    func dictRoundTrip() throws {
        let dict = ["iOS": "16.0", "macOS": "13.0", "visionOS": "1.0"]
        let versions = Indexer.platformVersionsFromDict(dict)
        #expect(versions?.iOS == "16.0")
        #expect(versions?.macOS == "13.0")
        #expect(versions?.tvOS == nil)
        #expect(versions?.visionOS == "1.0")
        let roundTrip = try Indexer.dictFromPlatformVersions(#require(versions))
        #expect(roundTrip == dict)
    }
}
