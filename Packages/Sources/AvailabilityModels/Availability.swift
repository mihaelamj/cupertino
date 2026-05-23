import Foundation

/// Namespace for availability-related types. Pre-#905 this anchor
/// lived in the `Availability` producer target; #905 moves it here
/// (mirroring the `Search` / `Crawler` / `SampleIndex` Models-as-anchor
/// pattern) so the `AvailabilityFoundationNetworking` sibling target +
/// future Linux-side concrete can extend `Availability.*` without
/// reaching into the producer.
public enum Availability {
    // Namespace root, types defined in extensions across this target
    // (Models) + the Availability producer + the
    // AvailabilityFoundationNetworking concrete.
}
