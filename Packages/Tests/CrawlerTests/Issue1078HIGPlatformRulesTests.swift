import Foundation
import HIGPlatformInferencePass
import Testing

// MARK: - #1078 — HIGPlatformRules single source of truth

//
// `HIGPlatformRules` consolidates the (URL substring → applicable
// platforms) table previously duplicated across three consumers:
//
//   1. `Crawler.HIG.inferPlatforms(forURL:)` — frontmatter + body
//      output in `.md` files.
//   2. `Search.Strategies.HIG` — `overrideMin<Platform>` at index
//      time (pre-#1078 stamped universal baseline regardless of
//      topic).
//   3. `Search.Index.applyHIGPlatformInference` — SQL backfill of
//      legacy indexes.
//
// This suite pins the table's correctness and the consumer-facing
// `applicablePlatforms(for:)` + `minimumVersions(for:)` helpers.

@Suite("#1078 — HIGPlatformRules: shared HIG platform inference")
struct Issue1078HIGPlatformRulesTests {
    @Test("designing-for-watchos URL → only watchOS applicable")
    func watchOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-watchos")
        #expect(keep == ["watchos"])
    }

    @Test("watch-faces URL → only watchOS")
    func watchFaces() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/watch-faces")
        #expect(keep == ["watchos"])
    }

    @Test("designing-for-tvos URL → only tvOS")
    func tvOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-tvos")
        #expect(keep == ["tvos"])
    }

    @Test("designing-for-visionos URL → only visionOS")
    func visionOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-visionos")
        #expect(keep == ["visionos"])
    }

    @Test("spatial-layout URL → only visionOS")
    func spatialLayout() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/spatial-layout")
        #expect(keep == ["visionos"])
    }

    @Test("designing-for-macos URL → only macOS")
    func macOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-macos")
        #expect(keep == ["macos"])
    }

    @Test("mac-catalyst URL → both iOS and macOS")
    func macCatalyst() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/mac-catalyst")
        #expect(keep == ["ios", "macos"])
    }

    @Test("carplay URL → only iOS")
    func carPlay() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://carplay/audio-app")
        #expect(keep == ["ios"])
    }

    @Test("designing-for-ipados URL → only iOS (iPadOS is iOS flavor)")
    func iPadOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-ipados")
        #expect(keep == ["ios"])
    }

    @Test("designing-for-ios URL → only iOS")
    func iOS() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/designing-for-ios")
        #expect(keep == ["ios"])
    }

    @Test("Cross-platform topic (no rule match) → all five platforms")
    func crossPlatform() {
        let keep = HIGPlatformRules.applicablePlatforms(for: "hig://general/buttons")
        #expect(keep == Set(HIGPlatformRules.allPlatforms))
    }

    @Test("minimumVersions: platform-specific topic gets only the kept platform's baseline")
    func minimumVersionsWatchOSOnly() {
        let versions = HIGPlatformRules.minimumVersions(for: "hig://general/designing-for-watchos")
        #expect(versions.iOS == nil)
        #expect(versions.macOS == nil)
        #expect(versions.tvOS == nil)
        #expect(versions.watchOS == "2.0")
        #expect(versions.visionOS == nil)
    }

    @Test("minimumVersions: cross-platform topic gets all five baselines populated")
    func minimumVersionsAllPopulated() {
        let versions = HIGPlatformRules.minimumVersions(for: "hig://general/buttons")
        #expect(versions.iOS == "2.0")
        #expect(versions.macOS == "10.0")
        #expect(versions.tvOS == "9.0")
        #expect(versions.watchOS == "2.0")
        #expect(versions.visionOS == "1.0")
    }

    @Test("Rule table covers exactly the 10 known platform-specific URL substrings")
    func ruleTableShape() {
        let substrings = Set(HIGPlatformRules.rules.map(\.urlSubstring))
        #expect(substrings == [
            "designing-for-watchos",
            "watch-faces",
            "designing-for-tvos",
            "designing-for-visionos",
            "spatial-layout",
            "designing-for-macos",
            "mac-catalyst",
            "carplay",
            "designing-for-ipados",
            "designing-for-ios",
        ])
    }
}
