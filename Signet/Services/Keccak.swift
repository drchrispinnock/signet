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
/// "accounts and aliases"): the first 20 bytes of Keccak-256 over the base58 address string,
/// which is what the EVM node's `tez_getTezosEthereumAddress` answers. Tez sent to it on the EVM
/// side are forwarded to the account on the Michelson interface.
enum EtherlinkAlias {
    static func address(for account: Address) -> String {
        "0x" + Keccak.hash256(Data(account.value.utf8)).prefix(20).map { String(format: "%02x", $0) }.joined()
    }
}
