#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// A freshly made Enclave key: the wrapped blob to keep and its public key (33 bytes, compressed).
struct EnclaveKeyPair: Sendable {
    let key: EnclaveKey
    let publicKey: Data
}

enum EnclaveError: LocalizedError, Equatable {
    case unavailable
    case notOnThisMac
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "This Mac has no Secure Enclave."
        case .notOnThisMac: "This key is not in this Mac's Secure Enclave. It was made on another Mac, or the Enclave has been reset."
        case .cancelled: "Signing with the Secure Enclave was cancelled."
        case .failed(let detail): "The Secure Enclave could not sign: \(detail)"
        }
    }
}

/// Keys made and used inside the Secure Enclave (tz3 only: the Enclave holds P-256 and nothing
/// else). `SecureEnclaveKeys` is the real one; `SoftwareEnclaveKeys` stands in for tests and
/// previews, where there is no Enclave and nobody to answer a prompt.
protocol EnclaveKeyService: Sendable {
    var isAvailable: Bool { get }
    /// Makes a key inside the Enclave. Nothing is asked of the user; using it will.
    func create() throws -> EnclaveKeyPair
    /// Whether this machine's Enclave can load the key at all (no prompt).
    func isUsable(_ key: EnclaveKey) -> Bool
    /// Signs a 32-byte digest as it is (no further hashing) after the user authenticates;
    /// `reason` completes the system's "Signet is trying to …". Returns raw r‖s, low-S.
    func sign(digest: Data, with key: EnclaveKey, reason: String) async throws -> Data
}

/// A digest computed elsewhere (Tezos signs Blake2b, which CryptoKit does not have), handed to
/// CryptoKit's ECDSA as the value to sign.
struct RawDigest: Digest {
    static var byteCount: Int { 32 }
    let bytes: [UInt8]

    init(_ data: Data) { bytes = Array(data) }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { bytes.makeIterator() }
    static func == (a: RawDigest, b: RawDigest) -> Bool { a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
    var description: String { "RawDigest" }
}

enum P256Signature {
    private static let order: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51,
    ]
    private static let halfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xde, 0x73, 0x7d, 0x56, 0xd3, 0x8b, 0xcf, 0x42, 0x79, 0xdc, 0xe5, 0x61, 0x7e, 0x31, 0x92, 0xa8,
    ]

    /// r‖s with s in the lower half of the group order. Both forms verify; the Enclave returns
    /// either, and the low one is the form every verifier accepts.
    static func lowS(_ raw: Data) -> Data {
        guard raw.count == 64 else { return raw }
        let s = Array(raw.suffix(32))
        guard s.lexicographicallyPrecedes(halfOrder) == false, s != halfOrder else { return raw }
        var out = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        for i in stride(from: 31, through: 0, by: -1) {
            let d = Int(order[i]) - Int(s[i]) - borrow
            out[i] = UInt8(truncatingIfNeeded: d < 0 ? d + 256 : d)
            borrow = d < 0 ? 1 : 0
        }
        return raw.prefix(32) + Data(out)
    }

    static func isLowS(_ raw: Data) -> Bool { lowS(raw) == raw }
}

/// For tests and previews: ordinary P-256 keys in memory behind the same interface, the "blob"
/// being the private key. Never selected by the app itself.
struct SoftwareEnclaveKeys: EnclaveKeyService {
    var isAvailable = true

    func create() throws -> EnclaveKeyPair {
        guard isAvailable else { throw EnclaveError.unavailable }
        let key = P256.Signing.PrivateKey()
        return EnclaveKeyPair(key: EnclaveKey(blob: key.rawRepresentation), publicKey: key.publicKey.compressedRepresentation)
    }

    func isUsable(_ key: EnclaveKey) -> Bool { (try? P256.Signing.PrivateKey(rawRepresentation: key.blob)) != nil }

    func sign(digest: Data, with key: EnclaveKey, reason: String) async throws -> Data {
        guard digest.count == 32 else { throw EnclaveError.failed("the digest is not 32 bytes") }
        guard let secret = try? P256.Signing.PrivateKey(rawRepresentation: key.blob) else { throw EnclaveError.notOnThisMac }
        return P256Signature.lowS(try secret.signature(for: RawDigest(digest)).rawRepresentation)
    }
}

/// Where there is no Enclave to talk to (Linux, or the type simply missing).
struct UnavailableEnclaveKeys: EnclaveKeyService {
    var isAvailable: Bool { false }
    func create() throws -> EnclaveKeyPair { throw EnclaveError.unavailable }
    func isUsable(_ key: EnclaveKey) -> Bool { false }
    func sign(digest: Data, with key: EnclaveKey, reason: String) async throws -> Data { throw EnclaveError.unavailable }
}

#if canImport(CryptoKit) && canImport(LocalAuthentication)
/// The real Enclave, through CryptoKit. The wrapped key is ours to store (no Keychain item),
/// so this needs no keychain entitlement or provisioning profile and works in ad-hoc builds.
struct SecureEnclaveKeys: EnclaveKeyService {
    /// Off only for tests that exercise the hardware with nobody to answer a prompt.
    var requiresUserPresence = true

    var isAvailable: Bool { SecureEnclave.isAvailable }

    func create() throws -> EnclaveKeyPair {
        guard isAvailable else { throw EnclaveError.unavailable }
        do {
            let key: SecureEnclave.P256.Signing.PrivateKey
            if requiresUserPresence {
                key = try Self.guardedKey()
            } else {
                key = try SecureEnclave.P256.Signing.PrivateKey()
            }
            return EnclaveKeyPair(key: EnclaveKey(blob: key.dataRepresentation), publicKey: key.publicKey.compressedRepresentation)
        } catch {
            throw EnclaveError.failed(error.localizedDescription)
        }
    }

    /// A key every use of which needs Touch ID or the login password, checked by the Enclave.
    /// "When unlocked" is preferred; some sessions refuse to make such a key (-25308), and
    /// there "after first unlock" is used: the presence check on every signature is the same.
    private static func guardedKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        var lastError: Error = EnclaveError.unavailable
        for protection in [kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] {
            guard let access = SecAccessControlCreateWithFlags(nil, protection, [.privateKeyUsage, .userPresence], nil) else { continue }
            do { return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access) } catch { lastError = error }
        }
        throw lastError
    }

    func isUsable(_ key: EnclaveKey) -> Bool {
        isAvailable && (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: key.blob)) != nil
    }

    func sign(digest: Data, with key: EnclaveKey, reason: String) async throws -> Data {
        guard digest.count == 32 else { throw EnclaveError.failed("the digest is not 32 bytes") }
        guard isAvailable else { throw EnclaveError.unavailable }
        let blob = key.blob
        return try await withCheckedThrowingContinuation { continuation in
            // The call blocks while the system's prompt is up, so it gets a thread of its own.
            DispatchQueue.global(qos: .userInitiated).async {
                // A fresh context each time: one authentication, one signature.
                let context = LAContext()
                context.localizedReason = reason
                context.touchIDAuthenticationAllowableReuseDuration = 0
                let secret: SecureEnclave.P256.Signing.PrivateKey
                do {
                    secret = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
                } catch {
                    continuation.resume(throwing: EnclaveError.notOnThisMac)
                    return
                }
                do {
                    let signature = try secret.signature(for: RawDigest(digest))
                    continuation.resume(returning: P256Signature.lowS(signature.rawRepresentation))
                } catch {
                    continuation.resume(throwing: Self.mapped(error))
                }
            }
        }
    }

    private static func mapped(_ error: Error) -> EnclaveError {
        let ns = error as NSError
        let cancelled = (ns.domain == LAError.errorDomain && [LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue].contains(ns.code))
            || ns.code == Int(errSecUserCanceled)
        return cancelled ? .cancelled : .failed(ns.localizedDescription)
    }
}
#endif

enum EnclaveKeys {
    /// The Enclave of the machine we are running on.
    static var platform: any EnclaveKeyService {
        #if canImport(CryptoKit) && canImport(LocalAuthentication)
        SecureEnclaveKeys()
        #else
        UnavailableEnclaveKeys()
        #endif
    }
}
