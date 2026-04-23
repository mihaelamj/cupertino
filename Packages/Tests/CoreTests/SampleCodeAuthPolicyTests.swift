#if os(macOS)
import AppKit
import Testing

@testable import Core

/// Regression guard for #6. The authentication window only renders when the
/// CLI process runs with `.regular` activation policy; `.prohibited` (the
/// default for bare CLI tools) silently drops `NSWindow.makeKeyAndOrderFront`.
///
/// These tests do not exercise the window itself — that needs an interactive
/// sign-in and is covered by a separate manual verification. What they pin
/// down is the constant the production code reads: if a future change drops
/// the value to `.prohibited` or `.accessory`, `cupertino fetch --authenticate`
/// silently regresses into the #6 bug.
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
#endif
