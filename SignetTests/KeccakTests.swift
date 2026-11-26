import Foundation
import Testing
@testable import Signet

struct KeccakTests {
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    @Test func matchesKnownKeccak256Vectors() {
        // Ethereum's Keccak-256, not SHA3-256 (which would start c5d24601 for "" too but differ for "abc").
        #expect(hex(Keccak.hash256(Data())) == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        #expect(hex(Keccak.hash256(Data("abc".utf8))) == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // Longer than one 136-byte block.
        let long = Data(String(repeating: "a", count: 200).utf8)
        #expect(hex(Keccak.hash256(long)) == "96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d")
    }

    /// Receive offers the EVM alias: only Etherlink 8.0's derivation is ever shown, and an old
    /// kernel's answer becomes `awaitingUpgrade` (`EtherlinkAliasTests`).
    @Test func theEvmAliasIsOfferedWithTheEtherlink8Derivation() {
        #expect(EtherlinkAlias.isOffered)
    }

    /// Etherlink 8.0's recoverable aliases for tz1–tz3 and the unchanged one for tz4 and KT1:
    /// octez.js's `getEthereumAlias` and Previewnet's gateway `resolveAddress` both gave these
    /// (26 November 2026); the first is octez.js's own documented example.
    @Test func etherlinkAliasMatchesEtherlink8() {
        let vectors = [
            "tz1aAdmy1MiGhnRkw8RWS6xbUpTuSRh3ZB4y": "0xcdb4d002582717fa10060665ec598ac68590072a",
            "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb": "0x3c0ee21da093b0aa44c590ba0bb1883ef8080137",
            "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq": "0x34cd840c30b89fbd90efbc6017c6db42ef143139",
            "tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5": "0x7d939c85301d07b57338b1a8b4e18279d5731d3e",
            "tz4E128TU3t1TdLCJEY4oHg8gZzZNoNBknwh": "0x0252d7a1b3428e1e578d013b26562cea8e3a828f",
            "KT18oDJJKXMKhfE1bSuAPGp92pYcwVDiqsPw": "0x24bc3b8e967680c95c8fba15cd5221093aac00d0",
        ]
        for (tz, evm) in vectors { #expect(EtherlinkAlias.address(for: Address(tz)) == evm, Comment(rawValue: tz)) }
        // Before 8.0 (and what Shadownet and mainnet Etherlink still answered on that date).
        #expect(EtherlinkAlias.legacyAddress(for: Address("tz1aAdmy1MiGhnRkw8RWS6xbUpTuSRh3ZB4y")) == "0x68087626a687c29afc74a3a344bf9b849f3900ed")
        #expect(EtherlinkAlias.legacyAddress(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")) == "0x16142132dd616dd8f61b8972ae4b9fcf8a22a450")
        #expect(EtherlinkAlias.legacyAddress(for: Address("tz4E128TU3t1TdLCJEY4oHg8gZzZNoNBknwh")) == EtherlinkAlias.address(for: Address("tz4E128TU3t1TdLCJEY4oHg8gZzZNoNBknwh")))
    }
}
