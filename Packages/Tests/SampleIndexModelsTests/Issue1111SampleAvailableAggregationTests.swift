import ASTIndexer
import Foundation
@testable import SampleIndexModels
import SearchModels
import Testing

/// #1111: per-file `@available(...)` aggregation. The MAX-per-platform
/// rule treats the sample's source as the source of truth for the
/// deployment floor; `if #available` guards collapse into the same
/// MAX (conservative on purpose).
@Suite("#1111 SampleAvailableAttributeAggregator")
struct Issue1111SampleAvailableAggregationTests {
    private typealias Attribute = ASTIndexer.AvailabilityParsers.Attribute
    private typealias Aggregator = SampleAvailableAttributeAggregator

    @Test("Single-platform attr: iOS 14.0 stamps iOS only")
    func singlePlatform() {
        let attrs = [
            Attribute(line: 10, raw: "(iOS 14.0, *)", platforms: ["iOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "14.0")
        #expect(result?.macOS == nil)
        #expect(result?.tvOS == nil)
        #expect(result?.watchOS == nil)
        #expect(result?.visionOS == nil)
    }

    @Test("Multi-platform attr stamps each platform")
    func multiPlatform() {
        let attrs = [
            Attribute(
                line: 1,
                raw: "(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)",
                platforms: ["iOS", "macOS", "tvOS", "watchOS", "visionOS", "*"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "16.0")
        #expect(result?.macOS == "13.0")
        #expect(result?.tvOS == "16.0")
        #expect(result?.watchOS == "9.0")
        #expect(result?.visionOS == "1.0")
    }

    @Test("MAX rule: two iOS attrs (13.0 and 16.0) yields 16.0")
    func maxPerPlatform() {
        let attrs = [
            Attribute(line: 5, raw: "(iOS 13.0, *)", platforms: ["iOS", "*"]),
            Attribute(line: 50, raw: "(iOS 16.0, *)", platforms: ["iOS", "*"]),
            Attribute(line: 100, raw: "(iOS 11.0, *)", platforms: ["iOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "16.0")
    }

    @Test("Mixed platforms with overlapping versions: each platform tracks its own MAX")
    func multiPlatformMixedMax() {
        let attrs = [
            Attribute(line: 5, raw: "(iOS 14.0, macOS 11.0, *)", platforms: ["iOS", "macOS", "*"]),
            Attribute(line: 50, raw: "(iOS 16.0, macOS 12.0, *)", platforms: ["iOS", "macOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "16.0")
        #expect(result?.macOS == "12.0")
    }

    @Test("ApplicationExtension variants collapse to parent platform")
    func applicationExtensionNormalisation() {
        let attrs = [
            Attribute(
                line: 70,
                raw: "(iOSApplicationExtension 14.0, watchOSApplicationExtension 7.0, *)",
                platforms: ["iOSApplicationExtension", "watchOSApplicationExtension", "*"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "14.0")
        #expect(result?.watchOS == "7.0")
    }

    @Test("Mac Catalyst collapses to iOS")
    func macCatalystAsiOS() {
        let attrs = [
            Attribute(
                line: 5,
                raw: "(macCatalyst 14.0, *)",
                platforms: ["macCatalyst", "*"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "14.0")
    }

    @Test("visionOS aliases (xrOS) normalise to visionOS")
    func visionOSAliasNormalisation() {
        let attrs = [
            Attribute(line: 5, raw: "(xrOS 1.0, *)", platforms: ["xrOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.visionOS == "1.0")
    }

    @Test("Wildcard-only / unavailable / deprecated attrs return nil")
    func nonVersionAttrsReturnNil() {
        let attrs = [
            Attribute(line: 5, raw: "(*)", platforms: ["*"]),
            Attribute(line: 6, raw: "(*, deprecated: 17.0)", platforms: ["*"]),
            Attribute(line: 7, raw: "(*, unavailable)", platforms: ["*"]),
            Attribute(line: 8, raw: "(*, renamed: \"newName\")", platforms: ["*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result == nil)
    }

    @Test("Empty attribute list returns nil")
    func emptyAttrsReturnNil() {
        let result = Aggregator.aggregate(attributes: [])
        #expect(result == nil)
    }

    @Test("Patch-level versions are kept verbatim and ordered numerically")
    func patchLevelVersions() {
        let attrs = [
            Attribute(line: 1, raw: "(iOS 17.0, *)", platforms: ["iOS", "*"]),
            Attribute(line: 2, raw: "(iOS 17.0.1, *)", platforms: ["iOS", "*"]),
            Attribute(line: 3, raw: "(iOS 16.4, *)", platforms: ["iOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "17.0.1")
    }

    @Test("Major-only versions compare correctly against major.minor (and stamp \"14.0\")")
    func majorOnlyVersionsCompare() {
        let attrs = [
            Attribute(line: 1, raw: "(iOS 14, *)", platforms: ["iOS", "*"]),
            Attribute(line: 2, raw: "(iOS 13.5, *)", platforms: ["iOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        // `14` is logically greater than `13.5`; stored as padded "14.0"
        // for column-shape parity with the other availability tiers.
        #expect(result?.iOS == "14.0")
    }

    @Test("Unrecognised platform tokens (linux, OpenBSD) are silently ignored")
    func unrecognisedPlatformIgnored() {
        let attrs = [
            Attribute(line: 1, raw: "(Linux 5.0, *)", platforms: ["Linux", "*"]),
            Attribute(line: 2, raw: "(swift 5.5, *)", platforms: ["swift", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result == nil)
    }

    @Test("Labeled @available form: introduced: X.Y is parsed")
    func labeledIntroducedForm() {
        let attrs = [
            Attribute(
                line: 5,
                raw: "(iOS, introduced: 14.0, deprecated: 17.0)",
                platforms: ["iOS"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "14.0")
        #expect(result?.macOS == nil)
    }

    @Test("Labeled @available form: message + renamed labels don't lower the floor")
    func labeledWithMessageLabel() {
        let attrs = [
            Attribute(
                line: 5,
                raw: "(macOS, introduced: 11.0, message: \"use newAPI()\", renamed: \"newAPI\")",
                platforms: ["macOS"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.macOS == "11.0")
    }

    @Test("Labeled @available form: deprecated-only (no introduced) yields no occurrence")
    func labeledDeprecatedOnlyYieldsNothing() {
        let attrs = [
            Attribute(
                line: 5,
                raw: "(iOS, deprecated: 17.0, message: \"...\")",
                platforms: ["iOS"]
            ),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result == nil)
    }

    @Test("Padded version format: @available(iOS 14, *) stamps \"14.0\", not \"14\"")
    func paddedVersionFormat() {
        let attrs = [
            Attribute(line: 1, raw: "(iOS 14, *)", platforms: ["iOS", "*"]),
        ]
        let result = Aggregator.aggregate(attributes: attrs)
        #expect(result?.iOS == "14.0")
    }
}
