import AppKit
import SwiftUI

/// The launch warning. Shown once per launch until the user turns it off in Settings.
enum Disclaimer {
    static let key = "showsDisclaimer"
    static let title = "⚠️ Signet - Warning"
    static let message = "Signet is very new software and should be used with care. Make sure you protect your keys with a password or use a Ledger.\n\nYou can turn off this warning in the Settings."
}

/// Presents the disclaimer when the window first appears. OK carries on; Exit quits the app.
struct DisclaimerAlert: ViewModifier {
    @AppStorage(Disclaimer.key) private var showsDisclaimer = true
    @State private var isPresented = false
    /// Never pop up inside a test host.
    private let suppressed = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func body(content: Content) -> some View {
        content
            .onAppear { if showsDisclaimer, !suppressed { isPresented = true } }
            .alert(Disclaimer.title, isPresented: $isPresented) {
                // OK takes the cancel role so SwiftUI does not add a Cancel button of its own.
                Button("OK", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
                Button("Exit", role: .destructive) { NSApp.terminate(nil) }
            } message: {
                Text(Disclaimer.message)
            }
    }
}

extension View {
    func showsLaunchDisclaimer() -> some View { modifier(DisclaimerAlert()) }
}
