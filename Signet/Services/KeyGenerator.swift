import CryptoKit
import Foundation

/// Generates key pairs for each address scheme.
///
/// tz1 (Ed25519) and tz3 (P-256) are generated with CryptoKit and encoded in Swift, so those
/// secrets never enter the JavaScript runtime; only the public key is sent to the bridge to
/// derive the address. tz2 (secp256k1), tz4 (BLS12-381) and tz5 (ML-DSA-44) have no CryptoKit
/// support, so they are generated inside the Taquito bridge with the libraries Taquito signs with.
struct KeyGenerator: Sendable {
    enum KeyError: LocalizedError {
        case unsupportedScheme(AddressScheme)
        case badBridgeResponse(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedScheme(let scheme): "\(scheme.rawValue) keys cannot be created yet."
            case .badBridgeResponse(let detail): "Unexpected response from the Taquito bridge: \(detail)"
            }
        }
    }

    let bridge: TaquitoBridge

    init(bridge: TaquitoBridge = .shared) {
        self.bridge = bridge
    }

    func generate(scheme: AddressScheme) async throws -> KeyMaterial {
        switch scheme {
        case .tz1:
            let key = Curve25519.Signing.PrivateKey()
            let secret = Base58.checkEncode(prefix: TezosPrefix.edsk, payload: Array(key.rawRepresentation))
            let publicKey = Base58.checkEncode(prefix: TezosPrefix.edpk, payload: Array(key.publicKey.rawRepresentation))
            return KeyMaterial(scheme: .tz1, publicKey: publicKey, address: try await address(for: publicKey), secretKey: secret)

        case .tz3:
            let key = P256.Signing.PrivateKey()
            let secret = Base58.checkEncode(prefix: TezosPrefix.p2sk, payload: Array(key.rawRepresentation))
            let publicKey = Base58.checkEncode(prefix: TezosPrefix.p2pk, payload: Array(key.publicKey.compressedRepresentation))
            return KeyMaterial(scheme: .tz3, publicKey: publicKey, address: try await address(for: publicKey), secretKey: secret)

        case .tz2, .tz4, .tz5:
            // No CryptoKit support for secp256k1, BLS12-381 or ML-DSA-44: the bridge generates these
            // with the same libraries Taquito signs with.
            let result = try await bridge.call("generateKeyPair", [scheme.rawValue])
            guard let secret = result["secretKey"]?.stringValue,
                  let publicKey = result["publicKey"]?.stringValue,
                  let address = result["address"]?.stringValue
            else { throw KeyError.badBridgeResponse(String(describing: result)) }
            return KeyMaterial(scheme: scheme, publicKey: publicKey, address: address, secretKey: secret)

        case .tz6:
            throw KeyError.unsupportedScheme(scheme)
        }
    }

    /// Encrypts a clear-text secret key with `passphrase` in octez-client's format (edesk/spesk/p2esk/BLesk).
    func encrypt(secretKey: String, passphrase: String) async throws -> String {
        let result = try await bridge.call("encryptSecretKey", [secretKey, passphrase])
        guard let encrypted = result.stringValue, KeyKind.encryptedKeyPrefixes.contains(String(encrypted.prefix(5))) else {
            throw KeyError.badBridgeResponse(String(describing: result))
        }
        return encrypted
    }

    /// Derives the tz address for a base58 public key. Public data only.
    func address(for publicKey: String) async throws -> String {
        let result = try await bridge.call("addressFromPublicKey", [publicKey])
        guard let address = result.stringValue else {
            throw KeyError.badBridgeResponse(String(describing: result))
        }
        return address
    }
}
