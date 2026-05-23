import Foundation

// MARK: - Availability.Networking (#905)

extension Availability {
    /// Network-fetch seam for `Availability.Fetcher` (#905). Foundation-
    /// only so this target stays in the strict-DI allow-list and the
    /// concrete URLSession-backed implementation can ship in a sibling
    /// SPM target (`AvailabilityFoundationNetworking`) that the binary
    /// composition root supplies.
    ///
    /// Pre-#905 `Availability.Fetcher` owned its own `URLSession` and
    /// imported `FoundationNetworking` directly. That coupled the
    /// `Availability` package to FoundationNetworking via the
    /// `#if canImport(FoundationNetworking)` shim, which works on Apple
    /// + Linux today but blocks the foundation-only lift-out trace
    /// from passing without the URLSession dep being present.
    ///
    /// Post-#905 the protocol takes a URL and returns `(Data, status)`
    /// where `status` is the integer HTTP status code (`0` for non-HTTP
    /// responses). The Foundation-only type surface deliberately does
    /// NOT expose `URLResponse` / `HTTPURLResponse`, both of which
    /// live in FoundationNetworking on Linux.
    public protocol Networking: Sendable {
        /// Fetch the URL and return the response body + HTTP status
        /// code. Returns `status == 0` if the response was not HTTP.
        /// Throws on transport errors (timeout, DNS, connection
        /// refused, etc.).
        func fetch(from url: URL) async throws -> (Data, Int)
    }
}
