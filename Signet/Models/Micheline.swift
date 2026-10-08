import Foundation

/// A strict reader for Micheline's binary encoding (what `PACK` produces after its `05` prefix).
///
/// Used to decide whether a dApp's "message" really is one complete Micheline expression: the
/// bytes must decode as exactly one expression with every declared length satisfied and nothing
/// left over. The bridge's `micheline.js` implements the same rules; keep them in step.
///
/// Encoding, from octez's `micheline_encoding`:
///   00 int (signed zarith)             01 string (u32 length, bytes)
///   02 sequence (u32 length, elements) 0a bytes (u32 length, bytes)
///   03 prim                             04 prim + annots
///   05 prim arg                         06 prim arg + annots
///   07 prim arg arg                     08 prim arg arg + annots
///   09 prim (u32 length, args) + annots
/// Annotations are one u32-length string. Primitive tags are not checked against octez's table.
enum MichelineBinary {
    /// Root depth is zero. Bound recursion before descending into untrusted expressions.
    static let maxDepth = 128

    /// True when `bytes` is exactly one well-formed expression.
    static func isWellFormed(_ bytes: [UInt8]) -> Bool {
        guard let end = try? expression(bytes, at: 0, depth: 0) else { return false }
        return end == bytes.count
    }

    /// True when `hex` is `05` followed by exactly one well-formed expression.
    static func isPackedExpression(hex: String) -> Bool {
        guard let bytes = Hex.bytes(fromHex: hex), bytes.first == 0x05 else { return false }
        return isWellFormed(Array(bytes.dropFirst()))
    }

    private struct Malformed: Error {}

    /// Reads one expression starting at `pos` and returns the position after it.
    private static func expression(_ b: [UInt8], at pos: Int, depth: Int) throws -> Int {
        guard depth <= maxDepth, pos < b.count else { throw Malformed() }
        var p = pos + 1
        switch b[pos] {
        case 0x00:
            // Zarith: continuation bit 7 on every byte, at least one byte.
            guard p < b.count else { throw Malformed() }
            while b[p] & 0x80 != 0 {
                p += 1
                guard p < b.count else { throw Malformed() }
            }
            return p + 1
        case 0x01, 0x0a:
            let length = try u32(b, at: p)
            p += 4
            guard length <= b.count - p else { throw Malformed() }
            return p + length
        case 0x02:
            let length = try u32(b, at: p)
            p += 4
            return try elements(b, from: p, length: length, depth: depth)
        case 0x03: return try prim(b, at: p, args: 0, annots: false, depth: depth)
        case 0x04: return try prim(b, at: p, args: 0, annots: true, depth: depth)
        case 0x05: return try prim(b, at: p, args: 1, annots: false, depth: depth)
        case 0x06: return try prim(b, at: p, args: 1, annots: true, depth: depth)
        case 0x07: return try prim(b, at: p, args: 2, annots: false, depth: depth)
        case 0x08: return try prim(b, at: p, args: 2, annots: true, depth: depth)
        case 0x09:
            guard p < b.count else { throw Malformed() }
            p += 1
            let length = try u32(b, at: p)
            p = try elements(b, from: p + 4, length: length, depth: depth)
            return try annotations(b, at: p)
        default:
            throw Malformed()
        }
    }

    private static func prim(_ b: [UInt8], at pos: Int, args: Int, annots: Bool, depth: Int) throws -> Int {
        guard pos < b.count else { throw Malformed() }
        var p = pos + 1
        for _ in 0..<args { p = try expression(b, at: p, depth: depth + 1) }
        return annots ? try annotations(b, at: p) : p
    }

    /// Expressions filling exactly `length` bytes from `pos`.
    private static func elements(_ b: [UInt8], from pos: Int, length: Int, depth: Int) throws -> Int {
        guard length <= b.count - pos else { throw Malformed() }
        let end = pos + length
        var p = pos
        while p < end { p = try expression(b, at: p, depth: depth + 1) }
        guard p == end else { throw Malformed() }
        return end
    }

    private static func annotations(_ b: [UInt8], at pos: Int) throws -> Int {
        let length = try u32(b, at: pos)
        guard length <= b.count - pos - 4 else { throw Malformed() }
        return pos + 4 + length
    }

    private static func u32(_ b: [UInt8], at pos: Int) throws -> Int {
        guard pos + 4 <= b.count else { throw Malformed() }
        return Int(b[pos]) << 24 | Int(b[pos + 1]) << 16 | Int(b[pos + 2]) << 8 | Int(b[pos + 3])
    }
}

enum Hex {
    static func bytes(fromHex hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
