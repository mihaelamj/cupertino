import Foundation
import SampleIndex
import Search
import SharedConstants
import SharedCore

// MARK: - Sample candidate fetcher (#230)

/// Adapter that bridges `Sample.Search.Service` into the
/// `Search.SmartQuery` fan-out used by `cupertino ask`.
///
/// Wraps `Sample.Search.Service.search(text:limit:)` and emits one
/// `Search.SmartCandidate` per matched file, scored on the file's
/// FTS rank. Project-level matches are ignored at this layer — file
/// chunks already cite their owning project through the metadata
/// dictionary, and project rows would otherwise duplicate the
/// resulting view.
///
/// Lives in `Services` (not `Search`) because pulling samples into
/// `Search` would force a hard dep on `SampleIndex` for every consumer
/// that just wants the docs corpus. `Services` already imports both
/// `SampleIndex` and `Search`, so the fetcher slots in cleanly.
extension Sample.Services {
    public struct CandidateFetcher: Search.CandidateFetcher {
        public let sourceName: String = Shared.Constants.SourcePrefix.samples

        private let service: Sample.Search.Service
        private let availability: Search.PackageQuery.AvailabilityFilter?

        public init(
            service: Sample.Search.Service,
            availability: Search.PackageQuery.AvailabilityFilter? = nil
        ) {
            self.service = service
            self.availability = availability
        }

        public func fetch(question: String, limit: Int) async throws -> [Search.SmartCandidate] {
            let query = Sample.Search.Query(
                text: question,
                limit: limit,
                platform: availability?.platform,
                minVersion: availability?.minVersion
            )
            let result = try await service.search(query)

            var candidates: [Search.SmartCandidate] = []

            // #238 follow-up: include project-level matches too. A natural-
            // language query like "swiftui list animation" frequently scores
            // a project's title/description/README without lighting up any
            // single file's content via FTS5. Emitting only file matches
            // dropped those projects entirely. Now both flow into RRF;
            // SmartResult dedupe still collapses obvious duplicates.
            for (idx, project) in result.projects.enumerated() {
                // Project rows lack their own bm25 score; rank by ordinal
                // (sample of arrival from the FTS query, best-first).
                let pseudoScore = 1.0 / Double(idx + 1)
                let chunk = project.readme.flatMap { readme -> String? in
                    let lines = readme.split(separator: "\n", omittingEmptySubsequences: false).prefix(20)
                    return lines.isEmpty ? nil : lines.joined(separator: "\n")
                } ?? project.description
                candidates.append(Search.SmartCandidate(
                    source: sourceName,
                    identifier: project.id,
                    title: project.title,
                    chunk: chunk,
                    rawScore: pseudoScore,
                    kind: "sampleProject",
                    metadata: [
                        "projectId": project.id,
                        "frameworks": project.frameworks.joined(separator: ","),
                        "rank": String(idx + 1),
                    ]
                ))
            }

            // File-level matches — same shape as before.
            for (idx, file) in result.files.enumerated() {
                // Higher rawScore = better. samples.db FTS5 returns its
                // native BM25 score (lower = better). Invert sign to match
                // the convention used by every other fetcher in the
                // SmartQuery fan-out so reciprocal-rank-fusion sees
                // comparable scales.
                let rawScore = -file.rank
                candidates.append(Search.SmartCandidate(
                    source: sourceName,
                    identifier: "\(file.projectId)/\(file.path)",
                    title: file.filename.isEmpty ? file.path : file.filename,
                    chunk: file.snippet,
                    rawScore: rawScore,
                    kind: nil,
                    metadata: [
                        "projectId": file.projectId,
                        "path": file.path,
                        "rank": String(idx + 1),
                    ]
                ))
            }

            return candidates
        }
    }
}
