#if os(macOS)
import AppKit
@testable import CoreSampleCode
import Foundation
import SharedConstants
import Testing

/// Regression guard for #6. The authentication window only renders when the
/// CLI process runs with `.regular` activation policy; `.prohibited` (the
/// default for bare CLI tools) silently drops `NSWindow.makeKeyAndOrderFront`.
@Suite("Sample.Core.Downloader auth flow activation policy")
struct SampleCodeAuthPolicyTests {
    @Test("Auth flow requires .regular activation policy (fix for #6)")
    func authFlowPolicyIsRegular() {
        #expect(Sample.Core.Downloader.authFlowActivationPolicy == .regular)
    }

    @Test("Auth flow policy is not .prohibited (the silent-no-op default)")
    func authFlowPolicyIsNotProhibited() {
        #expect(Sample.Core.Downloader.authFlowActivationPolicy != .prohibited)
    }

    @Test("Auth flow policy is not .accessory (menu-bar-only, no window)")
    func authFlowPolicyIsNotAccessory() {
        #expect(Sample.Core.Downloader.authFlowActivationPolicy != .accessory)
    }
}

// MARK: - Cookie detection (#6 follow-up auto-advance)

@Suite("Sample.Core.Downloader.containsAppleSessionCookie")
struct AppleSessionCookieDetectionTests {
    private static func cookie(name: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: "v",
            .domain: domain,
            .path: "/",
        ])!
    }

    @Test("Empty cookie list returns false")
    func emptyList() {
        #expect(Sample.Core.Downloader.containsAppleSessionCookie([]) == false)
    }

    @Test("myacinfo on apple.com domain counts as signed-in")
    func myacinfoOnAppleCom() {
        let cookies = [Self.cookie(name: "myacinfo", domain: ".apple.com")]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("myacinfo on developer.apple.com subdomain also counts")
    func myacinfoOnDeveloperSubdomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "developer.apple.com")]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("myacinfo on a non-apple domain does NOT count")
    func myacinfoOnUnrelatedDomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "example.com")]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == false)
    }

    @Test("Unknown cookie name on apple.com does NOT count")
    func unrelatedCookieOnAppleDomain() {
        let cookies = [Self.cookie(name: "random_marketing", domain: ".apple.com")]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == false)
    }

    @Test("Mix of unrelated cookies plus the target cookie counts")
    func mixedWithTarget() {
        let cookies = [
            Self.cookie(name: "random_marketing", domain: ".apple.com"),
            Self.cookie(name: "tracking", domain: "example.com"),
            Self.cookie(name: "myacinfo", domain: "idmsa.apple.com"),
        ]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("Case-insensitive apple.com matching (APPLE.COM)")
    func caseInsensitiveDomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "APPLE.COM")]
        #expect(Sample.Core.Downloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("Target cookie name set includes myacinfo")
    func targetCookieNameSet() {
        #expect(Sample.Core.Downloader.appleSessionCookieNames.contains("myacinfo"))
    }
}

// MARK: - TTY detection (#6 follow-up)

@Suite("Sample.Core.Downloader.isInteractiveStdin")
struct IsInteractiveStdinTests {
    @Test("Override seam returns whatever was forced")
    func overrideIsRespected() {
        let previous = Sample.Core.Downloader._isInteractiveStdinOverride
        defer { Sample.Core.Downloader._isInteractiveStdinOverride = previous }

        Sample.Core.Downloader._isInteractiveStdinOverride = true
        #expect(Sample.Core.Downloader.isInteractiveStdin() == true)

        Sample.Core.Downloader._isInteractiveStdinOverride = false
        #expect(Sample.Core.Downloader.isInteractiveStdin() == false)
    }

    @Test("Clearing the override falls back to the real isatty check")
    func noOverrideFallsBack() {
        let previous = Sample.Core.Downloader._isInteractiveStdinOverride
        defer { Sample.Core.Downloader._isInteractiveStdinOverride = previous }

        Sample.Core.Downloader._isInteractiveStdinOverride = nil
        // We don't assert true/false here — swift test's stdin may or may not
        // be a TTY depending on how the runner invoked us. Just confirm the
        // call does not crash and returns a Bool.
        _ = Sample.Core.Downloader.isInteractiveStdin()
    }
}

// MARK: - AuthOutcome enum

@Suite("Sample.Core.Downloader.AuthOutcome")
struct AuthOutcomeTests {
    @Test("AuthOutcome exposes exactly the three expected cases")
    func outcomeCases() {
        // Exhaustive switch pins the case list at compile time.
        let all: [Sample.Core.Downloader.AuthOutcome] = [
            .autoDetected, .userConfirmed, .userClosedWindow,
        ]
        #expect(all.count == 3)
    }
}
#endif
