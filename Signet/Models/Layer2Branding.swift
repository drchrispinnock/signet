import Foundation

/// Experimental (Settings > Experimental Features): what the app calls Etherlink, the Layer 2
/// rollup, and which logo it shows for it. "Tezos X" is the name the Tezos X work gives the
/// two runtimes together; choosing it renames every user-facing "Etherlink" and swaps the
/// Etherlink logo for the Tezos coin with an X (`TezosXLogo`). Nothing about the chain changes:
/// contracts, nodes, chain ids and the code's own names stay Etherlink's. Kept in UserDefaults.
enum Layer2Branding: String, CaseIterable, Identifiable, Sendable {
    case etherlink, tezosX

    static let key = "layer2Branding"
    var id: String { rawValue }

    /// The name shown in the app.
    var name: String {
        switch self {
        case .etherlink: "Etherlink"
        case .tezosX: "Tezos X"
        }
    }

    /// The asset drawn for the Layer 2.
    var logo: String {
        switch self {
        case .etherlink: "EtherlinkLogo"
        case .tezosX: "TezosXLogo"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> Layer2Branding {
        defaults.string(forKey: key).flatMap(Layer2Branding.init(rawValue:)) ?? .etherlink
    }
}

/// Shorthands for user-facing text: `"On \(Brand.l2)"`, `Image(Brand.l2Logo)`.
enum Brand {
    static var l2: String { Layer2Branding.current().name }
    static var l2Logo: String { Layer2Branding.current().logo }
}
