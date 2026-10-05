import AppKit
import SwiftUI

/// Light, dark, or follow the OS. Stored in the app's preferences.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "OS"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Applies to the whole app; `nil` lets every window follow the system.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}

/// Reads the stored appearance and keeps the app in step with it.
struct AppearanceApplier: ViewModifier {
    @AppStorage(Appearance.key) private var appearance: Appearance = .system

    func body(content: Content) -> some View {
        content
            .onAppear { appearance.apply() }
            .onChange(of: appearance) { _, new in new.apply() }
    }
}

extension View {
    func appliesStoredAppearance() -> some View { modifier(AppearanceApplier()) }
}
