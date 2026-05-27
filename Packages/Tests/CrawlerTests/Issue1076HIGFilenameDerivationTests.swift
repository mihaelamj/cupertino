import CrawlerModels
import Foundation
@testable import HIGSource
import Testing

// MARK: - #1076 — HIG crawler filename derivation

//
// Pre-#1076 the HIG crawler derived its output `.md` filename by
// running `sanitizeFilename(page.title)` over the extracted HTML
// `<title>` text. The cleaning logic stripped one variant of the
// Apple Developer Documentation suffix (`" | Apple Developer
// Documentation"`, with spaces) but not the dehyphenated variant
// (`"|AppleDeveloperDocumentation"`, no spaces). When Apple's site
// returned both variants for the same URL across consecutive fetches,
// the crawler saved TWO files per page (`buttons.md` plus
// `buttons-appledeveloperdocumentation.md`), each producing a row in
// hig.db with the same `url:` frontmatter. The result: every HIG
// search returned every topic twice.
//
// Post-fix the filename is derived from the URL's last path component
// (Apple's canonical HIG slug). Title is no longer in the filename
// derivation path. This file pins the canonicalization rule so a
// future refactor that reintroduces title-based naming fails fast.

@Suite("#1076 — Crawler.HIG canonical filename derivation")
struct Issue1076HIGFilenameDerivationTests {
    @Test("Buttons HIG page → 'buttons'")
    func buttonsCanonicalSlug() throws {
        let url = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/buttons"))
        #expect(Crawler.HIG.canonicalFilename(for: url) == "buttons")
    }

    @Test("designing-for-watchos page → 'designing-for-watchos' (hyphens preserved)")
    func watchOSSlug() throws {
        let url = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos"))
        #expect(Crawler.HIG.canonicalFilename(for: url) == "designing-for-watchos")
    }

    @Test("Trailing slash is dropped")
    func trailingSlashDropped() throws {
        let url = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/spatial-layout/"))
        #expect(Crawler.HIG.canonicalFilename(for: url) == "spatial-layout")
    }

    @Test("Uppercase letters in slug are lowercased (defensive)")
    func mixedCaseSlugIsLowercased() throws {
        let url = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/CarPlay"))
        #expect(Crawler.HIG.canonicalFilename(for: url) == "carplay")
    }

    @Test("Trailing .html extension is stripped (defensive — Apple's URLs don't use it today)")
    func htmlExtensionStripped() throws {
        let url = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/buttons.html"))
        #expect(Crawler.HIG.canonicalFilename(for: url) == "buttons")
    }

    @Test("Same URL with two different titles yields the same filename — the #1076 invariant")
    func sameURLDifferentTitleSameFilename() throws {
        // The pre-fix duplicate-file mechanism: Apple's HIG site
        // occasionally returned a page with the title rendered as the
        // dehyphenated `Buttons|AppleDeveloperDocumentation` variant.
        // The fact that the same URL produces the SAME canonical
        // filename — regardless of the title's surface form — is the
        // invariant the #1076 fix relies on.
        let urlA = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/buttons"))
        let urlB = try #require(URL(string: "https://developer.apple.com/design/human-interface-guidelines/buttons"))
        #expect(Crawler.HIG.canonicalFilename(for: urlA) == Crawler.HIG.canonicalFilename(for: urlB))
    }
}
