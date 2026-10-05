import CryptoKit
import Foundation

/// Base58Check as used by Tezos: `base58(prefix + payload + sha256(sha256(prefix + payload))[0..<4])`.
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var zeros = 0
        while zeros < bytes.count, bytes[zeros] == 0 { zeros += 1 }

        var digits: [UInt8] = []  // little-endian base-58 digits
        for byte in bytes[zeros...] {
            var carry = Int(byte)
            for i in digits.indices {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        var result = String(repeating: "1", count: zeros)
        result.reserveCapacity(zeros + digits.count)
        for digit in digits.reversed() {
            result.unicodeScalars.append(UnicodeScalar(alphabet[Int(digit)]))
        }
        return result
    }

    static func checkEncode(prefix: [UInt8], payload: [UInt8]) -> String {
        let body = prefix + payload
        let checksum = Array(SHA256.hash(data: Data(SHA256.hash(data: Data(body)))).prefix(4))
        return encode(body + checksum)
    }
}

/// Byte prefixes that make Tezos base58 strings start with their familiar letters.
enum TezosPrefix {
    static let edsk: [UInt8] = [13, 15, 58, 7]        // Ed25519 32-byte seed
    static let edpk: [UInt8] = [13, 15, 37, 217]
    static let spsk: [UInt8] = [17, 162, 224, 201]
    static let sppk: [UInt8] = [3, 254, 226, 86]
    static let p2sk: [UInt8] = [16, 81, 238, 189]
    static let p2pk: [UInt8] = [3, 178, 139, 127]
    static let blsk: [UInt8] = [3, 150, 192, 40]
    static let blpk: [UInt8] = [6, 149, 135, 204]
}

extension Base58 {
    private static let digitValues: [UInt8: UInt8] = {
        var map: [UInt8: UInt8] = [:]
        for (i, c) in alphabet.enumerated() { map[c] = UInt8(i) }
        return map
    }()

    /// Decodes base58 text to bytes, or `nil` on a bad character.
    static func decode(_ string: String) -> [UInt8]? {
        var zeros = 0
        for c in string.utf8 { if c == UInt8(ascii: "1") { zeros += 1 } else { break } }

        var bytes: [UInt8] = []  // little-endian base-256 digits
        for c in string.utf8.dropFirst(zeros) {
            guard var carry = digitValues[c].map(Int.init) else { return nil }
            for i in bytes.indices {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed()
    }

    /// Decodes and verifies the 4-byte double-SHA256 checksum; returns the payload including prefix.
    static func checkDecode(_ string: String) -> [UInt8]? {
        guard let bytes = decode(string), bytes.count > 4 else { return nil }
        let body = Array(bytes.dropLast(4))
        let checksum = Array(bytes.suffix(4))
        let expected = Array(SHA256.hash(data: Data(SHA256.hash(data: Data(body)))).prefix(4))
        return checksum == expected ? body : nil
    }
}
