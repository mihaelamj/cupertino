import Foundation
@testable import Shared
import Testing

@Suite("Shared.SchemaVersion (#234)")
struct SchemaVersionTests {
    @Test("make produces fixed-width 12-character string")
    func makeFixedWidth() {
        let version = Shared.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        )
        #expect(version == "202605042240")
        #expect(version.count == 12)
    }

    @Test("make zero-pads single-digit components")
    func makeZeroPads() {
        let version = Shared.SchemaVersion.make(
            year: 2026, month: 1, day: 9, hour: 7, minute: 3
        )
        #expect(version == "202601090703")
        #expect(version.count == 12)
    }

    @Test("now produces a 12-character string")
    func nowIsFixedWidth() {
        let value = Shared.SchemaVersion.now()
        #expect(value.count == 12)
        #expect(value.allSatisfy { $0.isASCII && $0.isHexDigit }) // all 0-9
    }

    @Test("now matches the supplied date in UTC")
    func nowAtSpecificDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        ))!
        #expect(Shared.SchemaVersion.now(date: date) == "202605042240")
    }

    @Test("components inverts make for valid input")
    func componentsRoundTrip() {
        let parts = Shared.SchemaVersion.components(from: "202605042240")
        #expect(parts?.year == 2026)
        #expect(parts?.month == 5)
        #expect(parts?.day == 4)
        #expect(parts?.hour == 22)
        #expect(parts?.minute == 40)
    }

    @Test("components rejects non-12-char strings")
    func componentsRejectsShort() {
        #expect(Shared.SchemaVersion.components(from: "20260504") == nil)
        #expect(Shared.SchemaVersion.components(from: "2026050422401") == nil)
        #expect(Shared.SchemaVersion.components(from: "") == nil)
    }

    @Test("components rejects non-canonical month/day/hour/minute")
    func componentsRejectsOutOfRange() {
        #expect(Shared.SchemaVersion.components(from: "202613042240") == nil) // month 13
        #expect(Shared.SchemaVersion.components(from: "202605322240") == nil) // day 32
        #expect(Shared.SchemaVersion.components(from: "202605042440") == nil) // hour 24
        #expect(Shared.SchemaVersion.components(from: "202605042260") == nil) // minute 60
    }

    @Test("components rejects pre-1970 year")
    func componentsRejectsAncient() {
        #expect(Shared.SchemaVersion.components(from: "196905042240") == nil)
    }

    @Test("dateOnlyInt32 returns YYYYMMDD only")
    func dateOnlyInt32Works() {
        #expect(Shared.SchemaVersion.dateOnlyInt32(from: "202605042240") == 20260504)
    }

    @Test("dateOnlyInt32 returns 0 for invalid input")
    func dateOnlyInt32Invalid() {
        #expect(Shared.SchemaVersion.dateOnlyInt32(from: "garbage") == 0)
    }

    @Test("iso8601Now produces a Z-suffixed UTC timestamp")
    func iso8601NowFormat() {
        let value = Shared.SchemaVersion.iso8601Now()
        #expect(value.hasSuffix("Z"))
        #expect(value.contains("T"))
    }

    @Test("Two versions are lex-comparable in chronological order")
    func lexOrderingMatchesChronology() {
        let earlier = Shared.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 40
        )
        let later = Shared.SchemaVersion.make(
            year: 2026, month: 5, day: 4, hour: 22, minute: 41
        )
        #expect(earlier < later)
    }
}
