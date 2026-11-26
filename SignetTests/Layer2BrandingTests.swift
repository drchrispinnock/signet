import AppKit
import Foundation
import Testing
@testable import Signet

/// Experimental Layer 2 branding: Etherlink by default, Tezos X on request; a rollup with a
/// name of its own keeps it, and both logos are in the bundle. The shared UserDefaults are
/// never changed here (other suites run alongside and expect "Etherlink").
struct Layer2BrandingTests {
    @Test func etherlinkIsTheDefaultAndTezosXRenamesIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "Layer2BrandingTests-\(UUID().uuidString)"))
        #expect(Layer2Branding.current(defaults) == .etherlink)
        defaults.set("tezosX", forKey: Layer2Branding.key)
        #expect(Layer2Branding.current(defaults) == .tezosX)
        defaults.set("nonsense", forKey: Layer2Branding.key)
        #expect(Layer2Branding.current(defaults) == .etherlink)

        #expect(Network.mainnet.l2Name(for: .etherlink) == "Etherlink")
        #expect(Network.mainnet.l2Name(for: .tezosX) == "Tezos X")
        #expect(Network.shadownetPreviewnet.l2Name(for: .tezosX) == "Previewnet")
        #expect(Layer2Branding.tezosX.logo == "TezosXLogo" && Layer2Branding.etherlink.logo == "EtherlinkLogo")
    }

    #if canImport(AppKit)
    @Test func bothLogosAreBundled() {
        for branding in Layer2Branding.allCases {
            #expect(NSImage(named: branding.logo) != nil, Comment(rawValue: branding.logo))
            #expect(NSImage(named: branding.miniLogo) != nil, Comment(rawValue: branding.miniLogo))
        }
        // The tabs' Tezos X mark is its own asset with the bigger X.
        #expect(Layer2Branding.tezosX.miniLogo == "TezosXMini" && Layer2Branding.etherlink.miniLogo == "EtherlinkLogo")
    }
    #endif

    @Test func layerMarksAreLogosByDefault() {
        #expect(LayerMarks.allCases.map(\.title) == ["tz", "L1/L2"])
        #expect(LayerMarks(rawValue: "labels") == .labels && LayerMarks(rawValue: "x") == nil)
    }
}
