import ASTIndexer
import Foundation
import SharedConstants

/// Per-sample availability sidecar JSON written next to each zip in
/// `~/.cupertino/sample-code/<projectId>.availability.json` by `cupertino
/// index` (#228 phase 1). Captures the `Package.swift` `platforms: [...]`
/// deployment targets (when present) and every `@available(...)` attribute
/// occurrence in the sample's `.swift` sources.
///
/// Mirror of #219's per-package `availability.json` shape — same field
/// names, same `Attribute` element type — so a future cross-corpus
/// consumer can decode both with one loader. samples.db schema isn't
/// extended in this phase; see the parent issue for phases 2+.
extension Sample.Index {
    public struct AvailabilitySidecar: Codable, Sendable, Equatable {
        public let version: String
        public let annotatedAt: Date
        public let projectId: String
        public let deploymentTargets: [String: String]
        public let fileAvailability: [FileEntry]
        public let stats: Stats

        public struct FileEntry: Codable, Sendable, Equatable {
            public let relpath: String
            public let attributes: [ASTIndexer.AvailabilityParsers.Attribute]

            public init(
                relpath: String,
                attributes: [ASTIndexer.AvailabilityParsers.Attribute]
            ) {
                self.relpath = relpath
                self.attributes = attributes
            }
        }

        public struct Stats: Codable, Sendable, Equatable {
            public let filesWithAvailability: Int
            public let totalAttributes: Int

            public init(filesWithAvailability: Int, totalAttributes: Int) {
                self.filesWithAvailability = filesWithAvailability
                self.totalAttributes = totalAttributes
            }
        }

        public init(
            version: String,
            annotatedAt: Date,
            projectId: String,
            deploymentTargets: [String: String],
            fileAvailability: [FileEntry],
            stats: Stats
        ) {
            self.version = version
            self.annotatedAt = annotatedAt
            self.projectId = projectId
            self.deploymentTargets = deploymentTargets
            self.fileAvailability = fileAvailability
            self.stats = stats
        }
    }
}
