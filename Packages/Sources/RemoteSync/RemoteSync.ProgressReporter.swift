import Foundation

// MARK: - Progress Reporter

extension RemoteSync {
    /// Reports progress to terminal with animated updates
    // @unchecked Sendable per concurrency.md §24: class holds animation
    // state (lastUpdate, lineCount) mutated only on a single MainActor
    // queue from the RemoteSync.Indexer actor. Mutation isolation is
    // by-convention via the caller actor; @unchecked acknowledges that
    // the compiler cannot verify the convention.

    public final class ProgressReporter: @unchecked Sendable {
        private let display: AnimatedProgress
        private let output: TerminalOutput
        private let lock = NSLock()
        private var spinnerIndex = 0
        private let spinnerChars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        public init(
            display: AnimatedProgress = AnimatedProgress(),
            output: TerminalOutput = StandardTerminalOutput()
        ) {
            self.display = display
            self.output = output
        }

        /// Update progress display (single line, overwrites previous)
        public func update(_ progress: RemoteSync.Progress) {
            lock.lock()
            defer { lock.unlock() }

            // Get spinner character
            let spinner = spinnerChars[spinnerIndex % spinnerChars.count]
            spinnerIndex += 1

            // Clear current line and write new progress
            let rendered = display.render(progress)
            let outputStr = "\r\u{1B}[K\(spinner) \(rendered)"
            FileHandle.standardOutput.write(Data(outputStr.utf8))
        }

        /// Print final summary
        public func finish(message: String) {
            lock.lock()
            defer { lock.unlock() }

            // Move to new line after progress
            print("")
            if !message.isEmpty {
                output.write(message)
            }
        }
    }
}
