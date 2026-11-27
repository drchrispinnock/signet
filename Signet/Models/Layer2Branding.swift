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

    /// The asset for the 14 to 16 point marks on the tabs: Tezos X's has a much bigger X
    /// (`TezosXMini`), or it is hard to tell from the Tezos coin at that size.
    var miniLogo: String {
        switch self {
        case .etherlink: "EtherlinkLogo"
        case .tezosX: "TezosXMini"
        }
    }

    /// The stored choice. The test host shares the app's UserDefaults, so under it the
    /// standard defaults are ignored and the default branding is used (other defaults, as the
    /// tests pass them, are read as usual).
    static func current(_ defaults: UserDefaults = .standard) -> Layer2Branding {
        if defaults == .standard, SignetApp.isTestHost { return .etherlink }
        return defaults.string(forKey: key).flatMap(Layer2Branding.init(rawValue:)) ?? .etherlink
    }
}

/// Experimental (Settings > Experimental Features): how the Activity, Assets, NFTs and Domains
/// tabs mark a layer, in the layer toggles and on layer 2 rows and tiles: the chains' small
/// logos ("tz", the default) or the plain text L1 / L2. Kept in UserDefaults.
enum LayerMarks: String, CaseIterable, Identifiable, Sendable {
    case logos, labels

    static let key = "layerMarks"
    var id: String { rawValue }
    var title: String { self == .logos ? "tz" : "L1/L2" }
}

/// Experimental (Settings > Experimental Features): show tez, Layer 2 and Shielded as one
/// tez balance that expands into its parts. Off by default; kept in UserDefaults.
enum ConsolidatedBalances {
    static let key = "consolidatedBalances"
}

/// Shorthands for user-facing text: `"On \(Brand.l2)"`, `Image(Brand.l2Logo)`.
enum Brand {
    static var l2: String { Layer2Branding.current().name }
    static var l2Logo: String { Layer2Branding.current().logo }
    static var l2MiniLogo: String { Layer2Branding.current().miniLogo }
}
