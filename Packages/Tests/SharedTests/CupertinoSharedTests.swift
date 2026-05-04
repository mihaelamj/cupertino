import Foundation
@testable import Shared
import Testing
import TestSupport

@Test func configuration() {
    let config = Shared.CrawlerConfiguration()
    #expect(config.maxPages > 0)
}

// MARK: - retryBackoff (#209)

@Test("retryBackoff produces 1s/3s/9s for attempts 1/2/3 with defaults")
func retryBackoffDefaultSequence() {
    let one = Shared.Constants.Delay.retryBackoff(attempt: 1)
    let two = Shared.Constants.Delay.retryBackoff(attempt: 2)
    let three = Shared.Constants.Delay.retryBackoff(attempt: 3)
    #expect(one == .seconds(1))
    #expect(two == .seconds(3))
    #expect(three == .seconds(9))
}

@Test("retryBackoff returns zero for attempt < 1")
func retryBackoffZeroForAttemptZero() {
    #expect(Shared.Constants.Delay.retryBackoff(attempt: 0) == .zero)
    #expect(Shared.Constants.Delay.retryBackoff(attempt: -1) == .zero)
}

@Test("retryBackoff caps at retryBackoffMax for high attempt numbers")
func retryBackoffCapped() {
    // attempt 10 with default base 1s and multiplier 3 = 3^9s ≈ 19,683s,
    // far above the 30s cap.
    let huge = Shared.Constants.Delay.retryBackoff(attempt: 10)
    #expect(huge == Shared.Constants.Delay.retryBackoffMax)
}

@Test("retryBackoff respects custom base and multiplier")
func retryBackoffCustomParameters() {
    let halfSecond = Shared.Constants.Delay.retryBackoff(
        attempt: 3,
        base: .milliseconds(500),
        multiplier: 2.0,
        maxDelay: .seconds(60)
    )
    // 0.5s * 2^2 = 2s
    #expect(halfSecond == .seconds(2))
}

@Test("retryBackoff total budget across 3 default attempts is 13s")
func retryBackoffTotalBudget() {
    var total = Duration.zero
    for attemptIndex in 1...3 {
        total += Shared.Constants.Delay.retryBackoff(attempt: attemptIndex)
    }
    #expect(total == .seconds(13))
}
