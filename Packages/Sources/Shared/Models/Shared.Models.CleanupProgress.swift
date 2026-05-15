import Foundation

// MARK: - Sample Code Cleanup Models

/// Progress update for sample code cleanup
extension Shared.Models {
    public struct CleanupProgress: Sendable {
        public let current: Int
        public let total: Int
        public let currentFile: String
        public let originalSize: Int64
        public let cleanedSize: Int64

        public var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(current) / Double(total) * 100.0
        }

        public init(
            current: Int,
            total: Int,
            currentFile: String,
            originalSize: Int64,
            cleanedSize: Int64
        ) {
            self.current = current
            self.total = total
            self.currentFile = currentFile
            self.originalSize = originalSize
            self.cleanedSize = cleanedSize
        }
    }
}

/// Statistics from sample code cleanup operation
extension Shared.Models {
    public struct CleanupStatistics: Sendable {
        public let totalArchives: Int
        public let cleanedArchives: Int
        public let skippedArchives: Int
        public let errors: Int
        public let originalTotalSize: Int64
        public let cleanedTotalSize: Int64
        public let totalItemsRemoved: Int
        public var duration: TimeInterval?

        public var spaceSaved: Int64 {
            originalTotalSize - cleanedTotalSize
        }

        public var spaceSavedPercentage: Double {
            guard originalTotalSize > 0 else { return 0 }
            return Double(spaceSaved) / Double(originalTotalSize) * 100.0
        }

        public init(
            totalArchives: Int,
            cleanedArchives: Int,
            skippedArchives: Int,
            errors: Int,
            originalTotalSize: Int64,
            cleanedTotalSize: Int64,
            totalItemsRemoved: Int = 0,
            duration: TimeInterval? = nil
        ) {
            self.totalArchives = totalArchives
            self.cleanedArchives = cleanedArchives
            self.skippedArchives = skippedArchives
            self.errors = errors
            self.originalTotalSize = originalTotalSize
            self.cleanedTotalSize = cleanedTotalSize
            self.totalItemsRemoved = totalItemsRemoved
            self.duration = duration
        }
    }
}

/// Result of cleaning a single archive
extension Shared.Models {
    public struct CleanupResult: Sendable {
        public let filename: String
        public let originalSize: Int64
        public let cleanedSize: Int64
        public let itemsRemoved: Int
        public let success: Bool
        public let errorMessage: String?

        public init(
            filename: String,
            originalSize: Int64,
            cleanedSize: Int64,
            itemsRemoved: Int,
            success: Bool,
            errorMessage: String? = nil
        ) {
            self.filename = filename
            self.originalSize = originalSize
            self.cleanedSize = cleanedSize
            self.itemsRemoved = itemsRemoved
            self.success = success
            self.errorMessage = errorMessage
        }
    }
}
