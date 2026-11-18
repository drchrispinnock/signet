#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Blockchain Commons' Uniform Resources (BCR-2020-005), as AirGap Vault and Wallet speak them:
/// `ur:<type>/<bytewords>` for a message that fits one QR code, and `ur:<type>/<n>-<m>/<bytewords>`
/// for the frames of an animated one, whose parts after the first `m` are fountain-coded mixes
/// of the fragments. Only what Signet needs is here: the `bytes` type, minimal Bytewords, the
/// fountain decoder, and an encoder that cycles the pure fragments (which any decoder accepts).
enum UniformResource {
    static let scheme = "ur:"
    /// A message longer than this is not something Signet ever needs to read.
    static let maximumMessageLength = 256 * 1024
    static let maximumParts = 1024

    enum DecodeError: Error, Equatable {
        case notAUR, unsupportedType, badBytewords, badChecksum, badPart, tooLarge, mismatchedParts
    }

    // MARK: Bytewords

    private static let words: [String] = {
        let all = Array("ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcityclawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedgeepicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirlglowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoirisironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaflegsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednewsnextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramprealredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxitenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwandwarmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom")
        return stride(from: 0, to: all.count, by: 4).map { String(all[$0..<$0 + 4]) }
    }()

    /// Minimal Bytewords: each byte is the first and last letter of its word.
    private static let minimal: [String] = words.map { "\($0.first!)\($0.last!)" }
    private static let minimalValues: [String: UInt8] = Dictionary(uniqueKeysWithValues: minimal.enumerated().map { ($1, UInt8($0)) })

    /// Bytes plus their CRC-32, as minimal Bytewords.
    static func bytewords(_ data: [UInt8]) -> String {
        (data + bigEndian(CRC32.checksum(data))).map { minimal[Int($0)] }.joined()
    }

    /// The bytes of minimal Bytewords whose trailing CRC-32 checks out.
    static func bytes(fromBytewords text: String) throws -> [UInt8] {
        let letters = Array(text.lowercased())
        guard letters.count % 2 == 0, letters.count >= 10 else { throw DecodeError.badBytewords }
        var out: [UInt8] = []
        out.reserveCapacity(letters.count / 2)
        for i in stride(from: 0, to: letters.count, by: 2) {
            guard let value = minimalValues[String(letters[i...i + 1])] else { throw DecodeError.badBytewords }
            out.append(value)
        }
        let body = Array(out.dropLast(4))
        guard bigEndian(CRC32.checksum(body)) == Array(out.suffix(4)) else { throw DecodeError.badChecksum }
        return body
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }

    // MARK: Parts

    /// One scanned QR code of a UR.
    struct Part: Equatable, Sendable {
        let type: String
        /// `nil` for a single-part UR, whose `body` is then the whole message.
        let sequence: (number: Int, count: Int)?
        let body: [UInt8]

        static func == (a: Part, b: Part) -> Bool {
            a.type == b.type && a.sequence?.number == b.sequence?.number && a.sequence?.count == b.sequence?.count && a.body == b.body
        }

        init(text: String) throws {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix(UniformResource.scheme) else { throw DecodeError.notAUR }
            let components = trimmed.dropFirst(UniformResource.scheme.count).lowercased().split(separator: "/", omittingEmptySubsequences: false)
            guard (2...3).contains(components.count) else { throw DecodeError.notAUR }
            type = String(components[0])
            guard type == "bytes" else { throw DecodeError.unsupportedType }
            if components.count == 3 {
                let numbers = components[1].split(separator: "-", omittingEmptySubsequences: false)
                guard numbers.count == 2, let number = Int(numbers[0]), let count = Int(numbers[1]),
                      number >= 1, (1...UniformResource.maximumParts).contains(count)
                else { throw DecodeError.badPart }
                sequence = (number, count)
            } else {
                sequence = nil
            }
            guard components.last!.count <= 2 * (UniformResource.maximumMessageLength + 64) else { throw DecodeError.tooLarge }
            body = try UniformResource.bytes(fromBytewords: String(components.last!))
        }
    }

    /// A fountain-coded part: which fragments it mixes and their XOR.
    struct FountainPart: Sendable {
        let number: Int
        let count: Int
        let messageLength: Int
        let checksum: UInt32
        let fragment: [UInt8]

        init(number: Int, count: Int, messageLength: Int, checksum: UInt32, fragment: [UInt8]) {
            self.number = number
            self.count = count
            self.messageLength = messageLength
            self.checksum = checksum
            self.fragment = fragment
        }

        /// The CBOR array `[seqNum, seqLen, messageLen, checksum, fragment]`.
        init(cbor bytes: [UInt8]) throws {
            guard case .array(let items) = try CBOR.decode(bytes), items.count == 5,
                  case .unsigned(let number) = items[0], case .unsigned(let count) = items[1],
                  case .unsigned(let length) = items[2], case .unsigned(let checksum) = items[3],
                  case .bytes(let fragment) = items[4],
                  number >= 1, number <= UInt64(Int32.max), (1...UInt64(UniformResource.maximumParts)).contains(count),
                  length >= 1, length <= UInt64(UniformResource.maximumMessageLength), checksum <= UInt64(UInt32.max),
                  !fragment.isEmpty, fragment.count * Int(count) >= Int(length)
            else { throw DecodeError.badPart }
            self.init(number: Int(number), count: Int(count), messageLength: Int(length), checksum: UInt32(checksum), fragment: fragment)
        }

        var cbor: [UInt8] {
            CBOR.array([.unsigned(UInt64(number)), .unsigned(UInt64(count)), .unsigned(UInt64(messageLength)), .unsigned(UInt64(checksum)), .bytes(fragment)]).encoded
        }
    }

    // MARK: Encoding

    /// The QR texts that carry `message` (raw bytes, wrapped here as a CBOR byte string), upper
    /// case for QR's alphanumeric mode: one single-part UR when it fits `maximumFragment`
    /// bytes, else the pure fragments `1-m … m-m`, to be shown in a loop.
    static func encode(_ message: [UInt8], maximumFragment: Int) -> [String] {
        let cbor = CBOR.bytes(message).encoded
        if cbor.count <= maximumFragment {
            return ["UR:BYTES/" + bytewords(cbor).uppercased()]
        }
        let count = (cbor.count + maximumFragment - 1) / maximumFragment
        let length = (cbor.count + count - 1) / count
        let padded = cbor + [UInt8](repeating: 0, count: length * count - cbor.count)
        let checksum = CRC32.checksum(cbor)
        return (1...count).map { number in
            let fragment = Array(padded[(number - 1) * length..<number * length])
            let part = FountainPart(number: number, count: count, messageLength: cbor.count, checksum: checksum, fragment: fragment)
            return "UR:BYTES/\(number)-\(count)/" + bytewords(part.cbor).uppercased()
        }
    }

    // MARK: Fountain codes

    /// The fragment indexes part `number` mixes: itself for the first `count`, then a degree and
    /// a shuffle drawn from Xoshiro256** seeded with SHA-256(number ‖ checksum), as the
    /// reference implementations do.
    static func fragmentIndexes(number: Int, count: Int, checksum: UInt32) -> [Int] {
        if number <= count { return [number - 1] }
        var rng = Xoshiro256(seed: Array(SHA256.hash(data: Data(bigEndian(UInt32(truncatingIfNeeded: number)) + bigEndian(checksum)))))
        let sampler = AliasSampler(probabilities: (1...count).map { 1 / Double($0) })
        let degree = sampler.next(&rng) + 1
        var remaining = Array(0..<count)
        var shuffled: [Int] = []
        while !remaining.isEmpty {
            shuffled.append(remaining.remove(at: rng.nextInt(0, remaining.count - 1)))
        }
        return Array(shuffled.prefix(degree))
    }

    struct Xoshiro256 {
        private var s: [UInt64]

        init(seed: [UInt8]) {
            s = (0..<4).map { i in seed[(i * 8)..<(i * 8 + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        }

        private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

        mutating func next() -> UInt64 {
            let result = Self.rotl(s[1] &* 5, 7) &* 9
            let t = s[1] << 17
            s[2] ^= s[0]
            s[3] ^= s[1]
            s[1] ^= s[2]
            s[0] ^= s[3]
            s[2] ^= t
            s[3] = Self.rotl(s[3], 45)
            return result
        }

        mutating func nextDouble() -> Double { Double(next()) / 18_446_744_073_709_551_616.0 }

        mutating func nextInt(_ low: Int, _ high: Int) -> Int {
            Int((nextDouble() * Double(high - low + 1)).rounded(.down)) + low
        }
    }

    /// Vose's alias method, laid out exactly as the reference sampler builds its tables.
    struct AliasSampler {
        private var probabilities: [Double]
        private var aliases: [Int]

        init(probabilities p: [Double]) {
            let n = p.count
            let sum = p.reduce(0, +)
            var scaled = p.map { $0 * Double(n) / sum }
            probabilities = [Double](repeating: 0, count: n)
            aliases = [Int](repeating: 0, count: n)
            var small: [Int] = []
            var large: [Int] = []
            for i in stride(from: n - 1, through: 0, by: -1) {
                if scaled[i] < 1 { small.append(i) } else { large.append(i) }
            }
            while let less = small.last, let more = large.last {
                small.removeLast()
                large.removeLast()
                probabilities[less] = scaled[less]
                aliases[less] = more
                scaled[more] = (scaled[more] + scaled[less]) - 1
                if scaled[more] < 1 { small.append(more) } else { large.append(more) }
            }
            while let i = large.popLast() { probabilities[i] = 1 }
            while let i = small.popLast() { probabilities[i] = 1 }
        }

        func next(_ rng: inout Xoshiro256) -> Int {
            let column = Int((rng.nextDouble() * Double(probabilities.count)).rounded(.down))
            return rng.nextDouble() < probabilities[column] ? column : aliases[column]
        }
    }

    /// Collects the frames of a UR in any order, mixed parts included, until the message is whole.
    struct Decoder: Sendable {
        private var count = 0
        private var messageLength = 0
        private var checksum: UInt32 = 0
        private var fragmentLength = 0
        private var simple: [Int: [UInt8]] = [:]
        private var mixed: [(indexes: Set<Int>, fragment: [UInt8])] = []
        private var seenNumbers: Set<Int> = []
        private(set) var message: [UInt8]?

        enum Outcome: Equatable, Sendable {
            case needMore
            /// The UR's payload: for `bytes`, the CBOR byte string's contents.
            case complete([UInt8])
        }

        var isEmpty: Bool { count == 0 }
        var expectedParts: Int { count }
        var receivedFragments: Int { simple.count }
        /// 0 to 1, by fragments recovered so far.
        var progress: Double { count == 0 ? 0 : Double(simple.count) / Double(count) }

        /// Takes one scanned part. A part of another message starts a new collection.
        mutating func receive(_ part: Part) throws -> Outcome {
            guard let sequence = part.sequence else {
                self = Decoder()
                return .complete(try Self.payload(of: part.body))
            }
            let fountain = try FountainPart(cbor: part.body)
            guard fountain.number == sequence.number, fountain.count == sequence.count else { throw DecodeError.badPart }
            if fountain.count != count || fountain.messageLength != messageLength || fountain.checksum != checksum || fountain.fragment.count != fragmentLength {
                self = Decoder()
                count = fountain.count
                messageLength = fountain.messageLength
                checksum = fountain.checksum
                fragmentLength = fountain.fragment.count
            }
            guard seenNumbers.insert(fountain.number).inserted else { return .needMore }
            let indexes = Set(UniformResource.fragmentIndexes(number: fountain.number, count: count, checksum: checksum))
            var queue: [(indexes: Set<Int>, fragment: [UInt8])] = [(indexes, fountain.fragment)]
            while let item = queue.first, message == nil {
                queue.removeFirst()
                var current = item
                // Reduce by every fragment already known.
                for index in current.indexes where simple[index] != nil && current.indexes.count > 1 {
                    current.indexes.remove(index)
                    current.fragment = Self.xor(current.fragment, simple[index]!)
                }
                if current.indexes.count == 1, let index = current.indexes.first {
                    guard simple[index] == nil else { continue }
                    simple[index] = current.fragment
                    if simple.count == count {
                        try finish()
                        break
                    }
                    // A new fragment may reduce the mixed parts held back.
                    var held: [(indexes: Set<Int>, fragment: [UInt8])] = []
                    for m in mixed {
                        if m.indexes.contains(index) {
                            queue.append((m.indexes.subtracting([index]), Self.xor(m.fragment, current.fragment)))
                        } else {
                            held.append(m)
                        }
                    }
                    mixed = held
                } else if current.indexes.count > 1, !mixed.contains(where: { $0.indexes == current.indexes }) {
                    if mixed.count < 4 * UniformResource.maximumParts { mixed.append(current) }
                }
            }
            if let message { return .complete(try Self.payload(of: message)) }
            return .needMore
        }

        private mutating func finish() throws {
            let joined = Array((0..<count).flatMap { simple[$0]! }.prefix(messageLength))
            guard CRC32.checksum(joined) == checksum else {
                self = Decoder()
                throw DecodeError.badChecksum
            }
            message = joined
        }

        private static func xor(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] { zip(a, b).map { $0 ^ $1 } }

        private static func payload(of cbor: [UInt8]) throws -> [UInt8] {
            guard case .bytes(let bytes) = try CBOR.decode(cbor) else { throw DecodeError.unsupportedType }
            return bytes
        }
    }
}

/// CRC-32 (IEEE 802.3), as Bytewords, the fountain parts and gzip use.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// The small part of CBOR (RFC 8949) the UR parts and AirGap's messages use: unsigned and
/// negative integers, byte and text strings, arrays, maps and the simple values. Definite
/// lengths only; depth and sizes are bounded.
indirect enum CBOR: Equatable, Sendable {
    case unsigned(UInt64)
    case negative(UInt64)  // -1 - n
    case bytes([UInt8])
    case text(String)
    case array([CBOR])
    case map([(CBOR, CBOR)])
    case bool(Bool)
    case null
    case undefined

    static func == (a: CBOR, b: CBOR) -> Bool {
        switch (a, b) {
        case (.unsigned(let x), .unsigned(let y)), (.negative(let x), .negative(let y)): x == y
        case (.bytes(let x), .bytes(let y)): x == y
        case (.text(let x), .text(let y)): x == y
        case (.array(let x), .array(let y)): x == y
        case (.map(let x), .map(let y)): x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.bool(let x), .bool(let y)): x == y
        case (.null, .null), (.undefined, .undefined): true
        default: false
        }
    }

    enum DecodeError: Error { case truncated, unsupported, tooDeep, tooLarge, trailingBytes }

    static let maximumDepth = 16
    static let maximumItems = 4096

    static func decode(_ bytes: [UInt8]) throws -> CBOR {
        var reader = Reader(bytes: bytes)
        let value = try reader.read(depth: 0)
        guard reader.offset == bytes.count else { throw DecodeError.trailingBytes }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var items = 0

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw DecodeError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func take(_ n: UInt64) throws -> [UInt8] {
            guard n <= UInt64(bytes.count - offset) else { throw DecodeError.truncated }
            defer { offset += Int(n) }
            return Array(bytes[offset..<offset + Int(n)])
        }

        mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0...23: return UInt64(info)
            case 24: return UInt64(try byte())
            case 25, 26, 27:
                let width = 1 << (info - 24)
                return try take(UInt64(width)).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            default: throw DecodeError.unsupported
            }
        }

        mutating func read(depth: Int) throws -> CBOR {
            guard depth <= CBOR.maximumDepth else { throw DecodeError.tooDeep }
            items += 1
            guard items <= CBOR.maximumItems else { throw DecodeError.tooLarge }
            let initial = try byte()
            let major = initial >> 5
            let info = initial & 0x1f
            switch major {
            case 0: return .unsigned(try argument(info))
            case 1: return .negative(try argument(info))
            case 2: return .bytes(try take(try argument(info)))
            case 3:
                guard let text = String(bytes: try take(try argument(info)), encoding: .utf8) else { throw DecodeError.unsupported }
                return .text(text)
            case 4:
                let n = try argument(info)
                guard n <= UInt64(CBOR.maximumItems) else { throw DecodeError.tooLarge }
                return .array(try (0..<n).map { _ in try read(depth: depth + 1) })
            case 5:
                let n = try argument(info)
                guard n <= UInt64(CBOR.maximumItems) else { throw DecodeError.tooLarge }
                return .map(try (0..<n).map { _ in (try read(depth: depth + 1), try read(depth: depth + 1)) })
            case 7:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 23: return .undefined
                default: throw DecodeError.unsupported
                }
            default: throw DecodeError.unsupported
            }
        }
    }

    var encoded: [UInt8] {
        switch self {
        case .unsigned(let n): Self.head(0, n)
        case .negative(let n): Self.head(1, n)
        case .bytes(let b): Self.head(2, UInt64(b.count)) + b
        case .text(let s): Self.head(3, UInt64(s.utf8.count)) + Array(s.utf8)
        case .array(let items): Self.head(4, UInt64(items.count)) + items.flatMap(\.encoded)
        case .map(let pairs): Self.head(5, UInt64(pairs.count)) + pairs.flatMap { $0.0.encoded + $0.1.encoded }
        case .bool(let b): [b ? 0xf5 : 0xf4]
        case .null: [0xf6]
        case .undefined: [0xf7]
        }
    }

    private static func head(_ major: UInt8, _ n: UInt64) -> [UInt8] {
        let m = major << 5
        switch n {
        case 0...23: return [m | UInt8(n)]
        case 24...0xff: return [m | 24, UInt8(n)]
        case 0x100...0xffff: return [m | 25] + (0..<2).reversed().map { UInt8(n >> (8 * $0) & 0xff) }
        case 0x10000...0xffff_ffff: return [m | 26] + (0..<4).reversed().map { UInt8(n >> (8 * $0) & 0xff) }
        default: return [m | 27] + (0..<8).reversed().map { UInt8(n >> (8 * $0) & 0xff) }
        }
    }
}
