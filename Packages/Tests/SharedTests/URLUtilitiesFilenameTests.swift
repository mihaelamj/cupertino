import Foundation
@testable import Shared
import Testing

// MARK: - URLUtilities.filename — long-name truncation tests

/// These cases reproduce the **exact errored URLs** from the v1.0 recrawl
/// on Claw Mini (2026-04-29 → 2026-04-30), which all failed with POSIX
/// errno 63 "File name too long" because the generated basename exceeded
/// the macOS 255-byte filesystem limit. The fix in `URLUtilities.filename`
/// caps the basename at 240 bytes (leaving room for `.json`) and appends
/// an 8-char SHA-1 hash for collision-resistant uniqueness.
@Suite("URLUtilities.filename — overlong slug truncation")
struct URLUtilitiesFilenameTests {
    /// Apple's per-component filename limit on HFS+/APFS.
    /// We must produce filenames whose `<name>.json` form fits within 255 bytes.
    private let macOSBasenameByteLimit = 255
    private let jsonExtensionBytes = ".json".utf8.count

    private func filenameWithExtension(for url: URL) -> String {
        URLUtilities.filename(from: url) + ".json"
    }

    // MARK: - Exact failing URLs from the 2026-04-30 error log

    /// `MPSSVGF.encodeReprojection(to:...)` 12-parameter overload — generated
    /// a 280+ byte filename pre-fix and failed POSIX 63.
    private static let mpssvgfReprojection12 = URL(
        string: "https://developer.apple.com/documentation/metalperformanceshaders/mpssvgf/encodereprojection"
            + "(to:sourcetexture:previoustexture:destinationtexture:previousluminancemomentstexture:"
            + "destinationluminancemomentstexture:previousframecount:destinationframecount:"
            + "motionvectortexture:depthnormaltexture:previousdepthnormaltex-3k6zp"
    )!

    /// `MPSSVGF.encodeReprojection(...)` 14-parameter stereo overload — also failed POSIX 63.
    private static let mpssvgfReprojection14 = URL(
        string: "https://developer.apple.com/documentation/metalperformanceshaders/mpssvgf/encodereprojection"
            + "(to:sourcetexture:previoustexture:destinationtexture:previousluminancemomentstexture:"
            + "destinationluminancemomentstexture:sourcetexture2:previoustexture2:destinationtexture2:"
            + "previousluminancemomentstexture2:destinationlumina-5nbfn"
    )!

    /// `MPSRayIntersector.encodeIntersection(commandBuffer:...)` 11-parameter overload — failed POSIX 63.
    private static let mpsRayIntersectorEncode = URL(
        string: "https://developer.apple.com/documentation/metalperformanceshaders/mpsrayintersector/"
            + "encodeintersection(commandbuffer:intersectiontype:raybuffer:raybufferoffset:rayindexbuffer:"
            + "rayindexbufferoffset:intersectionbuffer:intersectionbufferoffset:rayindexcount:accelerationstructure:)"
    )!

    @Test("Reprojection 12-param: filename + .json fits in 255 bytes")
    func mpssvgfReprojection12FitsLimit() {
        let name = filenameWithExtension(for: Self.mpssvgfReprojection12)
        #expect(
            name.utf8.count <= macOSBasenameByteLimit,
            "got \(name.utf8.count) bytes: \(name)"
        )
    }

    @Test("Reprojection 14-param: filename + .json fits in 255 bytes")
    func mpssvgfReprojection14FitsLimit() {
        let name = filenameWithExtension(for: Self.mpssvgfReprojection14)
        #expect(
            name.utf8.count <= macOSBasenameByteLimit,
            "got \(name.utf8.count) bytes: \(name)"
        )
    }

    @Test("MPSRayIntersector encodeIntersection: filename + .json fits in 255 bytes")
    func mpsRayIntersectorEncodeFitsLimit() {
        let name = filenameWithExtension(for: Self.mpsRayIntersectorEncode)
        #expect(
            name.utf8.count <= macOSBasenameByteLimit,
            "got \(name.utf8.count) bytes: \(name)"
        )
    }

    // MARK: - Truncated filenames preserve uniqueness

    @Test("Two near-identical overloads still produce different filenames")
    func nearIdenticalOverloadsAreUnique() {
        let firstName = URLUtilities.filename(from: Self.mpssvgfReprojection12)
        let secondName = URLUtilities.filename(from: Self.mpssvgfReprojection14)
        #expect(
            firstName != secondName,
            "filename collision between two distinct Apple URLs:\n  \(firstName)\n  \(secondName)"
        )
    }

    @Test("Different URLs always produce different filenames (no truncation collisions)")
    func differentURLsAreUnique() throws {
        let urls = try [
            Self.mpssvgfReprojection12,
            Self.mpssvgfReprojection14,
            Self.mpsRayIntersectorEncode,
            #require(URL(string: "https://developer.apple.com/documentation/swift/array")),
            #require(URL(string: "https://developer.apple.com/documentation/swiftui/view")),
        ]
        let names = urls.map(URLUtilities.filename)
        #expect(Set(names).count == names.count, "duplicate filenames: \(names)")
    }

    @Test("Same URL produces same filename (deterministic)")
    func filenameIsDeterministic() {
        let firstCall = URLUtilities.filename(from: Self.mpssvgfReprojection12)
        let secondCall = URLUtilities.filename(from: Self.mpssvgfReprojection12)
        #expect(firstCall == secondCall)
    }

    // MARK: - Truncation only triggers for over-long URLs

    @Test("Short URLs are not truncated and preserve their natural form")
    func shortURLsUntruncated() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swift/array"))
        let name = URLUtilities.filename(from: url)
        #expect(name == "documentation_swift_array")
    }

    @Test("Operator URLs at moderate length keep their hash disambiguator and are not double-suffixed")
    func operatorURLKeepsSingleHash() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swift/int/+(_:_:)"))
        let name = URLUtilities.filename(from: url)
        let underscoreCount = name.filter { $0 == "_" }.count
        #expect(name.contains("documentation_swift_int"))
        #expect(underscoreCount > 0)
        // Must not have two adjacent hash blocks (would indicate double-suffixing).
        #expect(!name.contains("__"))
    }

    // MARK: - Truncated filenames end on the hash, not on bare underscores

    @Test("Truncated filenames do not end on a trailing underscore before .json")
    func truncatedFilenameNoTrailingUnderscore() {
        let name = URLUtilities.filename(from: Self.mpssvgfReprojection12)
        // Should end with `_<8 hex chars>` — not `_` immediately before that.
        let parts = name.split(separator: "_")
        let last = parts.last.map(String.init) ?? ""
        #expect(last.count == 8, "expected 8-hex-char hash suffix, got: \(last)")
        let isAllHex = last.allSatisfy(\.isHexDigit)
        #expect(isAllHex, "hash suffix not all hex: \(last)")
    }

    @Test("Filename never returns empty string")
    func filenameNeverEmpty() throws {
        let name = try URLUtilities.filename(from: #require(URL(string: "https://developer.apple.com/")))
        #expect(!name.isEmpty)
    }
}
