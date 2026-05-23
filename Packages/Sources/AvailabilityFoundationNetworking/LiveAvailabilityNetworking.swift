import AvailabilityModels
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - LiveAvailabilityNetworking (#905)

/// Concrete URLSession-backed witness for `Availability.Networking`.
/// Lives in this sibling SPM target so the `Availability` producer can
/// stay Foundation-only (no `import FoundationNetworking` shim).
///
/// Apple platforms: URLSession is in Foundation, the FoundationNetworking
/// canImport guard never fires.
/// Linux (future): FoundationNetworking provides URLSession; this is
/// the only file in the producer graph that has to know about that.
public struct LiveAvailabilityNetworking: Availability.Networking {
    private let session: URLSession

    public init(timeout: TimeInterval, concurrency: Int) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpMaximumConnectionsPerHost = concurrency
        session = URLSession(configuration: config)
    }

    public func fetch(from url: URL) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: url)
        // Per the protocol's documented contract, non-HTTP responses
        // surface as `status == 0` so callers can branch on a single
        // integer instead of unwrapping a FoundationNetworking-typed
        // response.
        guard let httpResponse = response as? HTTPURLResponse else {
            return (data, 0)
        }
        return (data, httpResponse.statusCode)
    }
}

// MARK: - Factory

public struct LiveAvailabilityNetworkingFactory: Availability.NetworkingFactory {
    public init() {}

    public func make(timeout: TimeInterval, concurrency: Int) -> any Availability.Networking {
        LiveAvailabilityNetworking(timeout: timeout, concurrency: concurrency)
    }
}
