import Foundation
import Testing
@testable import Signet

/// Remote signers (octez-signer). The wire vectors are what octez-client sent to and
/// octez-signer 21 answered over TCP, captured with a logging proxy, and requests octez-signer
/// accepted; `signer_messages.ml` in octez is the reference for the encodings.
struct RemoteSignerTests {
    static let alice = Address("tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG")
    static let aliceKey = "edpkuStAKZyEk99wkft2maSTVqAmj9HoCwf63y2HyMvhPP7MMH5crT"
    static let bob = Address("tz4Euk9qYr7b43PC8iyufuK4ycrmhiQ7NYJY")
    static let aliceHash = "00120136f4f9c3d29772aa2b3663e3c24acfc735e1"

    // MARK: Locators

    @Test(arguments: [
        ("tcp://localhost:7732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG", RemoteSignerLocator.Transport.tcp, "localhost", 7732, ""),
        ("http://192.168.1.20:6732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG", .http, "192.168.1.20", 6732, ""),
        ("https://signer.example.com/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG", .https, "signer.example.com", 443, ""),
        ("https://signer.example.com:8443/tezos/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG", .https, "signer.example.com", 8443, "/tezos"),
        ("http://signer.local/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG", .http, "signer.local", 80, ""),
    ])
    func readsOctezClientLocators(text: String, transport: RemoteSignerLocator.Transport, host: String, port: Int, path: String) throws {
        let signer = try #require(RemoteSignerLocator(locator: text))
        #expect(signer.transport == transport)
        #expect(signer.host == host)
        #expect(signer.port == port)
        #expect(signer.path == path)
        #expect(signer.address == Self.alice)
        #expect(RemoteSignerLocator(locator: signer.locator) == signer)
        #expect(KeyKind(locator: text) == .remote)
    }

    @Test func writesTheLocatorOctezClientReads() {
        let signer = RemoteSignerLocator(transport: .tcp, host: "localhost", port: 7732, address: Self.alice)
        #expect(signer.locator == "tcp://localhost:7732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG")
        #expect(signer.endpoint == "tcp://localhost:7732")
        #expect(RemoteSignerLocator(transport: .http, host: "::1", port: 6732, address: Self.alice).locator == "http://[::1]:6732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG")
        let unix = RemoteSignerLocator(transport: .unix, host: "", port: 0, path: "/tmp/signer.sock", address: Self.alice)
        #expect(unix.locator == "unix:/tmp/signer.sock?pkh=tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG")
        #expect(RemoteSignerLocator(locator: unix.locator) == unix)
        #expect(RemoteSignerLocator.Transport.http.defaultPort == 6732)
        #expect(RemoteSignerLocator.Transport.https.defaultPort == 443)
        #expect(RemoteSignerLocator.Transport.tcp.defaultPort == 7732)
    }

    @Test(arguments: [
        "remote:tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG",
        "tcp://localhost/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG",
        "tcp://localhost:7732/KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi",
        "tcp://localhost:7732/nonsense",
        "https://user:pw@signer.example.com/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG",
        "http://localhost:6732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG?x=1",
        "unix:/tmp/signer.sock",
    ])
    func refusesWhatItCannotUse(text: String) {
        #expect(RemoteSignerLocator(locator: text) == nil)
    }

    @Test func remoteKeysSignButRemoteColonDoesNot() {
        #expect(KeyKind.remote.canSign && KeyKind.remote.signsMessages)
        #expect(KeyKind(locator: "remote:tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG") == .unknown)
        #expect(KeyKind(locator: "unix:/tmp/s?pkh=tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG") == .remote)
    }

    // MARK: Wire

    @Test func writesTheRequestsOctezSends() throws {
        #expect(Hex.encode(try #require(SignerWire.publicKeyRequest(address: Self.alice))) == "01" + Self.aliceHash)
        #expect(Hex.encode(try #require(SignerWire.frame([1] + Hex.decode(Self.aliceHash)!))) == "0016" + "01" + Self.aliceHash)
        let data: [UInt8] = [3] + [UInt8](repeating: 0xab, count: 40)
        // Accepted by octez-signer: kind 00, key hash, 4-byte length, data, and no byte for the absent authentication.
        #expect(Hex.encode(try #require(SignerWire.signRequest(address: Self.alice, data: data))) == "00" + Self.aliceHash + "00000029" + Hex.encode(data))
        #expect(SignerWire.authorizedKeysRequest == [2])
        #expect(SignerWire.knownKeysRequest == [6])
        #expect(try #require(SignerWire.provePossessionRequest(address: Self.bob)).count == 1 + 21 + 1)
    }

    @Test func namesATz4KeyWithItsVersion() throws {
        let hash = try #require(SignerWire.keyHash(Self.bob))
        #expect(hash.count == 21 && hash[0] == 3)
        let current = try #require(SignerWire.signRequest(address: Self.bob, data: [3, 1]))
        #expect(Array(current.prefix(24)) == [0, 3] + hash + [SignerWire.blsSignatureVersion])
        #expect(SignerWire.address(fromKeyHash: hash[...]) == Self.bob)
    }

    @Test func readsTheSignersReplies() throws {
        let publicKeyReply = Hex.decode("0000" + "69f1f01c04a09e8dec3f53e95f2ec95d2d65202b7af989f63a1d29aa32aead85")!
        #expect(try SignerWire.publicKey(fromValue: SignerWire.value(publicKeyReply)) == Self.aliceKey)
        // `--require-authentication` with no keys, then no authentication.
        #expect(try SignerWire.authorizedKeys(fromValue: SignerWire.value(Hex.decode("000100000000")!)) == [])
        #expect(try SignerWire.authorizedKeys(fromValue: SignerWire.value([0, 0])) == nil)
        let one = Hex.decode(Self.aliceHash)!
        #expect(try SignerWire.addresses(fromValue: (one + one)[...]) == [Self.alice, Self.alice])
        #expect(try SignerWire.addresses(fromValue: ([0, 0, 0, 21] + one)[...]) == [Self.alice])
        #expect(throws: SignerWire.Failure.malformed) { try SignerWire.addresses(fromValue: ([0, 0, 0, 22] + one)[...]) }
        let refusal = [1] + Array(#"[{"kind":"temporary","id":"signer.unknown_key","msg":"x"}]"#.utf8)
        #expect(throws: SignerWire.Failure.refused("signer.unknown_key")) { try SignerWire.value(refusal) }
        // What an octez-signer started without --allow-list-known-keys answers to known_keys: BSON.
        let listing = Hex.decode("010000005b0000005757000000026b696e64000a00000074656d706f726172790002696400080000006661696c75726500026d736700250000004c697374206b6e6f776e206b6579732072657175657374206e6f7420616c6c6f7765642e0000")!
        #expect(throws: SignerWire.Failure.refused("List known keys request not allowed.")) { try SignerWire.value(listing) }
        let declined = RemoteSignerError.declined(.listKeys, signer: "tcp://192.168.178.213:7732", key: Self.alice, reason: "List known keys request not allowed.")
        #expect(declined.localizedDescription.contains("The signer at tcp://192.168.178.213:7732 will not list its keys. The signer said: “List known keys request not allowed.”"))
        #expect(declined.localizedDescription.contains("--allow-list-known-keys"))
        let sign = RemoteSignerError.declined(.sign, signer: "tcp://h:7732", key: Self.alice, reason: nil).localizedDescription
        #expect(sign.contains("refused to sign with \(Self.alice.value). The signer gave no reason."))
        #expect(throws: SignerWire.Failure.malformed) { try SignerWire.value([7]) }
    }

    @Test func handsTheBridgeTheSignatureAsGiven() throws {
        #expect(RemoteSignature.raw([0xab, 0xcd]).bridgeJSON == #"{"raw":"abcd"}"#)
        #expect(RemoteSignature.base58("edsigX").bridgeJSON == #"{"signature":"edsigX"}"#)
        let signer = RemoteSignerLocator(transport: .tcp, host: "localhost", port: 7732, address: Self.alice)
        let key = SigningKey.remote(signer, publicKey: Self.aliceKey)
        let spec = try #require(try JSONSerialization.jsonObject(with: Data(key.bridgeSpec.utf8)) as? [String: String])
        #expect(spec == ["kind": "remote", "locator": signer.locator, "publicKey": Self.aliceKey, "address": Self.alice.value])
    }

    @Test func answersTheBridgeOnlyForTheKeyItNames() async throws {
        let mock = MockRemoteSignerService(keys: [Self.alice: Self.aliceKey]) { bytes, _ in .raw(bytes.reversed()) }
        let locator = "tcp://localhost:7732/\(Self.alice.value)"
        let reply = try await RemoteSigners.answer(requestJSON: #"{"op":"sign","locator":"\#(locator)","address":"\#(Self.alice.value)","bytes":"0301"}"#, service: mock)
        #expect(reply == #"{"raw":"0103"}"#)
        await #expect(throws: RemoteSignerError.malformedReply) {
            try await RemoteSigners.answer(requestJSON: #"{"op":"sign","locator":"\#(locator)","address":"\#(Self.bob.value)","bytes":"0301"}"#, service: mock)
        }
        await #expect(throws: RemoteSignerError.malformedReply) {
            try await RemoteSigners.answer(requestJSON: #"{"op":"sign","locator":"remote:\#(Self.alice.value)","address":"\#(Self.alice.value)","bytes":"0301"}"#, service: mock)
        }
    }

    // MARK: Accounts

    @Test @MainActor func connectsAnAccountOctezClientCanUse() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-remote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TezosClientStore(directory: dir)
        let multisig = MockMultisigService()
        multisig.keyAddresses = [Self.aliceKey: Self.alice.value, "edpkOther": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"]
        let model = WalletViewModel(chain: MockChainService(), multisig: multisig, walletStore: store)
        model.remoteSigners = MockRemoteSignerService(keys: [Self.alice: Self.aliceKey])
        let signer = RemoteSignerLocator(transport: .tcp, host: "localhost", port: 7732, address: Self.alice)

        let check = try await model.checkRemoteSigner(signer)
        #expect(check.publicKey == Self.aliceKey && check.acceptsUnauthenticated)
        try await model.connectRemoteSigner(alias: "Baker", signer: signer)

        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Baker" && wallet.keyKind == .remote && wallet.remoteSigner == signer && wallet.publicKey == Self.aliceKey)
        let secrets = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("secret_keys"))) as? [[String: Any]]
        #expect(secrets?.first?["value"] as? String == "tcp://localhost:7732/tz1MHEJyAu3Jw6uHKqdkvbkwLPEwxgfvgXcG")
        let publics = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("public_keys"))) as? [[String: Any]]
        #expect((publics?.first?["value"] as? [String: Any])?["locator"] as? String == signer.locator)
        #expect(try store.load().first == wallet)
        #expect(try model.signingKey(for: wallet, passphrase: nil) == .remote(signer, publicKey: Self.aliceKey))

        await #expect(throws: WalletViewModel.WalletError.self) { try await model.connectRemoteSigner(alias: "Again", signer: signer) }
    }

    @Test @MainActor func refusesAKeyThatIsNotTheAddresss() async throws {
        let multisig = MockMultisigService()
        multisig.keyAddresses = ["edpkOther": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"]
        let model = WalletViewModel(chain: MockChainService(), multisig: multisig, walletStore: InMemoryWalletStore())
        model.remoteSigners = MockRemoteSignerService(keys: [Self.alice: "edpkOther"], requiresAuthentication: true)
        let signer = RemoteSignerLocator(transport: .http, host: "localhost", port: 6732, address: Self.alice)
        await #expect(throws: RemoteSignerError.keyMismatch(expected: Self.alice, found: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))) {
            try await model.connectRemoteSigner(alias: "Liar", signer: signer)
        }
        #expect(model.wallets.allSatisfy { $0.alias != "Liar" })
    }
}

/// The whole path through the real bridge: Taquito's signer → `__signet.remoteSign` → this
/// client → an octez-signer → back into the bridge, which checks the signature. Opt-in: set
/// `TEST_RUNNER_SIGNET_REMOTE_SIGNERS` to comma-separated locators of running signers, e.g.
/// `tcp://localhost:7732/tz1…,http://localhost:6732/tz4…` (`octez-signer launch socket signer`).
/// A tz4 key needs octez-signer 23 or later: older ones make BLS signatures the chain refuses.
struct RemoteSignerLiveTests {
    static let locators = (ProcessInfo.processInfo.environment["SIGNET_REMOTE_SIGNERS"] ?? "")
        .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

    @Test(.enabled(if: !locators.isEmpty, "Set TEST_RUNNER_SIGNET_REMOTE_SIGNERS to locators of running octez-signers"))
    func signsThroughTheBridgeWithARealSigner() async throws {
        let chain = TaquitoChainService(network: .shadownet)
        for text in Self.locators {
            let signer = try #require(RemoteSignerLocator(locator: text), "\(text)")
            let publicKey = try await NetworkRemoteSignerService().publicKey(at: signer)
            // A Micheline payload: signed with no watermark, as dApps and multisig do.
            let signed = try await chain.signPayload(signer: .remote(signer, publicKey: publicKey), payloadHex: "05" + "0100000006" + Hex.encode(Array("Signet".utf8)))
            #expect(signed.publicKey == publicKey, "\(text)")
            #expect(signed.signature.hasPrefix(signer.address.scheme == .tz4 ? "BLsig" : "edsig") || signed.signature.hasPrefix("sig"), "\(text)")
            // A signer holding another key under this address is caught by the bridge.
            let liar = RemoteSignerLocator(transport: signer.transport, host: signer.host, port: signer.port, path: signer.path, address: signer.address)
            let other = signer.address.scheme == .tz4 ? "BLpk1tmtxM1XWK3V3DCb2KS4ykCiQV5XhrrsGgTx54HkP4g6wSqP7edV8dj84S9R2jKnmQKaTgkQ" : "edpkuStAKZyEk99wkft2maSTVqAmj9HoCwf63y2HyMvhPP7MMH5crT"
            if other != publicKey {
                await #expect(throws: (any Error).self) { try await chain.signPayload(signer: .remote(liar, publicKey: other), payloadHex: "0500") }
            }
        }
    }
}
