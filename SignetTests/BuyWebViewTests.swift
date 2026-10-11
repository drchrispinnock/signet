import Foundation
import Testing
import WebKit
@testable import Signet

/// S23: the embedded purchase page has no address bar, so the navigation and media policy
/// decides what the user can end up looking at and what the page can reach.
struct BuyWebViewPolicyTests {
    private let provider = BuyProvider.mtPelerin
    private func policy(_ text: String, _ type: WKNavigationType = .other, mainFrame: Bool = true) -> BuyWebView.NavigationPolicy {
        BuyWebView.policy(for: URL(string: text), navigationType: type, isMainFrame: mainFrame, provider: provider)
    }

    @Test func mainFrameOnlyShowsTheProvidersHTTPSPages() {
        #expect(policy("https://widget.mtpelerin.com/?x=1") == .allow)
        #expect(policy("https://kyc.mtpelerin.com/verify", .other) == .allow)
        #expect(policy("https://widget.mtpelerin.com/", .linkActivated) == .allow)
        // The provider over plain http is not the provider.
        #expect(policy("http://widget.mtpelerin.com/") == .cancel)
        // Look-alikes.
        #expect(policy("https://mtpelerin.com.evil.example/") == .cancel)
        #expect(policy("https://evil.example/widget.mtpelerin.com") == .cancel)
        #expect(policy("https://user:pw@widget.mtpelerin.com/") == .cancel)
    }

    @Test func redirectsScriptsAndFormsToForeignSitesAreCancelled() {
        // A server redirect or a script-driven navigation shows up as .other.
        #expect(policy("https://attacker.example/phish", .other) == .cancel)
        #expect(policy("https://attacker.example/phish", .reload) == .cancel)
        #expect(policy("https://attacker.example/phish", .backForward) == .cancel)
        #expect(policy("https://attacker.example/phish", .formResubmitted) == .cancel)
    }

    @Test func userInitiatedForeignLinksGoToTheBrowser() {
        #expect(policy("https://bank.example/login", .linkActivated) == .openInBrowser)
        #expect(policy("https://bank.example/pay", .formSubmitted) == .openInBrowser)
        // Only web pages go to the browser; a custom scheme is dropped even when clicked.
        #expect(policy("mailto:help@mtpelerin.com", .linkActivated) == .cancel)
        #expect(policy("signet://?type=tzip10&data=abc", .linkActivated) == .cancel)
        #expect(policy("x-apple.systempreferences:com.apple.preference", .linkActivated) == .cancel)
        #expect(policy("javascript:alert(1)", .linkActivated) == .cancel)
        #expect(policy("file:///etc/passwd", .linkActivated) == .cancel)
        #expect(policy("data:text/html,hi", .linkActivated) == .cancel)
    }

    @Test func framesMayOnlyLoadHTTPS() {
        #expect(policy("https://js.stripe.com/v3/", mainFrame: false) == .allow)
        #expect(policy("https://attacker.example/", .linkActivated, mainFrame: false) == .allow)
        #expect(policy("http://insecure.example/", mainFrame: false) == .cancel)
        #expect(policy("mailto:x@y", .linkActivated, mainFrame: false) == .cancel)
        #expect(policy("about:blank", mainFrame: false) == .allow)
        #expect(policy("about:blank") == .allow)
        #expect(BuyWebView.policy(for: nil, navigationType: .other, isMainFrame: true, provider: provider) == .cancel)
    }

    @Test func windowOpenForwardsOnlyWebURLs() {
        #expect(BuyWebView.mayOpenInBrowser(URL(string: "https://help.mtpelerin.com/")))
        #expect(BuyWebView.mayOpenInBrowser(URL(string: "http://example.org/")))
        #expect(!BuyWebView.mayOpenInBrowser(URL(string: "tel:+41000000000")))
        #expect(!BuyWebView.mayOpenInBrowser(URL(string: "signet://?type=tzip10&data=abc")))
        #expect(!BuyWebView.mayOpenInBrowser(URL(string: "file:///Applications")))
        #expect(!BuyWebView.mayOpenInBrowser(nil))
    }

    @Test func mediaCaptureNeedsTheExactHostOverHTTPSFromTheMainFrame() {
        func may(_ proto: String = "https", _ host: String = "widget.mtpelerin.com", main: Bool = true, frameProto: String? = "https", frameHost: String? = "widget.mtpelerin.com") -> Bool {
            BuyWebView.mayCaptureMedia(originProtocol: proto, originHost: host, isMainFrame: main, frameProtocol: frameProto, frameHost: frameHost, provider: provider)
        }
        #expect(may())
        #expect(may("https", "WIDGET.mtpelerin.com", frameHost: "widget.mtpelerin.com"))
        #expect(!may("http"))
        #expect(!may("https", "kyc.mtpelerin.com", frameHost: "kyc.mtpelerin.com"))   // suffix match is not enough for the camera
        #expect(!may(main: false))
        #expect(!may(frameHost: "attacker.example"))
        #expect(!may(frameProto: "http"))
        #expect(!may(frameProto: nil, frameHost: nil))
    }

    @Test func trustedMeansHTTPSOnTheProvidersHosts() {
        #expect(BuyWebView.isTrusted(URL(string: "https://widget.mtpelerin.com/x"), provider: provider))
        #expect(BuyWebView.isTrusted(URL(string: "https://kyc.mtpelerin.com/"), provider: provider))
        #expect(!BuyWebView.isTrusted(URL(string: "http://widget.mtpelerin.com/x"), provider: provider))
        #expect(!BuyWebView.isTrusted(URL(string: "https://evil.example/mtpelerin.com"), provider: provider))
        #expect(!BuyWebView.isTrusted(nil, provider: provider))
    }
}
