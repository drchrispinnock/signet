import SwiftUI

enum Theme {
    /// Keep the Tezos brand colour for protocol-specific icons.
    static let tezosBlue = Color(red: 0x0D / 255, green: 0x61 / 255, blue: 0xFF / 255)
    static let violet = Color(red: 0.40, green: 0.22, blue: 0.96)
    static let charcoal = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

enum AppRuntime {
    /// Explicit local preview mode: no file-backed wallet stores or live chain service.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
}
