import Foundation

// MARK: - Availability.NetworkingFactory (#905)

extension Availability {
    /// GoF Factory Method (Gamma 1994 p. 107) for `Availability.Networking`.
    /// The composition root (CLI) supplies a concrete factory; the
    /// `Availability.Fetcher` actor uses the factory to construct a
    /// per-instance `any Networking` configured with its `timeout` +
    /// `concurrency` settings.
    ///
    /// Why a factory instead of injecting `any Networking` directly:
    /// `Availability.Fetcher.Configuration` carries timeout +
    /// concurrency that the concrete URLSession needs at construction
    /// time. The Fetcher init reads its `Configuration`, then calls
    /// the factory to build a Networking with those settings. Without
    /// the factory we'd either freeze the URLSession configuration at
    /// CLI-composition-root time (loses the per-Fetcher knobs) or
    /// require every caller to construct the URLSession (loses the
    /// pluggability seam).
    public protocol NetworkingFactory: Sendable {
        /// Construct a Networking with the given timeout + concurrency.
        /// `timeout` is the per-request deadline in seconds;
        /// `concurrency` is the max concurrent connections per host.
        func make(timeout: TimeInterval, concurrency: Int) -> any Networking
    }
}
