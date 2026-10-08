import SwiftUI
import WebKit

/// Hosts Mt Pelerin's widget inside the app. Camera and microphone are granted only to Mt Pelerin's
/// own origin (its identity checks need them); links the widget tries to open in a new window, and
/// navigations away to other hosts, go to the browser instead.
struct BuyWebView: NSViewRepresentable {
    let url: URL
    var provider: BuyProvider = .current
    @Binding var isLoading: Bool
    @Binding var loadError: String?

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
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.load(URLRequest(url: url))
    }

    static func isTrusted(_ url: URL?, provider: BuyProvider = .current) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return isTrustedHost(host, provider: provider)
    }

    static func isTrustedHost(_ host: String, provider: BuyProvider) -> Bool {
        provider.trustedHosts.contains(host) || host.hasSuffix(provider.trustedDomainSuffix)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: BuyWebView
        var loadedURL: URL?

        init(_ parent: BuyWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.loadError = error.localizedDescription }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled { parent.loadError = error.localizedDescription }
        }

        /// Top-level navigations to other sites (bank pages, help links) belong in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if navigationAction.targetFrame?.isMainFrame ?? true, let url, url.scheme?.hasPrefix("http") == true, !BuyWebView.isTrusted(url, provider: parent.provider), navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// `window.open` targets: open in the browser rather than silently dropping them.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
            decisionHandler(BuyWebView.isTrustedHost(origin.host.lowercased(), provider: parent.provider) ? .grant : .deny)
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
