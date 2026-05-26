import AvailabilityModels
import Foundation

// MARK: - LiveAvailabilityNetworkingFactory (#905)

/// Composition-root-supplied factory that produces
/// `LiveAvailabilityNetworking` instances configured with the
/// caller's timeout + concurrency. The factory is the seam the
/// `Availability.Fetcher` actor consumes (via init injection); the
/// Availability producer target imports only AvailabilityModels, so
/// it sees the protocol but never the URLSession-backed concrete.
public struct LiveAvailabilityNetworkingFactory: Availability.NetworkingFactory {
    public init() {}

    public func make(timeout: TimeInterval, concurrency: Int) -> any Availability.Networking {
        LiveAvailabilityNetworking(timeout: timeout, concurrency: concurrency)
    }
}
