import ASTIndexer
import Foundation
import SearchModels

// MARK: - Sample @available aggregation

//
// #1111: aggregate per-file `@available(platform X.Y, ...)` attributes
// collected by `ASTIndexer.AvailabilityParsers.extractAvailability` (and
// already persisted in the per-sample sidecar's `fileAvailability`
// array) into a project-level `Search.PlatformVersions` stamp.
//
// Per-platform aggregation rule: MAX across all observed `@available`
// occurrences for that platform. A sample that touches APIs introduced
// in iOS 14 anywhere needs iOS 14 to compile, even if other lines only
// require iOS 11. Conservative-floor semantics that exclude false
// matches at the cost of occasionally overstating the floor for
// samples that use `if #available` guards purely for diagnostics.
//
// Lives in SampleIndexModels (foundation tier) alongside
// `SampleFrameworkAvailability` so the builder can consume it
// directly and tests can reach it without `import SampleIndex`.

public enum SampleAvailableAttributeAggregator {
    /// Aggregate a list of parsed `@available(...)` attributes into a
    /// per-platform MAX `Search.PlatformVersions`. Returns nil when
    /// no usable platform-version pair surfaces (e.g. the attributes
    /// only contain `*` / deprecation-only forms).
    public static func aggregate(
        attributes: [ASTIndexer.AvailabilityParsers.Attribute]
    ) -> Search.PlatformVersions? {
        var maxVersions: [String: SemanticVersion] = [:]
        for attribute in attributes {
            for occurrence in parseOccurrences(from: attribute.raw) {
                let key = canonicalPlatformKey(occurrence.platform)
                guard let key else { continue }
                if let current = maxVersions[key] {
                    if occurrence.version > current { maxVersions[key] = occurrence.version }
                } else {
                    maxVersions[key] = occurrence.version
                }
            }
        }
        if maxVersions.isEmpty { return nil }
        return Search.PlatformVersions(
            iOS: maxVersions["iOS"]?.formatted,
            macOS: maxVersions["macOS"]?.formatted,
            tvOS: maxVersions["tvOS"]?.formatted,
            watchOS: maxVersions["watchOS"]?.formatted,
            visionOS: maxVersions["visionOS"]?.formatted
        )
    }

    // MARK: - Internal parsing seam (testable)

    struct Occurrence: Equatable {
        let platform: String
        let version: SemanticVersion
    }

    /// Tuples `(platform, version)` parsed from a raw `@available(...)`
    /// payload (the text between the outer parens, e.g.
    /// `"(iOS 14.0, macOS 11.0, *)"`). Handles both Swift `@available`
    /// grammars:
    ///
    /// 1. **Shorthand** (multi-platform): `(iOS 14.0, macOS 11.0, *)`.
    ///    Each comma-separated chunk is one `<platform> <version>`
    ///    pair plus a trailing `*`.
    /// 2. **Labeled** (single-platform):
    ///    `(iOS, introduced: 14.0, deprecated: 17.0, message: "...")`.
    ///    One platform identifier followed by named labels. Only
    ///    `introduced:` yields an introduction-floor occurrence;
    ///    `deprecated:` / `obsoleted:` / `message:` / `renamed:` are
    ///    not introduction signals.
    ///
    /// Skips `*`, `unavailable`, and non-version labels. Tolerates
    /// extra whitespace and version numbers like `14`, `14.0`,
    /// `14.0.1`.
    static func parseOccurrences(from raw: String) -> [Occurrence] {
        // Strip outer parens if present so a caller can pass either
        // `(iOS 14.0, ...)` or `iOS 14.0, ...`. The sidecar emits the
        // parens form.
        var payload = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.hasPrefix("("), payload.hasSuffix(")") {
            payload = String(payload.dropFirst().dropLast())
        }

        let chunks = payload
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Detect labeled form by the presence of any colon-labeled
        // chunk; the labeled grammar binds to a SINGLE platform per
        // attribute, with introduction/deprecation/etc. as siblings.
        if chunks.contains(where: { isLabeledArgument($0) }) {
            guard
                let platform = chunks.first(where: { isBarePlatformIdentifier($0) }),
                let introducedVersion = chunks.lazy
                .compactMap({ introducedVersion(from: $0) })
                .first
            else {
                return []
            }
            return [Occurrence(platform: platform, version: introducedVersion)]
        }

        // Shorthand grammar: each chunk is one `<platform> <version>`
        // pair, plus a trailing `*`.
        var results: [Occurrence] = []
        for chunk in chunks {
            guard let occurrence = parseShorthandChunk(chunk) else { continue }
            results.append(occurrence)
        }
        return results
    }

    /// True iff the chunk contains a `<label>:` token (introduced:,
    /// deprecated:, obsoleted:, message:, renamed:), regardless of
    /// what follows. Pure shape probe; the actual label semantics live
    /// in `introducedVersion(from:)`.
    private static func isLabeledArgument(_ chunk: String) -> Bool {
        chunk.contains(":")
    }

    /// True iff the chunk is a bare platform identifier (no digits,
    /// no labels, not `*`, not `unavailable`). Used only on the
    /// labeled-grammar path.
    private static func isBarePlatformIdentifier(_ chunk: String) -> Bool {
        guard !chunk.isEmpty, chunk != "*" else { return false }
        if chunk.caseInsensitiveCompare("unavailable") == .orderedSame { return false }
        if chunk.contains(":") { return false }
        for scalar in chunk.unicodeScalars where scalar.isASCIIDigit {
            return false
        }
        return true
    }

    /// If the chunk is an `introduced: X.Y` label, return the parsed
    /// version; otherwise nil. `deprecated:` / `obsoleted:` /
    /// `message:` / `renamed:` are deliberately not introduction
    /// signals; they would lower the floor incorrectly.
    private static func introducedVersion(from chunk: String) -> SemanticVersion? {
        guard let colonIdx = chunk.firstIndex(of: ":") else { return nil }
        let label = chunk[..<colonIdx]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard label == "introduced" else { return nil }
        let versionPart = chunk[chunk.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SemanticVersion(versionPart)
    }

    /// Shorthand grammar parser: `"iOS 14.0"` → (iOS, 14.0). Tolerates
    /// `"iOS14.0"` (no space). Returns nil for `*`, `unavailable`, or
    /// chunks that don't fit the shape.
    private static func parseShorthandChunk(_ chunk: String) -> Occurrence? {
        guard !chunk.isEmpty else { return nil }
        if chunk == "*" { return nil }
        if chunk.caseInsensitiveCompare("unavailable") == .orderedSame { return nil }

        // The chunk is "<platform>[<sep>]<version>" where sep is one or
        // more whitespace chars or, in malformed forms, none. Find the
        // boundary where the platform identifier ends and the version
        // digits begin.
        let scalars = Array(chunk.unicodeScalars)
        var boundary = scalars.endIndex
        for (idx, scalar) in scalars.enumerated() where scalar.isASCIIDigit {
            boundary = idx
            break
        }
        guard boundary > 0, boundary < scalars.endIndex else { return nil }

        let platformRaw = String(
            String.UnicodeScalarView(scalars[..<boundary])
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let versionRaw = String(
            String.UnicodeScalarView(scalars[boundary...])
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platformRaw.isEmpty, !versionRaw.isEmpty else { return nil }
        guard let version = SemanticVersion(versionRaw) else { return nil }
        return Occurrence(platform: platformRaw, version: version)
    }

    /// Normalise the platform spelling Apple's `@available` accepts to
    /// the five canonical keys the projects table uses. Returns nil
    /// for anything that doesn't map (Swift / OpenBSD / catalyst-only
    /// flavours we don't track in the schema).
    static func canonicalPlatformKey(_ platform: String) -> String? {
        let lower = platform.lowercased()
        // ApplicationExtension suffix is the same SDK floor as the
        // parent platform; collapse before matching.
        let stripped = lower
            .replacingOccurrences(of: "applicationextension", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch stripped {
        case "ios", "iphoneos", "ipados": return "iOS"
        case "macos", "macosx", "osx", "mac": return "macOS"
        case "tvos": return "tvOS"
        case "watchos": return "watchOS"
        case "visionos", "xros": return "visionOS"
        case "maccatalyst", "catalyst":
            // Mac Catalyst is iOS-source-compatible; surface as iOS
            // for the projects-table stamp.
            return "iOS"
        default: return nil
        }
    }

    // MARK: - Semantic version (internal)

    /// Numeric major.minor.patch comparator. Internal because the only
    /// caller is the aggregator; lifting it would bloat the public
    /// surface for a tiny utility.
    struct SemanticVersion: Comparable, Equatable {
        let components: [Int]
        /// Always emit at least major.minor (`14` becomes `"14.0"`),
        /// matching the storage shape the sample-swift and
        /// sample-framework-inferred tiers use. Pre-fix this echoed
        /// the input shape verbatim, so `@available(iOS 14, *)`
        /// landed `"14"` while every other tier stored `"14.0"`:
        /// same logical version, two distinct column values.
        var formatted: String {
            let padded = components.count >= 2
                ? components
                : components + Array(repeating: 0, count: 2 - components.count)
            return padded.map(String.init).joined(separator: ".")
        }

        init?(_ string: String) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: ".")
            var ints: [Int] = []
            for part in parts {
                guard let value = Int(part), value >= 0 else { return nil }
                ints.append(value)
            }
            guard !ints.isEmpty else { return nil }
            components = ints
        }

        static func <(lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            for idx in 0..<count {
                let left = idx < lhs.components.count ? lhs.components[idx] : 0
                let right = idx < rhs.components.count ? rhs.components[idx] : 0
                if left != right { return left < right }
            }
            return false
        }
    }
}

private extension Unicode.Scalar {
    var isASCIIDigit: Bool {
        value >= 0x30 && value <= 0x39
    }
}
