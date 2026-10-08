import Foundation

/// What the Tezos app on a Ledger told us about itself.
struct LedgerAppInfo: Equatable, Sendable {
    let version: String
    /// False for the Tezos Baking app, which cannot sign wallet operations.
    let isWallet: Bool
}

/// Discovery and key derivation on Ledger devices. Signing itself goes through `ChainService`
/// with a `SigningKey.ledger`.
protocol LedgerService: Sendable {
    func devices() async -> [LedgerDevice]
    /// Fails when the device shows the dashboard or another app.
    func appInfo(deviceID: String) async throws -> LedgerAppInfo
    /// Public key and address for `key`; with `prompt` the device shows the address for the user to approve.
    func address(deviceID: String, key: LedgerKey, prompt: Bool) async throws -> (publicKey: String, address: Address)
    /// octez-client's "ledger id": the ed25519 address at `44'/1729'`.
    func rootAddress(deviceID: String) async throws -> Address
}

/// The real thing: Taquito's `LedgerSigner` over the native HID transport, via the bridge.
struct BridgeLedgerService: LedgerService {
    let bridge: TaquitoBridge

    init(bridge: TaquitoBridge = .shared) {
        self.bridge = bridge
    }

    func devices() async -> [LedgerDevice] {
        guard let list = try? await bridge.call("ledgerDevices").arrayValue else { return [] }
        return list.compactMap { item in
            guard let id = item["id"]?.stringValue else { return nil }
            return LedgerDevice(id: id, name: item["name"]?.stringValue ?? "", productID: Int(item["productID"]?.doubleValue ?? 0))
        }
    }

    func appInfo(deviceID: String) async throws -> LedgerAppInfo {
        let r = try await mapped { try await bridge.call("ledgerAppVersion", [deviceID]) }
        return LedgerAppInfo(version: r["version"]?.stringValue ?? "?", isWallet: r["isWallet"]?.boolValue ?? true)
    }

    func address(deviceID: String, key: LedgerKey, prompt: Bool) async throws -> (publicKey: String, address: Address) {
        let r = try await mapped { try await bridge.call("ledgerGetAddress", [deviceID, key.fullPath, key.curve.derivationType, prompt]) }
        guard let pk = r["publicKey"]?.stringValue, let address = r["address"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected Ledger payload: \(String(describing: r))")
        }
        return (pk, Address(address))
    }

    func rootAddress(deviceID: String) async throws -> Address {
        let r = try await mapped { try await bridge.call("ledgerGetAddress", [deviceID, LedgerKey.rootPath.joined(separator: "/"), LedgerCurve.ed25519.derivationType, false]) }
        guard let address = r["address"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no root address from Ledger") }
        return Address(address)
    }

    private func mapped(_ body: () async throws -> JSONValue) async throws -> JSONValue {
        do {
            return try await body()
        } catch let error as TaquitoBridge.BridgeError {
            if case .javaScript(let message) = error, let known = ChainError.fromBridgeMessage(message) { throw known }
            throw error
        }
    }
}

/// For previews and tests: a pretend Nano with fixed keys.
struct MockLedgerService: LedgerService {
    var connected: [LedgerDevice] = []
    var appOpen = true
    static let sampleDevice = LedgerDevice(id: "4242", name: "Nano S Plus", productID: 0x5011)
    static let rootAddress = Address("tz1LedgerRootMockMockMockMockMockMockMo")

    func devices() async -> [LedgerDevice] { connected }

    func appInfo(deviceID: String) async throws -> LedgerAppInfo {
        guard appOpen else { throw ChainError.ledgerAppNotOpen }
        return LedgerAppInfo(version: "3.0.5", isWallet: true)
    }

    func address(deviceID: String, key: LedgerKey, prompt: Bool) async throws -> (publicKey: String, address: Address) {
        guard appOpen else { throw ChainError.ledgerAppNotOpen }
        let n = key.account ?? 0
        switch key.curve {
        case .ed25519, .bip25519: return ("edpkMockLedger\(n)", Address("tz1Ledger\(key.curve.rawValue)\(n)"))
        case .secp256k1: return ("sppkMockLedger\(n)", Address("tz2Ledger\(n)"))
        case .p256: return ("p2pkMockLedger\(n)", Address("tz3Ledger\(n)"))
        }
    }

    func rootAddress(deviceID: String) async throws -> Address { Self.rootAddress }
}
