@testable import Cleanup
import Foundation
@testable import Shared
import Testing
import TestSupport

// MARK: - SampleCodeCleaner Tests

@Test("CleanupProgress percentage calculation")
func cleanupProgressPercentage() throws {
    let progress = CleanupProgress(
        current: 50,
        total: 100,
        currentFile: "test.zip",
        originalSize: 1000,
        cleanedSize: 500
    )

    #expect(progress.percentage == 50.0)
    print("   ✅ Progress percentage calculated correctly")
}

@Test("CleanupProgress handles zero total")
func cleanupProgressZeroTotal() throws {
    let progress = CleanupProgress(
        current: 0,
        total: 0,
        currentFile: "test.zip",
        originalSize: 0,
        cleanedSize: 0
    )

    #expect(progress.percentage == 0)
    print("   ✅ Zero total handled correctly")
}

@Test("CleanupStatistics space saved calculation")
func cleanupStatisticsSpaceSaved() throws {
    let stats = CleanupStatistics(
        totalArchives: 10,
        cleanedArchives: 8,
        skippedArchives: 2,
        errors: 0,
        originalTotalSize: 1000,
        cleanedTotalSize: 300
    )

    #expect(stats.spaceSaved == 700)
    #expect(stats.spaceSavedPercentage == 70.0)
    print("   ✅ Space saved calculated correctly")
}

@Test("CleanupStatistics handles zero original size")
func cleanupStatisticsZeroSize() throws {
    let stats = CleanupStatistics(
        totalArchives: 0,
        cleanedArchives: 0,
        skippedArchives: 0,
        errors: 0,
        originalTotalSize: 0,
        cleanedTotalSize: 0
    )

    #expect(stats.spaceSaved == 0)
    #expect(stats.spaceSavedPercentage == 0)
    print("   ✅ Zero size handled correctly")
}

@Test("CleanupResult initialization")
func cleanupResultInit() throws {
    let result = CleanupResult(
        filename: "test.zip",
        originalSize: 1000,
        cleanedSize: 500,
        itemsRemoved: 5,
        success: true
    )

    #expect(result.filename == "test.zip")
    #expect(result.originalSize == 1000)
    #expect(result.cleanedSize == 500)
    #expect(result.itemsRemoved == 5)
    #expect(result.success)
    #expect(result.errorMessage == nil)
    print("   ✅ CleanupResult initialized correctly")
}

@Test("CleanupResult with error")
func cleanupResultWithError() throws {
    let result = CleanupResult(
        filename: "test.zip",
        originalSize: 1000,
        cleanedSize: 1000,
        itemsRemoved: 0,
        success: false,
        errorMessage: "Failed to extract archive"
    )

    #expect(!result.success)
    #expect(result.errorMessage == "Failed to extract archive")
    print("   ✅ CleanupResult error handling correct")
}
