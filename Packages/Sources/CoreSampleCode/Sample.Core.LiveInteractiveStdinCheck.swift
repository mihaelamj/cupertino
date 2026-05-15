import Foundation
import SharedConstants

// MARK: - Sample.Core.LiveInteractiveStdinCheck

extension Sample.Core {
    /// Production conformer for `Sample.Core.InteractiveStdinChecking`.
    /// Calls `isatty(fileno(stdin))`, exactly the behaviour the deleted
    /// `Sample.Core.Downloader.isInteractiveStdin()` static helper had
    /// before #547. Default value of the `interactiveStdinCheck:` init
    /// parameter on `Sample.Core.Downloader` so existing call sites
    /// stay source-compatible.
    public struct LiveInteractiveStdinCheck: InteractiveStdinChecking {
        public init() {}

        public func isInteractive() -> Bool {
            isatty(fileno(stdin)) != 0
        }
    }
}
