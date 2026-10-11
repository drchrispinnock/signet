import SwiftUI
import WebKit

/// Hosts the on-ramp's widget inside the app. The embedded page has no address bar, so the policy
/// is strict (S23): the main frame may only ever show HTTPS pages on the provider's own hosts,
/// and the sheet shows which host is up. Links the widget opens elsewhere go to the browser,
/// where the user can see where they are; any other foreign navigation (a redirect, a script, a
/// form posting away) is simply cancelled. Frames may only load HTTPS. Camera and microphone are
/// granted only to the provider's exact hosts, over HTTPS, from the main frame (its identity
/// checks need them), and only when the frame asking is that same origin.
struct BuyWebView: NSViewRepresentable {
    let url: URL
    var provider: BuyProvider = .current
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    /// The URL the main frame is showing or loading, for the sheet's origin line.
    var currentURL: Binding<URL?>? = nil

    /// What to do with a navigation the web view proposes.
    enum NavigationPolicy: Equatable, Sendable {
        case allow
        /// A foreign page the user asked for: show it in the browser instead.
        case openInBrowser
        case cancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.load(URLRequest(url: url))
    }

    // MARK: Policy (pure, tested)

    /// An HTTPS URL on one of the provider's hosts.
    static func isTrusted(_ url: URL?, provider: BuyProvider = .current) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host()?.lowercased() else { return false }
        return isTrustedHost(host, provider: provider)
    }

    static func isTrustedHost(_ host: String, provider: BuyProvider) -> Bool {
        let lower = host.lowercased()
        return provider.trustedHosts.contains(lower) || lower.hasSuffix(provider.trustedDomainSuffix)
    }

    /// Decides every navigation, main frame or not, whatever started it.
    static func policy(for url: URL?, navigationType: WKNavigationType, isMainFrame: Bool, provider: BuyProvider) -> NavigationPolicy {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if scheme == "about", url.absoluteString == "about:blank" { return .allow }
        guard scheme == "https" else { return .cancel }    // plain http, custom schemes, data:, file:
        guard isMainFrame else { return .allow }           // frames: any HTTPS, no browser hand-off
        if isTrusted(url, provider: provider) { return .allow }
        // Only something the user did on the page earns a trip to the browser; a redirect, a
        // script or a timer does not.
        switch navigationType {
        case .linkActivated, .formSubmitted: return .openInBrowser
        default: return .cancel
        }
    }

    /// Whether `window.open(url)` may be forwarded to the browser: only web URLs.
    static func mayOpenInBrowser(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// Camera/microphone: the provider's exact hosts, over HTTPS, asked for by the main frame
    /// whose own origin is that host.
    static func mayCaptureMedia(originProtocol: String, originHost: String, isMainFrame: Bool, frameProtocol: String?, frameHost: String?, provider: BuyProvider) -> Bool {
        guard originProtocol.lowercased() == "https", isMainFrame else { return false }
        let host = originHost.lowercased()
        guard provider.trustedHosts.contains(host) else { return false }
        return frameProtocol?.lowercased() == "https" && frameHost?.lowercased() == host
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: BuyWebView
        var loadedURL: URL?

        init(_ parent: BuyWebView) { self.parent = parent }

        private func showCurrent(_ webView: WKWebView) {
            parent.currentURL?.wrappedValue = webView.url
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
            showCurrent(webView)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            showCurrent(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            showCurrent(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            showCurrent(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.loadError = error.localizedDescription }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.loadError = error.localizedDescription }
        }

        /// Every navigation, including each hop of a redirect chain (WebKit asks again per hop).
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            switch BuyWebView.policy(for: url, navigationType: navigationAction.navigationType, isMainFrame: isMainFrame, provider: parent.provider) {
            case .allow:
                decisionHandler(.allow)
            case .openInBrowser:
                if let url { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            case .cancel:
                if isMainFrame, let url {
                    parent.loadError = "Blocked a page outside \(parent.provider.title): \(url.host() ?? url.scheme ?? "unknown"). Use “Open in browser instead” if you need it."
                }
                decisionHandler(.cancel)
            }
        }

        /// `window.open` targets go to the browser when they are web pages; other schemes are dropped.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, BuyWebView.mayOpenInBrowser(url) { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
            let allowed = BuyWebView.mayCaptureMedia(
                originProtocol: origin.protocol, originHost: origin.host, isMainFrame: frame.isMainFrame,
                frameProtocol: frame.securityOrigin.protocol, frameHost: frame.securityOrigin.host, provider: parent.provider)
            decisionHandler(allowed ? .grant : .deny)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
