import Foundation

/// BLAKE2s-256 (RFC 7693) with the optional 8-byte personalization TzEL's hashes are
/// domain-separated by, over the C implementation in `tzel_blake2s.c` (compiled with -O3 in
/// every configuration, because an address's XMSS auth tree is about 44 million hashes). The
/// protocol itself stays in `TaquitoBridge/src/tzel.js`; `ShieldedTests` checks this against
/// the RFC vector, the bridge and the tzel cross-implementation vectors.
enum Blake2s {
    static let digestLength = 32

    /// The eight personalization bytes.
    struct Personalization: Hashable, Sendable {
        let bytes: [UInt8]

        static let none = Personalization(bytes: [])

        /// Exactly eight ASCII bytes, as the spec writes them (`"mrklSP__"`); `nil` otherwise.
        init?(_ label: String) {
            let bytes = Array(label.utf8)
            guard bytes.count == 8 else { return nil }
            self.bytes = bytes
        }

        private init(bytes: [UInt8]) { self.bytes = bytes }
    }

    /// The 32-byte digest of `message`.
    static func hash(_ message: [UInt8], personalization: Personalization = .none) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: digestLength)
        message.withUnsafeBufferPointer { input in
            out.withUnsafeMutableBufferPointer { output in
                if personalization.bytes.isEmpty {
                    tzel_blake2s(input.baseAddress, input.count, nil, output.baseAddress)
                } else {
                    personalization.bytes.withUnsafeBufferPointer { tzel_blake2s(input.baseAddress, input.count, $0.baseAddress, output.baseAddress) }
                }
            }
        }
        return out
    }
}

/// Hex helpers for the values the shielded code passes around (`Hex` itself is in Micheline.swift).
extension Hex {
    static func encode(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8](); out.reserveCapacity(bytes.count * 2)
        for b in bytes { out.append(digits[Int(b >> 4)]); out.append(digits[Int(b & 15)]) }
        return String(decoding: out, as: UTF8.self)
    }

    static func encode(_ data: Data) -> String { encode([UInt8](data)) }

    /// Lowercase or uppercase hex, even length; `nil` for anything else.
    static func decode(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = [UInt8](); out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let high = nibble(chars[i]), let low = nibble(chars[i + 1]) else { return nil }
            out.append(high << 4 | low)
            i += 2
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: c - 48
        case 97...102: c - 87
        case 65...70: c - 55
        default: nil
        }
    }
}
