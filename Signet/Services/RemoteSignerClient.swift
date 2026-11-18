import Foundation
import Network

/// What Signet asks an octez-signer: its keys, a key's public key, whether it wants requests
/// authenticated, a signature, and a tz4 key's proof of possession. HTTP(S) speaks the signer's
/// JSON RPC (`signer_services.ml`); TCP and Unix sockets its binary messages (`SignerWire`).
/// Nothing secret is ever sent: what is signed is public once injected, and every signature is
/// checked against the account's key before it is used.
protocol RemoteSignerService: Sendable {
    /// The keys the signer holds (`known_keys`; older signers do not answer it).
    func knownKeys(at signer: RemoteSignerLocator) async throws -> [Address]
    /// The base58 public key of the locator's key.
    func publicKey(at signer: RemoteSignerLocator) async throws -> String
    /// `nil` when the signer accepts unauthenticated requests, else the keys it wants a request signed by.
    func authorizedKeys(at signer: RemoteSignerLocator) async throws -> [Address]?
    func sign(_ bytes: [UInt8], at signer: RemoteSignerLocator) async throws -> RemoteSignature
    /// A BLS proof of possession (`BLsig…`) for the locator's tz4 key.
    func provePossession(at signer: RemoteSignerLocator) async throws -> String
}

/// A signature as the signer gave it: base58 over HTTP (often the generic `sig…` form), raw
/// bytes over a socket. The bridge turns either into the right form for the key.
enum RemoteSignature: Equatable, Sendable {
    case base58(String)
    case raw([UInt8])

    var bridgeJSON: String {
        let object: [String: String] = switch self {
        case .base58(let text): ["signature": text]
        case .raw(let bytes): ["raw": Hex.encode(bytes)]
        }
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
}

enum RemoteSignerError: LocalizedError, Equatable {
    case unreachable(String)
    /// The signer hung up without answering: what an octez-signer does with a request it cannot decode.
    case closed
    case timedOut
    case authenticationRequired
    case refused(String?)
    case notFound
    case malformedReply
    case unsupported(String)
    /// The signer's public key for this address hashes to another address.
    case keyMismatch(expected: Address, found: Address)

    /// Octez 23 moved BLS signing to the proof-of-possession scheme the chain checks today, and
    /// names a tz4 key in a request with its signature version; older signers do neither.
    static let tz4NeedsRecentSigner = "This signer does not understand a signing request for a tz4 key. tz4 keys need octez-signer 23 or later, which makes the BLS signatures the chain accepts."

    var errorDescription: String? {
        switch self {
        case .unreachable(let detail): "Signet could not reach the remote signer: \(detail)"
        case .closed: "The remote signer closed the connection without answering; it may not understand this request (an older octez-signer?)."
        case .timedOut: "The remote signer did not answer in time."
        case .authenticationRequired: "The remote signer only accepts authenticated requests (it was started with --require-authentication). Signet cannot authenticate to a signer yet."
        case .refused(let reason): "The remote signer refused the request" + (reason.map { ": \($0)" } ?? ".")
        case .notFound: "The remote signer does not answer that request (it may be an older octez-signer)."
        case .malformedReply: "The remote signer's reply could not be read."
        case .unsupported(let what): what
        case .keyMismatch(let expected, let found): "The signer's public key for \(expected.value) belongs to \(found.value). Signet will not use it."
        }
    }
}

struct NetworkRemoteSignerService: RemoteSignerService {
    /// Long enough for a signer that waits on a person (a Ledger behind octez-signer).
    var timeout: Duration = .seconds(120)
    /// The most a reply may carry: a public key list, a key, a signature.
    static let replyLimit = 256 << 10

    func knownKeys(at signer: RemoteSignerLocator) async throws -> [Address] {
        switch signer.transport {
        case .http, .https:
            let object = try await getJSON(signer, path: "/known_keys")
            guard let list = object["known_keys"] as? [String] else { throw RemoteSignerError.malformedReply }
            return list.map(Address.init).filter(\.isImplicitAccount)
        case .tcp, .unix:
            return try SignerWire.addresses(fromValue: SignerWire.value(try await exchange(signer, [SignerWire.knownKeysRequest]).last!))
        }
    }

    func publicKey(at signer: RemoteSignerLocator) async throws -> String {
        switch signer.transport {
        case .http, .https:
            let object = try await getJSON(signer, path: "/keys/\(signer.address.value)")
            guard let key = object["public_key"] as? String else { throw RemoteSignerError.malformedReply }
            return key
        case .tcp, .unix:
            guard let request = SignerWire.publicKeyRequest(address: signer.address) else { throw RemoteSignerError.malformedReply }
            return try SignerWire.publicKey(fromValue: SignerWire.value(try await exchange(signer, [request]).last!))
        }
    }

    func authorizedKeys(at signer: RemoteSignerLocator) async throws -> [Address]? {
        switch signer.transport {
        case .http, .https:
            let object = try await getJSON(signer, path: "/authorized_keys")
            guard let list = object["authorized_keys"] else { return nil }
            guard let keys = list as? [String] else { throw RemoteSignerError.malformedReply }
            return keys.map(Address.init)
        case .tcp, .unix:
            return try SignerWire.authorizedKeys(fromValue: SignerWire.value(try await exchange(signer, [SignerWire.authorizedKeysRequest]).last!))
        }
    }

    func sign(_ bytes: [UInt8], at signer: RemoteSignerLocator) async throws -> RemoteSignature {
        switch signer.transport {
        case .http, .https:
            guard try await authorizedKeys(at: signer) == nil else { throw RemoteSignerError.authenticationRequired }
            let body = try JSONSerialization.data(withJSONObject: Hex.encode(bytes), options: .fragmentsAllowed)
            let object = try await requestJSON(signer, path: "/keys/\(signer.address.value)", method: "POST", body: body)
            guard let signature = object["signature"] as? String else { throw RemoteSignerError.malformedReply }
            return .base58(signature)
        case .tcp, .unix:
            // As octez-client does: ask whether authentication is needed, then sign, on one connection.
            func signed() async throws -> [[UInt8]] {
                guard let request = SignerWire.signRequest(address: signer.address, data: bytes) else { throw RemoteSignerError.malformedReply }
                return try await exchange(signer, [SignerWire.authorizedKeysRequest, request]) { index, reply in
                    if index == 0, try SignerWire.authorizedKeys(fromValue: SignerWire.value(reply)) != nil { throw RemoteSignerError.authenticationRequired }
                }
            }
            let replies: [[UInt8]]
            do {
                replies = try await signed()
            } catch RemoteSignerError.closed where signer.address.scheme == .tz4 {
                throw RemoteSignerError.unsupported(RemoteSignerError.tz4NeedsRecentSigner)
            }
            let signature = try SignerWire.value(replies[1])
            guard [64, 96, 2420].contains(signature.count) else { throw RemoteSignerError.malformedReply }
            return .raw(Array(signature))
        }
    }

    func provePossession(at signer: RemoteSignerLocator) async throws -> String {
        guard signer.address.scheme == .tz4 else { throw RemoteSignerError.unsupported("Only a tz4 key has a proof of possession.") }
        switch signer.transport {
        case .http, .https:
            let object = try await getJSON(signer, path: "/bls_prove_possession/\(signer.address.value)")
            guard let proof = object["bls_prove_possession"] as? String, proof.hasPrefix("BLsig") else { throw RemoteSignerError.malformedReply }
            return proof
        case .tcp, .unix:
            guard let request = SignerWire.provePossessionRequest(address: signer.address) else { throw RemoteSignerError.malformedReply }
            let value = try SignerWire.value(try await exchange(signer, [request]).last!)
            guard value.count == 96 else { throw RemoteSignerError.malformedReply }
            return Base58.checkEncode(prefix: [40, 171, 64, 207], payload: Array(value))
        }
    }

    // MARK: HTTP

    private func getJSON(_ signer: RemoteSignerLocator, path: String) async throws -> [String: Any] {
        try await requestJSON(signer, path: path, method: "GET", body: nil)
    }

    private func requestJSON(_ signer: RemoteSignerLocator, path: String, method: String, body: Data?) async throws -> [String: Any] {
        guard let base = signer.baseURL, let url = URL(string: base.absoluteString + path) else { throw RemoteSignerError.unreachable("the signer's address is not a valid URL") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: TimeInterval(timeout.components.seconds))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = TimeInterval(timeout.components.seconds)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let reply: BoundedHTTP.Reply
        do {
            reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.replyLimit, json: .record)
        } catch let error as URLError where error.code == .timedOut {
            throw RemoteSignerError.timedOut
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            _ = error
            throw RemoteSignerError.unreachable("macOS allows plain HTTP only to this Mac, an IP address, a .local name or a one-word host name. Use the signer's IP address, HTTPS or TCP.")
        } catch let error as URLError {
            throw RemoteSignerError.unreachable(error.localizedDescription)
        } catch BoundedHTTP.Failure.overBudget, BoundedHTTP.Failure.tooLarge {
            throw RemoteSignerError.malformedReply
        }
        guard reply.isSuccess else {
            if reply.status == 404 { throw RemoteSignerError.notFound }
            let errors = try? JSONSerialization.jsonObject(with: reply.data) as? [[String: Any]]
            let id = errors?.first?["id"] as? String
            if let id, id.contains("authentication") || id.contains("unauthorized") { throw RemoteSignerError.authenticationRequired }
            throw RemoteSignerError.refused(id ?? "HTTP \(reply.status)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any] else { throw RemoteSignerError.malformedReply }
        return object
    }

    // MARK: Sockets

    /// Sends `requests` one after another on one connection and returns each reply's payload.
    /// `check` sees every reply as it arrives and may stop the exchange by throwing.
    private func exchange(_ signer: RemoteSignerLocator, _ requests: [[UInt8]], check: @escaping @Sendable (Int, [UInt8]) throws -> Void = { _, _ in }) async throws -> [[UInt8]] {
        let endpoint: NWEndpoint
        switch signer.transport {
        case .tcp:
            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: signer.port)) else { throw RemoteSignerError.unreachable("invalid port") }
            endpoint = .hostPort(host: NWEndpoint.Host(signer.host), port: port)
        case .unix:
            endpoint = .unix(path: signer.path)
        default:
            throw RemoteSignerError.unreachable("not a socket signer")
        }
        let connection = FramedConnection(endpoint: endpoint)
        defer { connection.close() }
        return try await withThrowingTaskGroup(of: [[UInt8]]?.self) { group in
            group.addTask {
                try await connection.open()
                var replies: [[UInt8]] = []
                for (index, request) in requests.enumerated() {
                    guard let frame = SignerWire.frame(request) else { throw RemoteSignerError.malformedReply }
                    try await connection.send(frame)
                    let header = try await connection.receive(exactly: 2)
                    let length = Int(header[0]) << 8 | Int(header[1])
                    let reply = try await connection.receive(exactly: length)
                    try check(index, reply)
                    replies.append(reply)
                }
                return replies
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let replies = first else {
                connection.close()
                throw RemoteSignerError.timedOut
            }
            return replies
        }
    }
}

/// One Network.framework connection carrying length-prefixed messages. Every callback resumes
/// its continuation once; closing fails whatever is still waiting.
private final class FramedConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "org.tezos.signet.remote-signer")
    /// Whether `open` has answered; touched on `queue` only, where every state update runs.
    private var opened = false

    init(endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: parameters)
    }

    func open() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { [self] state in
                    guard !opened else { return }
                    switch state {
                    case .ready:
                        opened = true
                        continuation.resume()
                    case .failed(let error), .waiting(let error):
                        opened = true
                        continuation.resume(throwing: RemoteSignerError.unreachable(Self.describe(error)))
                    case .cancelled:
                        opened = true
                        continuation.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: { connection.cancel() }
    }

    func send(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: RemoteSignerError.unreachable(Self.describe(error))) } else { continuation.resume() }
            })
        }
    }

    func receive(exactly count: Int) async throws -> [UInt8] {
        var collected: [UInt8] = []
        while collected.count < count {
            let chunk: [UInt8] = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - collected.count) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: RemoteSignerError.unreachable(Self.describe(error))) }
                    else if let data, !data.isEmpty { continuation.resume(returning: [UInt8](data)) }
                    else if isComplete { continuation.resume(throwing: RemoteSignerError.closed) }
                    else { continuation.resume(returning: []) }
                }
            }
            collected += chunk
        }
        return collected
    }

    func close() { connection.cancel() }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED: "nothing is listening there (connection refused)"
        case .dns: "the host name could not be found"
        default: error.localizedDescription
        }
    }
}

/// For tests and previews: a signer holding the given keys that signs with `signer`.
struct MockRemoteSignerService: RemoteSignerService {
    var keys: [Address: String] = [:]
    var requiresAuthentication = false
    var signature: @Sendable ([UInt8], Address) throws -> RemoteSignature = { _, _ in .raw([UInt8](repeating: 0, count: 64)) }

    func knownKeys(at signer: RemoteSignerLocator) async throws -> [Address] { keys.keys.sorted { $0.value < $1.value } }
    func publicKey(at signer: RemoteSignerLocator) async throws -> String {
        guard let key = keys[signer.address] else { throw RemoteSignerError.refused("unknown_key") }
        return key
    }
    func authorizedKeys(at signer: RemoteSignerLocator) async throws -> [Address]? { requiresAuthentication ? [] : nil }
    func sign(_ bytes: [UInt8], at signer: RemoteSignerLocator) async throws -> RemoteSignature {
        if requiresAuthentication { throw RemoteSignerError.authenticationRequired }
        return try signature(bytes, signer.address)
    }
    func provePossession(at signer: RemoteSignerLocator) async throws -> String { "BLsigMockProof" }
}

/// The bridge's way to a remote signer: `{op: "sign", locator, address, bytes}` or
/// `{op: "prove", locator, address}`, answered with `RemoteSignature.bridgeJSON` or
/// `{"proof": "BLsig…"}`. The locator is the one Swift put in the signing key.
enum RemoteSigners {
    static let service: any RemoteSignerService = NetworkRemoteSignerService()

    static func answer(requestJSON: String, service: any RemoteSignerService = service) async throws -> String {
        guard let data = requestJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = object["op"] as? String, let text = object["locator"] as? String,
              let signer = RemoteSignerLocator(locator: text), signer.address.value == object["address"] as? String
        else { throw RemoteSignerError.malformedReply }
        switch op {
        case "sign":
            guard let hex = object["bytes"] as? String, let bytes = Hex.decode(hex), !bytes.isEmpty else { throw RemoteSignerError.malformedReply }
            return try await service.sign(bytes, at: signer).bridgeJSON
        case "prove":
            let proof = try await service.provePossession(at: signer)
            return String(data: try JSONSerialization.data(withJSONObject: ["proof": proof]), encoding: .utf8)!
        default:
            throw RemoteSignerError.malformedReply
        }
    }
}
