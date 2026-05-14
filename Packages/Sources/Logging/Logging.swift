import Foundation

// MARK: - Logging namespace anchor (concrete target)

/// Namespace anchor inside the concrete `Logging` SPM target. Hosts the
/// OSLog + console + file conformer (`Logging.LiveRecording`), plus the
/// legacy static surface (`Logging.Log`, `Logging.ConsoleLogger`,
/// `Logging.Unified`) that's being phased out by the GoF Strategy
/// migration to `Logging.Recording` (defined under the same-named
/// anchor in the sibling `LoggingModels` target).
///
/// Two anchors, one per module, lets either target extend `Logging.*`
/// without dragging the other in: consumers that need only the
/// protocol-typed seam import `LoggingModels` (foundation-only);
/// consumers that own the binary's logger composition root import
/// `Logging` for the production conformer.
public enum Logging {
    // Namespace root - types defined in extensions
}
