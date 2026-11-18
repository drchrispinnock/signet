import Foundation

/// Connect Remote Signer: an account whose key octez-signer holds, reached over HTTP, HTTPS or
/// TCP. Like a Ledger account, Signet keeps only the address, the public key and where the
/// key is; the alias is written in octez-client's form, so octez-client can use it too.
extension WalletViewModel {
    /// What the signer says about one of its keys, checked here.
    struct RemoteSignerCheck: Equatable, Sendable {
        let signer: RemoteSignerLocator
        let publicKey: String
        /// `false` when the signer was started with `--require-authentication`.
        let acceptsUnauthenticated: Bool
    }

    /// The keys a signer lists, when it lists them (octez-signer 22 and later).
    func remoteSignerKeys(at signer: RemoteSignerLocator) async throws -> [Address] {
        try await remoteSigners.knownKeys(at: signer)
    }

    /// Asks the signer for the key's public key and checks it is the address's own: the address
    /// is derived from the key here, never taken from the signer.
    func checkRemoteSigner(_ signer: RemoteSignerLocator) async throws -> RemoteSignerCheck {
        guard signer.address.isImplicitAccount else { throw WalletError.invalidAddress }
        let publicKey = try await remoteSigners.publicKey(at: signer)
        let derived = try await address(forScannedPublicKey: publicKey)
        guard derived == signer.address else { throw RemoteSignerError.keyMismatch(expected: signer.address, found: derived) }
        let authorized = try await remoteSigners.authorizedKeys(at: signer)
        return RemoteSignerCheck(signer: signer, publicKey: publicKey, acceptsUnauthenticated: authorized == nil)
    }
}
