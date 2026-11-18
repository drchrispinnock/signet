import AppKit
import SwiftUI
import WebKit

/// Help > Getting Started: the book's Getting Started chapter (`manuscript/110-starting.md` and
/// its screenshots, bundled with the app) rendered by `Markua` and shown in its own window.
/// Links within the chapter scroll; every other link opens in the browser.
struct GettingStartedView: View {
    static let windowID = "getting-started"
    static let chapterResource = "110-starting"

    var body: some View {
        Group {
            if let html = Self.chapterHTML() {
                ChapterWebView(html: html, baseURL: Bundle.main.resourceURL)
            } else {
                VStack(spacing: 12) {
                    Text("The Getting Started chapter is missing from this copy of Signet.")
                    Link("Read it online", destination: SignetApp.gettingStartedURL)
                }
                .padding(40)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    /// The chapter as HTML, from the bundle.
    static func chapterHTML(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: chapterResource, withExtension: "md"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Markua.html(from: source, title: "Getting Started")
    }
}

/// A web view for one rendered page: no JavaScript, nothing fetched but the bundled pictures.
private struct ChapterWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(html, baseURL: baseURL)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)  // the page itself
                return
            }
            // A link to another place in the chapter scrolls there; anything else is the browser's.
            if url.fragment != nil, url.scheme == "file" || url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}

/// The Help menu's items. A view of its own so it can open the Getting Started window.
struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Getting Started") { openWindow(id: GettingStartedView.windowID) }
        Button("Signet Website") { NSWorkspace.shared.open(SignetApp.websiteURL) }
    }
}
