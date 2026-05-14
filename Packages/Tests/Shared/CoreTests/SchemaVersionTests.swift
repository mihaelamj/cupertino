import Foundation
import SharedConstants
import SharedUtils
import Testing

@Suite("Shared.Utils.SchemaVersion (#234)")
struct SchemaVersionTests {
    @Test("make produces fixed-width 12-character string")
    func makeFixedWidth() {
        let version = Shared.Utils.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        )
        #expect(version == "202605042240")
        #expect(version.count == 12)
    }

    @Test("make zero-pads single-digit components")
    func makeZeroPads() {
        let version = Shared.Utils.SchemaVersion.make(
            year: 2026, month: 1, day: 9, hour: 7, minute: 3
        )
        #expect(version == "202601090703")
        #expect(version.count == 12)
    }

    @Test("now produces a 12-character string")
    func nowIsFixedWidth() {
        let value = Shared.Utils.SchemaVersion.now()
        #expect(value.count == 12)
        #expect(value.allSatisfy { $0.isASCII && $0.isHexDigit }) // all 0-9
    }

    @Test("now matches the supplied date in UTC")
    func nowAtSpecificDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        )))
        #expect(Shared.Utils.SchemaVersion.now(date: date) == "202605042240")
    }

    @Test("components inverts make for valid input")
    func componentsRoundTrip() {
        let parts = Shared.Utils.SchemaVersion.components(from: "202605042240")
        #expect(parts?.year == 2026)
        #expect(parts?.month == 5)
        #expect(parts?.day == 4)
        #expect(parts?.hour == 22)
        #expect(parts?.minute == 40)
    }

    @Test("components rejects non-12-char strings")
    func componentsRejectsShort() {
        #expect(Shared.Utils.SchemaVersion.components(from: "20260504") == nil)
        #expect(Shared.Utils.SchemaVersion.components(from: "2026050422401") == nil)
        #expect(Shared.Utils.SchemaVersion.components(from: "") == nil)
    }

    @Test("components rejects non-canonical month/day/hour/minute")
    func componentsRejectsOutOfRange() {
        #expect(Shared.Utils.SchemaVersion.components(from: "202613042240") == nil) // month 13
        #expect(Shared.Utils.SchemaVersion.components(from: "202605322240") == nil) // day 32
        #expect(Shared.Utils.SchemaVersion.components(from: "202605042440") == nil) // hour 24
        #expect(Shared.Utils.SchemaVersion.components(from: "202605042260") == nil) // minute 60
    }

    @Test("components rejects pre-1970 year")
    func componentsRejectsAncient() {
        #expect(Shared.Utils.SchemaVersion.components(from: "196905042240") == nil)
    }

    @Test("dateOnlyInt32 returns YYYYMMDD only")
    func dateOnlyInt32Works() {
        #expect(Shared.Utils.SchemaVersion.dateOnlyInt32(from: "202605042240") == 20260504)
    }

    @Test("dateOnlyInt32 returns 0 for invalid input")
    func dateOnlyInt32Invalid() {
        #expect(Shared.Utils.SchemaVersion.dateOnlyInt32(from: "garbage") == 0)
    }

    @Test("iso8601Now produces a Z-suffixed UTC timestamp")
    func iso8601NowFormat() {
        let value = Shared.Utils.SchemaVersion.iso8601Now()
        #expect(value.hasSuffix("Z"))
        #expect(value.contains("T"))
    }

    @Test("Two versions are lex-comparable in chronological order")
    func lexOrderingMatchesChronology() {
        let earlier = Shared.Utils.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        )
        let later = Shared.Utils.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 41
        )
        #expect(earlier < later)
    }
}

// MARK: - Shared.Utils.FTSQuery (#238)

@Suite("Shared.Utils.FTSQuery (#238)")
struct FTSQueryTests {
    @Test("Stopwords removed, remaining tokens OR-joined")
    func stopwordsAndOR() {
        let query = Shared.Utils.FTSQuery.build(question: "how do I animate a swiftui list")
        // After stopword strip: animate, swiftui, list
        #expect(query.contains("\"animate\""))
        #expect(query.contains("\"swiftui\""))
        #expect(query.contains("\"list\""))
        #expect(query.contains(" OR "))
        // Stopwords gone
        #expect(!query.contains("\"how\""))
        #expect(!query.contains("\"do\""))
        #expect(!query.contains("\"i\""))
        #expect(!query.contains("\"a\""))
    }

    @Test("Empty / stopword-only question yields empty FTS string")
    func emptyAndOnlyStopwords() {
        #expect(Shared.Utils.FTSQuery.build(question: "") == "")
        #expect(Shared.Utils.FTSQuery.build(question: "   ") == "")
        #expect(Shared.Utils.FTSQuery.build(question: "how do I a the") == "")
    }

    @Test("Dotted identifiers survive tokenization")
    func dottedIdentifiers() {
        let tokens = Shared.Utils.FTSQuery.tokens(from: "swift-nio.EventLoop foo")
        // Dash splits, dots within preserved
        #expect(tokens.contains("nio.EventLoop") || tokens.contains("EventLoop"))
        #expect(tokens.contains("swift"))
        #expect(tokens.contains("foo"))
    }

    @Test("Single-character tokens dropped")
    func dropsSingleChars() {
        let tokens = Shared.Utils.FTSQuery.tokens(from: "a x foo")
        #expect(!tokens.contains("a"))
        #expect(!tokens.contains("x"))
        #expect(tokens.contains("foo"))
    }
}
