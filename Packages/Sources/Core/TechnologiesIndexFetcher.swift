import Foundation
import Shared

// MARK: - Technologies Index Fetcher

/// Fetches all framework URLs from Apple's technology index (technologies.json)
/// Used to seed the crawler queue for complete framework coverage.
/// See: https://github.com/mihaelamj/cupertino/issues/160
public enum TechnologiesIndexFetcher {
    private static let indexURL = URL.knownGood(
        "https://developer.apple.com/tutorials/data/documentation/technologies.json"
    )

    /// Fetch all active framework root URLs from Apple's technology index
    public static func fetchFrameworkURLs() async throws -> [URL] {
        let (data, response) = try await URLSession.shared.data(from: indexURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw TechnologiesIndexError.fetchFailed
        }

        return try parseFrameworkURLs(from: data)
    }

    private static func parseFrameworkURLs(from data: Data) throws -> [URL] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["sections"] as? [[String: Any]]
        else {
            throw TechnologiesIndexError.invalidFormat
        }

        var urls: [URL] = []

        for section in sections {
            if let technologies = section["technologies"] as? [[String: Any]] {
                urls.append(contentsOf: extractURLs(from: technologies))
            }

            if let groups = section["groups"] as? [[String: Any]] {
                for group in groups {
                    if let technologies = group["technologies"] as? [[String: Any]] {
                        urls.append(contentsOf: extractURLs(from: technologies))
                    }
                }
            }
        }

        return urls
    }

    private static func extractURLs(from technologies: [[String: Any]]) -> [URL] {
        technologies.compactMap { tech -> URL? in
            guard let destination = tech["destination"] as? [String: Any],
                  let identifier = destination["identifier"] as? String,
                  let isActive = destination["isActive"] as? Bool,
                  isActive
            else {
                return nil
            }

            return convertIdentifierToURL(identifier)
        }
    }

    private static func convertIdentifierToURL(_ identifier: String) -> URL? {
        guard identifier.hasPrefix("doc://"),
              let range = identifier.range(of: "/documentation/")
        else {
            return nil
        }

        let path = String(identifier[range.lowerBound...]).lowercased()
        return URL(string: "https://developer.apple.com\(path)")
    }
}

// MARK: - Error Types

public enum TechnologiesIndexError: Error, LocalizedError {
    case fetchFailed
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case .fetchFailed: return "Failed to fetch technologies.json"
        case .invalidFormat: return "Invalid technologies.json format"
        }
    }
}
