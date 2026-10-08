import Foundation

/// What a pasted secret key turned out to be.
struct InspectedSecretKey: Equatable, Sendable {
    /// An octez-encrypted key (edesk…) that needs its password before anything is known.
    let needsPassphrase: Bool
    let isEncrypted: Bool
    let publicKey: String?
    let address: Address?
    /// The key as it should be stored: the pasted key, or an ed25519 seed when a 64-byte key was pasted.
    let secretKey: String?
}

struct MnemonicCheck: Equatable, Sendable {
    let isValid: Bool
    let wordCount: Int
    let unknownWords: [String]
}

/// Derivation curves a recovery phrase can produce keys on (Taquito's names).
enum MnemonicCurve: String, CaseIterable, Identifiable, Sendable {
    case ed25519, secp256k1, p256, bip25519
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ed25519: "Ed25519 (tz1) — most wallets"
        case .secp256k1: "secp256k1 (tz2)"
        case .p256: "P-256 (tz3)"
        case .bip25519: "BIP32-Ed25519 (tz1) — Ledger style"
        }
    }
    var scheme: AddressScheme {
        switch self {
        case .ed25519, .bip25519: .tz1
        case .secp256k1: .tz2
        case .p256: .tz3
        }
    }
}

/// Turns pasted secrets into key material, through the bridge (Taquito's own derivation).
protocol KeyImporter: Sendable {
    func inspect(secretKey: String, passphrase: String?) async throws -> InspectedSecretKey
    func check(mnemonic: String) async throws -> MnemonicCheck
    func key(fromMnemonic mnemonic: String, passphrase: String?, derivationPath: String, curve: MnemonicCurve) async throws -> KeyMaterial
    /// The old fundraiser / non-HD derivation (email + password + phrase).
    func key(fromFundraiserEmail email: String, password: String, mnemonic: String) async throws -> KeyMaterial
    /// The clear key behind an octez-encrypted one (for Export).
    func decrypt(secretKey: String, passphrase: String) async throws -> String
}

struct BridgeKeyImporter: KeyImporter {
    let bridge: TaquitoBridge

    init(bridge: TaquitoBridge = .shared) { self.bridge = bridge }

    static let defaultDerivationPath = "44'/1729'/0'/0'"

    func inspect(secretKey: String, passphrase: String?) async throws -> InspectedSecretKey {
        let r: JSONValue
        do {
            r = try await bridge.call("inspectSecretKey", [secretKey, passphrase ?? ""])
        } catch let error as TaquitoBridge.BridgeError {
            if case .javaScript(let message) = error, let known = ChainError.fromBridgeMessage(message) { throw known }
            throw error
        }
        return InspectedSecretKey(
            needsPassphrase: r["needsPassphrase"]?.boolValue ?? false,
            isEncrypted: r["encrypted"]?.boolValue ?? false,
            publicKey: r["publicKey"]?.stringValue,
            address: r["address"]?.stringValue.map(Address.init),
            secretKey: r["secretKey"]?.stringValue
        )
    }

    func check(mnemonic: String) async throws -> MnemonicCheck {
        let r = try await bridge.call("validateMnemonic", [mnemonic])
        return MnemonicCheck(isValid: r["valid"]?.boolValue ?? false, wordCount: Int(r["wordCount"]?.doubleValue ?? 0),
                             unknownWords: r["unknownWords"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }

    func key(fromMnemonic mnemonic: String, passphrase: String?, derivationPath: String, curve: MnemonicCurve) async throws -> KeyMaterial {
        try Self.material(curve.scheme, try await bridge.call("keyFromMnemonic", [mnemonic, passphrase ?? "", derivationPath, curve.rawValue]))
    }

    func key(fromFundraiserEmail email: String, password: String, mnemonic: String) async throws -> KeyMaterial {
        try Self.material(.tz1, try await bridge.call("keyFromFundraiser", [email, password, mnemonic]))
    }

    func decrypt(secretKey: String, passphrase: String) async throws -> String {
        do {
            let r = try await bridge.call("decryptSecretKey", [secretKey, passphrase])
            guard let key = r["secretKey"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no key returned") }
            return key
        } catch let error as TaquitoBridge.BridgeError {
            if case .javaScript(let message) = error, let known = ChainError.fromBridgeMessage(message) { throw known }
            throw error
        }
    }

    private static func material(_ scheme: AddressScheme, _ r: JSONValue) throws -> KeyMaterial {
        guard let sk = r["secretKey"]?.stringValue, let pk = r["publicKey"]?.stringValue, let address = r["address"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected key payload")
        }
        return KeyMaterial(scheme: Address(address).scheme ?? scheme, publicKey: pk, address: address, secretKey: sk)
    }
}

/// For tests and previews: fixed answers, no bridge.
struct MockKeyImporter: KeyImporter {
    func inspect(secretKey: String, passphrase: String?) async throws -> InspectedSecretKey {
        if secretKey.hasPrefix("edesk") {
            if passphrase == nil { return InspectedSecretKey(needsPassphrase: true, isEncrypted: true, publicKey: nil, address: nil, secretKey: nil) }
            guard passphrase == "correct horse" else { throw ChainError.wrongPassphrase }
            return InspectedSecretKey(needsPassphrase: false, isEncrypted: true, publicKey: "edpkEnc", address: Address("tz1EncMockMockMockMockMockMockMockMo"), secretKey: secretKey)
        }
        guard secretKey.hasPrefix("edsk") else { throw TaquitoBridge.BridgeError.javaScript("Invalid secret key") }
        return InspectedSecretKey(needsPassphrase: false, isEncrypted: false, publicKey: "edpkClear", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), secretKey: secretKey)
    }
    func check(mnemonic: String) async throws -> MnemonicCheck {
        let words = mnemonic.split(separator: " ")
        return MnemonicCheck(isValid: [12, 15, 18, 21, 24].contains(words.count), wordCount: words.count, unknownWords: [])
    }
    func key(fromMnemonic mnemonic: String, passphrase: String?, derivationPath: String, curve: MnemonicCurve) async throws -> KeyMaterial {
        KeyMaterial(scheme: curve.scheme, publicKey: "edpkMnemonic", address: "tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5", secretKey: "edskMnemonic")
    }
    func key(fromFundraiserEmail email: String, password: String, mnemonic: String) async throws -> KeyMaterial {
        KeyMaterial(scheme: .tz1, publicKey: "edpkFund", address: "tz1FundMockMockMockMockMockMockMockMo", secretKey: "edskFund")
    }
    func decrypt(secretKey: String, passphrase: String) async throws -> String {
        guard passphrase == "correct horse" else { throw ChainError.wrongPassphrase }
        return "edskDECRYPTED"
    }
}
