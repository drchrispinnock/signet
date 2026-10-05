import Foundation

/// A freshly generated key pair in Tezos base58 form. The secret key is only ever held in
/// memory long enough to be written to the secret key store.
struct KeyMaterial: Sendable {
    let scheme: AddressScheme
    /// Base58 public key, e.g. `edpk...`, `sppk...`, `p2pk...`, `BLpk...`.
    let publicKey: String
    /// Base58 address derived from the public key, e.g. `tz1...`.
    let address: String
    /// Base58 secret key, e.g. `edsk...` (seed form), `spsk...`, `p2sk...`, `BLsk...`.
    let secretKey: String
}
