#if canImport(Compression)
import Compression
#elseif canImport(CZlib)
import CZlib
#endif
import Foundation

/// AirGap's inter-app messages (IAC, serializer version 3), the QR language of AirGap Vault and
/// AirGap Wallet: `gzip(CBOR([3, [message, …]]))` carried as a `ur:bytes` Uniform Resource. A
/// message is `[version, type, protocol, id, payload]`; the payload is the message type's JSON
/// schema flattened to an array of its properties in alphabetical order, with a string that
/// looks like hex sent as bytes behind a one-byte tag saying how to write it back.
///
/// Signet reads an account share (Vault's "Pair Account" code: the public key, derivation path
/// and the Vault's master fingerprint) and writes and reads Tezos transaction sign requests and
/// responses. The format is AirGap's (`@airgap/serializer`); nothing here talks to anything.
enum AirGap {
    static let serializerVersion: UInt64 = 3
    static let tezosProtocol = "xtz"
    /// What AirGap Wallet puts in a sign request; Vault requires the field.
    static let callbackURL = "airgap-wallet://?d="
    /// A message far larger than any Signet reads or writes.
    static let maximumInflatedLength = 512 * 1024

    enum MessageType: UInt64, Sendable {
        case accountShareRequest = 3
        case accountShareResponse = 4
        case transactionSignRequest = 5
        case transactionSignResponse = 6
        case messageSignRequest = 7
        case messageSignResponse = 8
    }

    enum Error: Swift.Error, Equatable {
        case notAirGap
        case unsupportedVersion
        case malformed
        case noTezosAccount
        case wrongResponse
        /// The reply answers this request but signs other bytes than were sent.
        case differentOperation
    }

    struct Message: Equatable, Sendable {
        var version: UInt64 = 1
        var type: UInt64
        var protocolIdentifier: String
        var id: UInt64
        var payload: [CBOR]

        var cbor: CBOR {
            .array([.unsigned(version), .unsigned(type), .text(protocolIdentifier), .unsigned(id), .array(payload)])
        }

        init(type: UInt64, protocolIdentifier: String, id: UInt64, payload: [CBOR]) {
            self.type = type
            self.protocolIdentifier = protocolIdentifier
            self.id = id
            self.payload = payload
        }

        init(cbor: CBOR) throws {
            guard case .array(let fields) = cbor, fields.count == 5,
                  case .unsigned(let version) = fields[0], version <= 1,
                  case .unsigned(let type) = fields[1],
                  case .text(let protocolIdentifier) = fields[2],
                  case .unsigned(let id) = fields[3], id <= 99_999_999,
                  case .array(let payload) = fields[4]
            else { throw Error.malformed }
            self.version = version
            self.type = type
            self.protocolIdentifier = protocolIdentifier
            self.id = id
            self.payload = payload
        }
    }

    // MARK: The wrapper

    /// The messages in an IAC payload: the bytes a `ur:bytes` UR carries.
    static func messages(from payload: [UInt8]) throws -> [Message] {
        guard let inflated = Gzip.decompress(payload, limit: maximumInflatedLength) else { throw Error.notAirGap }
        guard case .array(let top) = try CBOR.decode(inflated), top.count == 2,
              case .unsigned(let version) = top[0], case .array(let items) = top[1]
        else { throw Error.notAirGap }
        guard version == serializerVersion else { throw Error.unsupportedVersion }
        return try items.map(Message.init(cbor:))
    }

    static func payload(for messages: [Message]) -> [UInt8] {
        Gzip.compress(CBOR.array([.unsigned(serializerVersion), .array(messages.map(\.cbor))]).encoded)
    }

    // MARK: Strings

    /// A schema string as AirGap writes it: hex as tagged bytes, anything else as text.
    static func encodeString(_ value: String) -> CBOR {
        func isHex(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy(\.isHexDigit) }
        var tag: UInt8
        var hex: Substring
        if value.hasPrefix("0x") {
            hex = value.dropFirst(2)
            guard isHex(hex) else { return .bytes([0] + Array(hex.utf8)) }
            tag = hex.count % 2 == 0 ? 1 : 3
        } else {
            guard isHex(Substring(value)) else { return .text(value) }
            hex = Substring(value)
            tag = hex.count % 2 == 0 ? 2 : 4
        }
        let even = hex.count % 2 == 0 ? String(hex) : "0" + hex
        return .bytes([tag] + (Hex.decode(even) ?? []))
    }

    static func decodeString(_ value: CBOR) throws -> String {
        switch value {
        case .text(let text): return text
        case .bytes(let bytes):
            guard let tag = bytes.first else { throw Error.malformed }
            let rest = Array(bytes.dropFirst())
            switch tag {
            case 0: return "0x" + (String(bytes: rest, encoding: .utf8) ?? "")
            case 1: return "0x" + Hex.encode(rest)
            case 2: return Hex.encode(rest)
            case 3: return "0x" + Hex.encode(rest).dropFirst()
            case 4: return String(Hex.encode(rest).dropFirst())
            default: throw Error.malformed
            }
        default: throw Error.malformed
        }
    }

    // MARK: Account share

    /// A Tezos account a Vault shared: its ed25519 public key and where the Vault keeps it.
    struct Account: Equatable, Hashable, Sendable {
        /// `edpk…`.
        let publicKey: String
        let derivationPath: String
        let masterFingerprint: String
        /// The Vault's name for the secret the account comes from.
        let groupLabel: String

        /// The `secret_keys` locator, in octez-client's shape (octez lists it as "airgap sk
        /// known" and leaves it alone): `airgap://<fingerprint>/<path without m/>`.
        var locator: String {
            var path = derivationPath
            if path.hasPrefix("m/") { path.removeFirst(2) }
            return "airgap://\(masterFingerprint.isEmpty ? "vault" : masterFingerprint)/\(path)"
        }
    }

    /// The Tezos accounts in an account share response; other coins are skipped.
    static func accounts(in messages: [Message]) throws -> [Account] {
        try messages.compactMap { message in
            guard message.type == MessageType.accountShareResponse.rawValue, message.protocolIdentifier == tezosProtocol else { return nil }
            // derivationPath, groupId, groupLabel, isActive, isExtendedPublicKey, masterFingerprint, publicKey
            guard message.payload.count == 7, case .bool(let extended) = message.payload[4], !extended else { throw Error.malformed }
            let key = try decodeString(message.payload[6])
            guard let publicKey = edpk(from: key) else { throw Error.malformed }
            return Account(publicKey: publicKey,
                           derivationPath: try decodeString(message.payload[0]),
                           masterFingerprint: try decodeString(message.payload[5]),
                           groupLabel: try decodeString(message.payload[2]))
        }
    }

    /// The base58 public key for AirGap's hex form (32 bytes of ed25519) or an `edpk` as is.
    static func edpk(from key: String) -> String? {
        if key.hasPrefix("edpk") {
            guard let body = Base58.checkDecode(key), body.count == 36 else { return nil }
            return key
        }
        guard key.count == 64, let bytes = Hex.decode(key) else { return nil }
        return Base58.checkEncode(prefix: TezosPrefix.edpk, payload: bytes)
    }

    /// The 32 raw bytes of an `edpk`, as hex, which is how AirGap names the key in a request.
    static func hexPublicKey(_ edpk: String) -> String? {
        guard edpk.hasPrefix("edpk"), let body = Base58.checkDecode(edpk), body.count == 36 else { return nil }
        return Hex.encode(Array(body.suffix(32)))
    }

    // MARK: Signing

    /// A request for the Vault to sign `forged` (the operation's bytes, without the watermark).
    static func signRequest(publicKey edpk: String, forged: [UInt8], id: UInt64) -> Message? {
        guard let key = hexPublicKey(edpk) else { return nil }
        // callbackURL, publicKey, transaction { binaryTransaction }
        return Message(type: MessageType.transactionSignRequest.rawValue, protocolIdentifier: tezosProtocol, id: id,
                       payload: [encodeString(callbackURL), encodeString(key), .array([encodeString(Hex.encode(forged))])])
    }

    /// The signed operation in a Vault's response to request `id`: forged bytes followed by the
    /// 64-byte signature.
    static func signedOperation(in messages: [Message], id: UInt64) throws -> [UInt8] {
        guard let message = messages.first(where: { $0.type == MessageType.transactionSignResponse.rawValue }) else { throw Error.wrongResponse }
        guard message.protocolIdentifier == tezosProtocol, message.id == id else { throw Error.wrongResponse }
        // accountIdentifier, transaction
        guard message.payload.count == 2, let bytes = Hex.decode(try decodeString(message.payload[1])) else { throw Error.malformed }
        return bytes
    }

    /// The 64-byte signature in a Vault's reply to request `id` for `forged`: the reply must
    /// carry exactly those bytes followed by the signature. The signature itself is checked
    /// against the account's key in the bridge before it is used.
    static func signature(in messages: [Message], id: UInt64, forged: [UInt8]) throws -> [UInt8] {
        let signed = try signedOperation(in: messages, id: id)
        guard signed.count == forged.count + 64, signed.starts(with: forged) else { throw Error.differentOperation }
        return Array(signed.suffix(64))
    }

    /// A fresh 8-digit message id, as AirGap makes them.
    static func newID() -> UInt64 { UInt64.random(in: 10_000_000...99_999_999) }
}

/// gzip (RFC 1952) around raw DEFLATE from Apple's Compression framework.
enum Gzip {
    static func decompress(_ data: [UInt8], limit: Int) -> [UInt8]? {
        #if canImport(Compression) || canImport(CZlib)
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 8 else { return nil }
        let flags = data[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { return nil }
            offset += 2 + (Int(data[offset]) | Int(data[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count - 8 else { return nil }
        let trailer = Array(data.suffix(8))
        let size = Int(UInt32(trailer[4]) | UInt32(trailer[5]) << 8 | UInt32(trailer[6]) << 16 | UInt32(trailer[7]) << 24)
        guard size <= limit else { return nil }
        let crc = UInt32(trailer[0]) | UInt32(trailer[1]) << 8 | UInt32(trailer[2]) << 16 | UInt32(trailer[3]) << 24
        let deflated = Array(data[offset..<(data.count - 8)])
        var output = [UInt8](repeating: 0, count: size + 1)
        #if canImport(Compression)
        let written = output.withUnsafeMutableBufferPointer { out in
            deflated.withUnsafeBufferPointer { input in
                compression_decode_buffer(out.baseAddress!, out.count, input.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        #else
        let written = zlibInflateRaw(deflated, into: &output)
        #endif
        guard written == size else { return nil }
        let result = Array(output.prefix(size))
        return CRC32.checksum(result) == crc ? result : nil
        #else
        return nil
        #endif
    }

    static func compress(_ data: [UInt8]) -> [UInt8] {
        #if canImport(Compression) || canImport(CZlib)
        var deflated = [UInt8](repeating: 0, count: data.count + 1024)
        #if canImport(Compression)
        let written = deflated.withUnsafeMutableBufferPointer { out in
            data.withUnsafeBufferPointer { input in
                compression_encode_buffer(out.baseAddress!, out.count, input.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        #else
        let written = zlibDeflateRaw(data, into: &deflated)
        #endif
        let little = { (v: UInt32) in [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)] }
        return [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3] + deflated.prefix(written) + little(CRC32.checksum(data)) + little(UInt32(truncatingIfNeeded: data.count))
        #else
        return []
        #endif
    }

    #if !canImport(Compression) && canImport(CZlib)
    /// Raw DEFLATE (no zlib header, as Compression's `COMPRESSION_ZLIB`) with zlib: the bytes
    /// written into `output`, or -1.
    private static func zlibInflateRaw(_ input: [UInt8], into output: inout [UInt8]) -> Int {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return -1 }
        defer { inflateEnd(&stream) }
        var input = input
        let capacity = output.count
        return input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(capacity)
                guard inflate(&stream, Z_FINISH) == Z_STREAM_END else { return -1 }
                return capacity - Int(stream.avail_out)
            }
        }
    }

    private static func zlibDeflateRaw(_ input: [UInt8], into output: inout [UInt8]) -> Int {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return 0 }
        defer { deflateEnd(&stream) }
        var input = input
        let capacity = output.count
        return input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(capacity)
                guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return 0 }
                return capacity - Int(stream.avail_out)
            }
        }
    }
    #endif
}
