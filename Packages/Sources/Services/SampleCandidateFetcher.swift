import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Sample candidate fetcher (#230)

/// Adapter that bridges `SampleSearchService` into the
/// `Search.SmartQuery` fan-out used by `cupertino ask`.
///
/// Wraps `SampleSearchService.search(text:limit:)` and emits one
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
public struct SampleCandidateFetcher: Search.CandidateFetcher {
    public let sourceName: String = Shared.Constants.SourcePrefix.samples

    private let service: SampleSearchService
    private let availability: Search.PackageQuery.AvailabilityFilter?

    public init(
        service: SampleSearchService,
        availability: Search.PackageQuery.AvailabilityFilter? = nil
    ) {
        self.service = service
        self.availability = availability
    }

    public func fetch(question: String, limit: Int) async throws -> [Search.SmartCandidate] {
        let query = SampleQuery(
            text: question,
            limit: limit,
            platform: availability?.platform,
            minVersion: availability?.minVersion
        )
        let result = try await service.search(query)

        return result.files.enumerated().map { idx, file in
            // Higher rawScore = better. samples.db FTS5 returns its
            // native BM25 score (lower = better). Invert sign to match
            // the convention used by every other fetcher in the
            // SmartQuery fan-out so reciprocal-rank-fusion sees
            // comparable scales.
            let rawScore = -file.rank

            // FileSearchResult already carries an FTS5-extracted
            // snippet — no further chunking needed. Title is the
            // filename (lighter than the full relative path).
            return Search.SmartCandidate(
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
            )
        }
    }
}
