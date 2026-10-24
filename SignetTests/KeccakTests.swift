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

    @Test func etherlinkAliasMatchesTheNode() {
        // What node.mainnet.etherlink.com's tez_getTezosEthereumAddress returns for this address.
        #expect(EtherlinkAlias.address(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")) == "0x16142132dd616dd8f61b8972ae4b9fcf8a22a450")
    }
}
