import Foundation
import Testing
@testable import Signet

/// AirGap Vault's QR codes: Uniform Resources, fountain codes and the IAC v3 messages. The
/// vectors were made with AirGap's own libraries (`@airgap/serializer` 0.14.0 and
/// `@ngraveio/bc-ur` 1.1.13), and AirGap's decoder reads what `UniformResource.encode` writes.
struct AirGapTests {
    /// An account share for public key a0b1…8e9f, path m/44h/1729h/0h/0h, fingerprint f4e3d2c1,
    /// group "My Vault", message id 12345678.
    static let shareSingle = "UR:BYTES/HDHLCTLUAYAEAEAEAEAEAEAXJEIDJTJZIHIEGAPLDEPTMOIDTPMUVSTSHYMKPYJLIDMOOYJLISJTIENLOYJLAEFWPLGSHECKHEFTMKVYHPPTBEMTHDNYGUWZYKBDFYCXFWMEINSESWFXMSNEKEIHBWTSPFWKLETOPTWENDMYTOATAEWLWESRWMHHAEAEAEFLMOLTWN"
    /// The same share as an animated code of three fragments: parts 1 to 3 pure, 4 to 9 mixed.
    static let shareParts = [
        "ur:bytes/1-3/lpadaxcshecyflmoltwnhdcxhdhlctluayaeaeaeaeaeaeaxjeidjtjzihiegapldeptmoidtpmuvstshymkpyjlhfpabyga",
        "ur:bytes/2-3/lpaoaxcshecyflmoltwnhdcxidmooyjlisjtienloyjlaefwplgsheckheftmkvyhpptbemthdnyguwzykbdfycxnljnbgwp",
        "ur:bytes/3-3/lpaxaxcshecyflmoltwnhdcxfwmeinseswfxmsnekeihbwtspfwkletoptwendmytoataewlwesrwmhhaeaeaeaetykovlcl",
        "ur:bytes/4-3/lpaaaxcshecyflmoltwnhdcxidmooyjlisjtienloyjlaefwplgsheckheftmkvyhpptbemthdnyguwzykbdfycxtijycprl",
        "ur:bytes/5-3/lpahaxcshecyflmoltwnhdcxfwmeinseswfxmsnekeihbwtspfwkletoptwendmytoataewlwesrwmhhaeaeaeaentjltekn",
        "ur:bytes/6-3/lpamaxcshecyflmoltwnhdcxfwmeinseswfxmsnekeihbwtspfwkletoptwendmytoataewlwesrwmhhaeaeaeaeghhpspkt",
        "ur:bytes/7-3/lpataxcshecyflmoltwnhdcxkshytsdaoldpwfamutbkbwmtkptnrkrfmuqdgertryatlfcajnsggdkkpymuwsgwbznbdsdk",
        "ur:bytes/8-3/lpayaxcshecyflmoltwnhdcxidmooyjlisjtienloyjlaefwplgsheckheftmkvyhpptbemthdnyguwzykbdfycxfwfgfwad",
        "ur:bytes/9-3/lpasaxcshecyflmoltwnhdcxfwmeinseswfxmsnekeihbwtspfwkletoptwendmytoataewlwesrwmhhaeaeaeaebshlqdsf",
    ]
    /// A sign request (id 87654321) for 40 × ab then 6c00, as AirGap Wallet writes it.
    static let requestSingle = "ur:bytes/hdhgctluayaeaeaeaeaeaeaxjeidjtjzihiegtpldeptmoidrepsurtphhnsmkhkmwnnhdnbhpnnmkmumuhtidonpejlneidcwoyspqzhnvloysbgwrnprldjehdknfevdtyynsnflvdemfgiseopmdsbgvedyaeaecsnncygukpaeaeaesfmtpssb"
    /// Its response: the same bytes followed by 64 × cd.
    static let responseSingle = "ur:bytes/hdeectluayaeaeaeaeaeaeaxjeidjtjzihiegrpldeptmoidrepsurtpvesaghuyemfhcpndinecmecxltvydwlpaeaekovydwwflfaeaeaegsaoadmt"
    static let publicKeyHex = "a0b1c2d3e4f5061728394a5b6c7d8e9fa0b1c2d3e4f5061728394a5b6c7d8e9f"
    static let forged = Hex.decode(String(repeating: "ab", count: 40) + "6c00")!

    private func payload(_ texts: [String]) throws -> [UInt8]? {
        var decoder = UniformResource.Decoder()
        for text in texts {
            if case .complete(let payload) = try decoder.receive(UniformResource.Part(text: text)) { return payload }
        }
        return nil
    }

    @Test func readsAVaultAccountShare() throws {
        let messages = try AirGap.messages(from: #require(try payload([Self.shareSingle])))
        #expect(messages.count == 1)
        #expect(messages[0].id == 12_345_678)
        let accounts = try AirGap.accounts(in: messages)
        #expect(accounts == [AirGap.Account(publicKey: "edpkurzfBZJnGNxoUrkB4xPssgKEz3QssGGnCc1RcJh1rFFyLk9CiR",
                                            derivationPath: "m/44h/1729h/0h/0h", masterFingerprint: "f4e3d2c1", groupLabel: "My Vault")])
        #expect(accounts[0].locator == "airgap://f4e3d2c1/44h/1729h/0h/0h")
        #expect(KeyKind(locator: accounts[0].locator) == .airgap)
        #expect(!KeyKind.airgap.canSign)
    }

    @Test(arguments: [[1, 2, 3], [3, 2, 1], [2, 4, 5, 6, 7, 8, 9], [1, 7, 9], [4, 5, 6, 7, 8, 9], [3, 4, 5, 7], [1, 1, 2, 2, 3]])
    func joinsAnimatedFramesInAnyOrder(order: [Int]) throws {
        let single = try payload([Self.shareSingle])
        #expect(try payload(order.map { Self.shareParts[$0 - 1] }) == single)
    }

    @Test func waitsForMissingFragments() throws {
        var decoder = UniformResource.Decoder()
        #expect(try decoder.receive(UniformResource.Part(text: Self.shareParts[0])) == .needMore)
        // Part 7 mixes all three fragments, so it alone cannot add one.
        #expect(try decoder.receive(UniformResource.Part(text: Self.shareParts[6])) == .needMore)
        #expect(decoder.receivedFragments == 1)
        #expect(decoder.expectedParts == 3)
    }

    @Test func refusesACorruptedFrame() {
        var text = Self.shareSingle
        text.replaceSubrange(text.index(text.startIndex, offsetBy: 40)..<text.index(text.startIndex, offsetBy: 42), with: "ZO")
        #expect(throws: UniformResource.DecodeError.self) { try UniformResource.Part(text: text) }
        #expect(throws: UniformResource.DecodeError.self) { try UniformResource.Part(text: "ur:crypto-psbt/" + Self.shareSingle.dropFirst(9)) }
    }

    /// The reference implementation's choices of fragments for mixed parts of a 17-fragment message.
    @Test func choosesTheReferenceFragments() {
        let expected: [Int: Set<Int>] = [
            18: [11], 19: [15], 20: [3, 12, 13, 14], 22: [0, 1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16], 23: [7, 14, 16],
            28: [2, 3, 4, 5, 6, 11, 12, 13, 16], 29: [3, 5, 7, 8, 9], 32: [2, 3, 4, 5, 11, 13, 16], 35: [2, 5, 9, 13],
            37: [0, 1, 6, 10, 15, 16], 40: [4, 13], 50: [7], 123: [14, 16],
        ]
        for (number, indexes) in expected {
            #expect(Set(UniformResource.fragmentIndexes(number: number, count: 17, checksum: 0xdead_beef)) == indexes, "part \(number)")
        }
        #expect(Set(UniformResource.fragmentIndexes(number: 4, count: 3, checksum: 0)) == [1, 2])
        #expect(UniformResource.fragmentIndexes(number: 5, count: 17, checksum: 0) == [4])
    }

    @Test func writesTheSignRequestAirGapWalletWrites() throws {
        let edpk = try #require(AirGap.edpk(from: Self.publicKeyHex))
        let request = try #require(AirGap.signRequest(publicKey: edpk, forged: Self.forged, id: 87_654_321))
        let theirs = try AirGap.messages(from: #require(try payload([Self.requestSingle])))
        #expect(theirs == [request])
        // Compression's DEFLATE happens to match pako's here, so the code is the same too.
        #expect(UniformResource.encode(AirGap.payload(for: [request]), maximumFragment: 2000) == [Self.requestSingle.uppercased()])
    }

    @Test func splitsALongRequestIntoFramesThatJoinAgain() throws {
        let edpk = try #require(AirGap.edpk(from: Self.publicKeyHex))
        let request = try #require(AirGap.signRequest(publicKey: edpk, forged: [UInt8](repeating: 0x5a, count: 3000) + (0..<255).map { UInt8($0) }, id: 11_112_222))
        let message = AirGap.payload(for: [request])
        let frames = UniformResource.encode(message, maximumFragment: 200)
        #expect(frames.count > 1)
        #expect(frames.allSatisfy { $0.hasPrefix("UR:BYTES/") })
        #expect(try payload(frames.reversed()) == message)
        #expect(try AirGap.messages(from: message) == [request])
    }

    @Test func readsTheSignedOperation() throws {
        let messages = try AirGap.messages(from: #require(try payload([Self.responseSingle])))
        #expect(try AirGap.signedOperation(in: messages, id: 87_654_321) == Self.forged + [UInt8](repeating: 0xcd, count: 64))
        #expect(throws: AirGap.Error.wrongResponse) { try AirGap.signedOperation(in: messages, id: 11_111_111) }
    }

    @Test func writesStringsAsAirGapDoes() throws {
        for text in ["", "My Vault", "m/44h/1729h/0h/0h", "abcd", "abc", "0xabcd", "0xabc", "0xnothex", "f4e3d2c1"] {
            #expect(try AirGap.decodeString(AirGap.encodeString(text)) == text)
        }
        #expect(AirGap.encodeString("f4e3d2c1") == .bytes([2, 0xf4, 0xe3, 0xd2, 0xc1]))
        #expect(AirGap.encodeString("My Vault") == .text("My Vault"))
    }

    @Test func gzipRoundTrips() {
        let data = Array("Signet and AirGap Vault, Signet and AirGap Vault".utf8)
        #expect(Gzip.decompress(Gzip.compress(data), limit: 1000) == data)
        #expect(Gzip.decompress(Gzip.compress(data), limit: 10) == nil)
        #expect(Gzip.decompress(Array(data), limit: 1000) == nil)
    }

    @Test func classifiesAirGapCodes() throws {
        guard case .uniformResource = QRPayload.classify(Self.shareSingle) else { Issue.record("single"); return }
        guard case .uniformResource = QRPayload.classify(Self.shareParts[4]) else { Issue.record("frame"); return }
        let body = Self.shareSingle.dropFirst("UR:BYTES/".count)
        guard case .uniformResource(let part) = QRPayload.classify("airgap-wallet://?ur=\(body)") else { Issue.record("link"); return }
        #expect(part == (try UniformResource.Part(text: Self.shareSingle)))
        #expect(QRPayload.classify("airgap-wallet://?d=3vQB7B6MrGQZaxCuFg4oh") == .airGapLegacy)
        #expect(QRPayload.classify("ur:bytes/nonsense") == .unknown)
        #expect(!QRPayload.classify(Self.shareSingle).isSecret)
    }

    @Test func skipsOtherCoinsAndExtendedKeys() throws {
        let other = AirGap.Message(type: AirGap.MessageType.accountShareResponse.rawValue, protocolIdentifier: "eth", id: 1, payload: [])
        #expect(try AirGap.accounts(in: [other]).isEmpty)
        let messages = try AirGap.messages(from: #require(try payload([Self.shareSingle])))
        var extended = messages[0]
        extended.payload[4] = .bool(true)
        #expect(throws: AirGap.Error.malformed) { try AirGap.accounts(in: [extended]) }
    }
}
