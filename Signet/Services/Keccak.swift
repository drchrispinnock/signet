import Foundation

/// Keccak-256 as Ethereum uses it (the original Keccak padding, not FIPS SHA3-256), for the
/// account's alias on Etherlink's EVM side: the first 20 bytes of the hash of the base58 address
/// string (`EtherlinkAlias`). CryptoKit has no Keccak, and the alias should be shown without a
/// round trip through the bridge.
enum Keccak {
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    private static let rotations: [Int] = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
    private static let piLanes: [Int] = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

    /// Keccak-256 digest (32 bytes) of `message`.
    static func hash256(_ message: Data) -> Data {
        let rate = 136
        var state = [UInt64](repeating: 0, count: 25)
        var padded = [UInt8](message)
        padded.append(0x01)
        while padded.count % rate != 0 { padded.append(0) }
        padded[padded.count - 1] |= 0x80
        for block in stride(from: 0, to: padded.count, by: rate) {
            for lane in 0..<(rate / 8) {
                var word: UInt64 = 0
                for byte in 0..<8 { word |= UInt64(padded[block + lane * 8 + byte]) << (8 * UInt64(byte)) }
                state[lane] ^= word
            }
            permute(&state)
        }
        var out = Data(count: 32)
        for lane in 0..<4 {
            for byte in 0..<8 { out[lane * 8 + byte] = UInt8(truncatingIfNeeded: state[lane] >> (8 * UInt64(byte))) }
        }
        return out
    }

    private static func permute(_ a: inout [UInt64]) {
        var b = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            // θ
            for x in 0..<5 { b[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            for x in 0..<5 {
                let t = b[(x + 4) % 5] ^ rotl(b[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) { a[x + y] ^= t }
            }
            // ρ and π
            var current = a[1]
            for i in 0..<24 {
                let j = piLanes[i]
                let next = a[j]
                a[j] = rotl(current, rotations[i])
                current = next
            }
            // χ
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 { b[x] = a[y + x] }
                for x in 0..<5 { a[y + x] = b[x] ^ (~b[(x + 1) % 5] & b[(x + 2) % 5]) }
            }
            // ι
            a[0] ^= roundConstants[round]
        }
    }

    private static func rotl(_ value: UInt64, _ n: Int) -> UInt64 { (value << UInt64(n)) | (value >> UInt64(64 - n)) }
}

/// The account's address on Etherlink's EVM side, derived from its Tezos address (Tezos X
/// "accounts and aliases"), as the EVM node's `tez_getTezosEthereumAddress` and the gateway's
/// `resolveAddress` view answer. Tez sent to it on the EVM side are forwarded to the account on
/// the Michelson interface.
///
/// **Etherlink 8.0 (RFC-26051, "rescue accounts v1")** made the alias of a tz1, tz2 or tz3
/// account recoverable: it is the CREATE2 address, through the Safe singleton factory (at the
/// same address on every EVM chain), of an EIP-1167 minimal proxy to the account type's
/// rescue implementation with the 20-byte public key hash appended, so tez or tokens sent to it
/// by mistake on another EVM chain can be recovered with the Tezos key:
/// `keccak256(0xff ‖ factory ‖ salt ‖ keccak256(initcode))[12...]`. Other addresses (tz4, tz5,
/// KT1) keep the first 20 bytes of Keccak-256 over the base58 address string, which was the
/// alias of every address before 8.0 (`legacyAddress`). The constants are octez.js's
/// (`@tezos-x/octez.js-utils` `alias.js`, 25.1.0-rc.1), and the results match what Previewnet's
/// gateway answered for tz1, tz2, tz3 and tz4 (`KeccakTests`).
enum EtherlinkAlias {
    /// Whether Receive offers the EVM-side address and "Link to Etherlink". On: the derivation
    /// below is Etherlink 8.0's, and a network still on the old kernel reports
    /// `EtherlinkAliasStatus.awaitingUpgrade` rather than an address, so Receive shows a note
    /// there and linking is refused; nothing stale can be shown or linked.
    static let isOffered = true

    /// Safe singleton factory.
    static let factory = bytes("914d7fec6aac8cd542e72bca78b30650d45643d7")
    /// `keccak256("tezosx.rescue.v1")`.
    static let salt = bytes("9b8bb449a3d23b110d8c46424ba9b40748ac28bc7b99b7422a272950e17bb1d8")
    /// Refuses to deploy where the guard address has code (Etherlink itself), then copies out the runtime.
    static let clonePrefix = bytes("733822d2fe3dce6ce4f4c7f274e2415fa3fae66c3e3b15601e57600080fd5b604180602a6000396000f3")
    static let cloneRuntimeHead = bytes("363d3d373d3d3d363d73")
    static let cloneRuntimeTail = bytes("5af43d82803e903d91602b57fd5bf3")
    /// The rescue implementation for each account type.
    static func implementation(for scheme: AddressScheme) -> Data? {
        switch scheme {
        case .tz1: bytes("fee60e905d91905df9cd6bf8153976e9d77d5051")
        case .tz2: bytes("47c81e55f51344d80a8e85c2add86257b51ea3d2")
        case .tz3: bytes("894b62c61b208184b80fd72803811ba35d818112")
        default: nil
        }
    }

    /// The alias as Etherlink 8.0 derives it, lowercase `0x` hex.
    static func address(for account: Address) -> String {
        guard let scheme = account.scheme, let implementation = implementation(for: scheme),
              let decoded = Base58.checkDecode(account.value), decoded.count == 23
        else { return legacyAddress(for: account) }
        let pkh = Data(decoded.suffix(20))
        let initcode = clonePrefix + cloneRuntimeHead + implementation + cloneRuntimeTail + pkh
        let preimage = Data([0xff]) + factory + salt + Keccak.hash256(initcode)
        return hex(Keccak.hash256(preimage).suffix(20))
    }

    /// The alias before Etherlink 8.0 (and still for tz4, tz5 and KT1): the first 20 bytes of
    /// Keccak-256 over the base58 address. Kept to recognise a node that has not upgraded.
    static func legacyAddress(for account: Address) -> String {
        hex(Keccak.hash256(Data(account.value.utf8)).prefix(20))
    }

    private static func hex(_ data: Data) -> String { "0x" + data.map { String(format: "%02x", $0) }.joined() }

    private static func bytes(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
