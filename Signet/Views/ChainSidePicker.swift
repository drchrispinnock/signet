import AppKit
import SwiftUI

/// Which side of the bridge a sheet is about: the account on Tezos, or the same account on Etherlink.
enum ChainSide: String, CaseIterable, Identifiable {
    case tezos = "Tezos", etherlink = "Etherlink"
    var id: String { rawValue }
    var logo: String { self == .tezos ? "TezosToken" : "EtherlinkLogo" }
}

/// The chain's logo and, when `canSwitch`, a standard pop-up button beside it (native bezel and
/// arrows, so it is plainly a dropdown) to switch between Tezos and Etherlink. Used at the top
/// left of the Receive and Send sheets; Receive names the second side "EVM", since what it shows
/// there is the account's address on Etherlink's EVM side.
struct ChainSidePicker: View {
    @Binding var side: ChainSide
    var canSwitch: Bool
    /// What the Layer 2 side is called on this network ("Etherlink", or "Previewnet").
    var layer2Name = ChainSide.etherlink.rawValue

    private func title(_ side: ChainSide) -> String { side == .etherlink ? layer2Name : side.rawValue }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.smallLogo(side.logo, points: 22))
                .accessibilityHidden(true)
            if canSwitch {
                Picker("Chain", selection: $side) {
                    ForEach(ChainSide.allCases) { candidate in
                        Text(title(candidate)).tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .help("On \(title(side)). Switch between Tezos and \(layer2Name).")
            }
        }
    }

    /// The asset drawn at `points`, whatever its pixel size (a menu label is flattened to an
    /// NSImage at the asset's own size, so the logo must already be small, not merely framed).
    static func smallLogo(_ name: String, points: CGFloat) -> NSImage {
        guard let image = NSImage(named: name)?.copy() as? NSImage else { return NSImage() }
        image.size = NSSize(width: points, height: points)
        return image
    }
}
