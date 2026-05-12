import ASTIndexer
import Foundation
import SharedCore
import CoreProtocols

extension Core {
    /// Walks a downloaded package on disk and writes an `availability.json`
    /// alongside its `manifest.json`, capturing:
    ///
    /// - The package's `Package.swift` `platforms: [...]` block (deployment targets).
    /// - Every `@available(...)` attribute occurrence in `.swift` source under
    ///   `Sources/` and `Tests/`, with file path + line + the parsed platform list.
    ///
    /// Pure on-disk pass — no network. Idempotent: rewrites the JSON each call.
    /// Regex-based; multi-line `@available` attrs aren't recognised and the
    /// scanner doesn't associate hits with specific declarations (would need
    /// AST). Good enough for first-cut ranking signals per #219; an AST upgrade
    /// is a follow-up that can extend `ASTIndexer.SwiftSourceExtractor`.
    public actor PackageAvailabilityAnnotator {
        public init() {}

        public static let outputFilename = "availability.json"

        public struct AnnotationResult: Codable, Sendable, Equatable {
            public let version: String
            public let annotatedAt: Date
            public let deploymentTargets: [String: String]
            public let fileAvailability: [FileAvailability]
            public let stats: Stats

            public struct Stats: Codable, Sendable, Equatable {
                public let filesScanned: Int
                public let filesWithAvailability: Int
                public let totalAttributes: Int
            }
        }

        public struct FileAvailability: Codable, Sendable, Equatable {
            public let relpath: String
            public let attributes: [Attribute]
        }

        /// Re-exported under the original public name for source/binary
        /// stability after the parser helpers moved to ASTIndexer (#228).
        public typealias Attribute = ASTIndexer.AvailabilityParsers.Attribute

        public enum AnnotationError: Error, Sendable, Equatable {
            case missingPackageDirectory(URL)
            case writeFailed(String)
        }

        @discardableResult
        public func annotate(packageDirectory: URL) async throws -> AnnotationResult {
            let manager = FileManager.default
            // Resolve symlinks so /var ↔ /private/var on macOS doesn't trip
            // the relpath stripping below when callers pass a non-resolved
            // URL (e.g. test temp dirs).
            let resolvedDir = packageDirectory.resolvingSymlinksInPath()
            guard manager.fileExists(atPath: resolvedDir.path) else {
                throw AnnotationError.missingPackageDirectory(packageDirectory)
            }

            let packageSwiftURL = resolvedDir.appendingPathComponent("Package.swift")
            let deploymentTargets: [String: String]
            if let manifest = try? String(contentsOf: packageSwiftURL, encoding: .utf8) {
                deploymentTargets = Self.parsePlatforms(from: manifest)
            } else {
                deploymentTargets = [:]
            }

            var fileAvailability: [FileAvailability] = []
            var filesScanned = 0
            var totalAttrs = 0

            let basePath = resolvedDir.path
            for subdir in ["Sources", "Tests"] {
                let root = resolvedDir.appendingPathComponent(subdir)
                guard manager.fileExists(atPath: root.path) else { continue }
                let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil)
                while let next = enumerator?.nextObject() as? URL {
                    guard next.pathExtension == "swift" else { continue }
                    filesScanned += 1
                    guard let source = try? String(contentsOf: next, encoding: .utf8) else { continue }
                    let attrs = Self.extractAvailability(from: source)
                    if !attrs.isEmpty {
                        let resolvedFile = next.resolvingSymlinksInPath().path
                        let relpath: String
                        if resolvedFile.hasPrefix(basePath + "/") {
                            relpath = String(resolvedFile.dropFirst(basePath.count + 1))
                        } else {
                            relpath = resolvedFile
                        }
                        fileAvailability.append(FileAvailability(relpath: relpath, attributes: attrs))
                        totalAttrs += attrs.count
                    }
                }
            }

            // Stable sort by relpath so re-runs produce byte-identical output
            // when the corpus is unchanged.
            fileAvailability.sort { $0.relpath < $1.relpath }

            let result = AnnotationResult(
                version: "1.0",
                annotatedAt: Date(),
                deploymentTargets: deploymentTargets,
                fileAvailability: fileAvailability,
                stats: AnnotationResult.Stats(
                    filesScanned: filesScanned,
                    filesWithAvailability: fileAvailability.count,
                    totalAttributes: totalAttrs
                )
            )

            let outputURL = packageDirectory.appendingPathComponent(Self.outputFilename)
            try Self.write(result, to: outputURL)
            return result
        }

        // MARK: - Parsers (delegated to ASTIndexer.AvailabilityParsers, #228)

        /// Forwarder kept for source compatibility with #219 callers.
        /// Real implementation lives in `ASTIndexer.AvailabilityParsers`
        /// so SampleIndex (#228) can reuse without depending on Core.
        public static func parsePlatforms(from packageSwift: String) -> [String: String] {
            ASTIndexer.AvailabilityParsers.parsePlatforms(from: packageSwift)
        }

        public static func extractAvailability(from source: String) -> [Attribute] {
            ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        }

        // MARK: - Persistence

        /// Encode `result` and atomically write to `url`. `internal static`
        /// rather than instance-method-on-actor so tests can drive it
        /// without an actor hop.
        static func write(_ result: AnnotationResult, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(result)
                try data.write(to: url, options: [.atomic])
            } catch {
                throw AnnotationError.writeFailed(error.localizedDescription)
            }
        }
    }
}
