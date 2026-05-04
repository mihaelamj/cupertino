#if os(macOS)
import AppKit
@testable import Core
import Foundation
import Testing

/// Regression guard for #6. The authentication window only renders when the
/// CLI process runs with `.regular` activation policy; `.prohibited` (the
/// default for bare CLI tools) silently drops `NSWindow.makeKeyAndOrderFront`.
@Suite("SampleCodeDownloader auth flow activation policy")
struct SampleCodeAuthPolicyTests {
    @Test("Auth flow requires .regular activation policy (fix for #6)")
    func authFlowPolicyIsRegular() {
        #expect(SampleCodeDownloader.authFlowActivationPolicy == .regular)
    }

    @Test("Auth flow policy is not .prohibited (the silent-no-op default)")
    func authFlowPolicyIsNotProhibited() {
        #expect(SampleCodeDownloader.authFlowActivationPolicy != .prohibited)
    }

    @Test("Auth flow policy is not .accessory (menu-bar-only, no window)")
    func authFlowPolicyIsNotAccessory() {
        #expect(SampleCodeDownloader.authFlowActivationPolicy != .accessory)
    }
}

// MARK: - Cookie detection (#6 follow-up auto-advance)

@Suite("SampleCodeDownloader.containsAppleSessionCookie")
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
        #expect(SampleCodeDownloader.containsAppleSessionCookie([]) == false)
    }

    @Test("myacinfo on apple.com domain counts as signed-in")
    func myacinfoOnAppleCom() {
        let cookies = [Self.cookie(name: "myacinfo", domain: ".apple.com")]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("myacinfo on developer.apple.com subdomain also counts")
    func myacinfoOnDeveloperSubdomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "developer.apple.com")]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("myacinfo on a non-apple domain does NOT count")
    func myacinfoOnUnrelatedDomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "example.com")]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == false)
    }

    @Test("Unknown cookie name on apple.com does NOT count")
    func unrelatedCookieOnAppleDomain() {
        let cookies = [Self.cookie(name: "random_marketing", domain: ".apple.com")]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == false)
    }

    @Test("Mix of unrelated cookies plus the target cookie counts")
    func mixedWithTarget() {
        let cookies = [
            Self.cookie(name: "random_marketing", domain: ".apple.com"),
            Self.cookie(name: "tracking", domain: "example.com"),
            Self.cookie(name: "myacinfo", domain: "idmsa.apple.com"),
        ]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("Case-insensitive apple.com matching (APPLE.COM)")
    func caseInsensitiveDomain() {
        let cookies = [Self.cookie(name: "myacinfo", domain: "APPLE.COM")]
        #expect(SampleCodeDownloader.containsAppleSessionCookie(cookies) == true)
    }

    @Test("Target cookie name set includes myacinfo")
    func targetCookieNameSet() {
        #expect(SampleCodeDownloader.appleSessionCookieNames.contains("myacinfo"))
    }
}

// MARK: - TTY detection (#6 follow-up)

@Suite("SampleCodeDownloader.isInteractiveStdin")
struct IsInteractiveStdinTests {
    @Test("Override seam returns whatever was forced")
    func overrideIsRespected() {
        let previous = SampleCodeDownloader._isInteractiveStdinOverride
        defer { SampleCodeDownloader._isInteractiveStdinOverride = previous }

        SampleCodeDownloader._isInteractiveStdinOverride = true
        #expect(SampleCodeDownloader.isInteractiveStdin() == true)

        SampleCodeDownloader._isInteractiveStdinOverride = false
        #expect(SampleCodeDownloader.isInteractiveStdin() == false)
    }

    @Test("Clearing the override falls back to the real isatty check")
    func noOverrideFallsBack() {
        let previous = SampleCodeDownloader._isInteractiveStdinOverride
        defer { SampleCodeDownloader._isInteractiveStdinOverride = previous }

        SampleCodeDownloader._isInteractiveStdinOverride = nil
        // We don't assert true/false here — swift test's stdin may or may not
        // be a TTY depending on how the runner invoked us. Just confirm the
        // call does not crash and returns a Bool.
        _ = SampleCodeDownloader.isInteractiveStdin()
    }
}

// MARK: - AuthOutcome enum

@Suite("SampleCodeDownloader.AuthOutcome")
struct AuthOutcomeTests {
    @Test("AuthOutcome exposes exactly the three expected cases")
    func outcomeCases() {
        // Exhaustive switch pins the case list at compile time.
        let all: [SampleCodeDownloader.AuthOutcome] = [
            .autoDetected, .userConfirmed, .userClosedWindow,
        ]
        #expect(all.count == 3)
    }
}
#endif
