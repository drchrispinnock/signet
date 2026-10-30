import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a network's shielded transactions (TzEL) live: the rollup node whose durable state
/// holds the notes and deposit pools, the rollup itself, the layer 1 bridge ticketer that
/// funds a pool, the operator that relays proved requests to the rollup (bearer token), the
/// proving service, and the DAL producer every shield pays a fee note to.
struct ShieldedConfig: Hashable, Sendable {
    let rollupNode: URL
    let rollupAddress: String
    let ticketer: Address
    let operatorURL: URL
    let provingURL: URL
    /// The producer-fee note's value, in mutez (the operator's inclusion policy).
    let producerFeeMutez: UInt64
    var producer: ProducerAddress

    /// The producer's payment address in the reference JSON form (`d_j`, `auth_root`,
    /// `auth_pub_seed`, `nk_tag`, `ek_v`, `ek_d`, all hex): a bundled resource, or given.
    enum ProducerAddress: Hashable, Sendable {
        case resource(String)
        case json([String: String])
    }

    /// Shadownet's deployment (verified October 2026, `docs/tzel/RESEARCH.md`). The producer
    /// address is the operator's published fee address.
    static let shadownet = ShieldedConfig(
        rollupNode: URL(string: "http://rollup.tzel.tezos.com:8932")!,
        rollupAddress: "sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK",
        ticketer: Address("KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4"),
        operatorURL: URL(string: "http://operator.tzel.tezos.com:8787")!,
        provingURL: URL(string: "https://proving.tzel.tezos.com")!,
        producerFeeMutez: 100_000,
        producer: .resource("tzel-shadownet-producer")
    )

    /// The items the Shielded settings sheet shows per network. Where Signet ships a deployment
    /// each has a default; elsewhere the fields start blank and the network can shield once
    /// every one is filled in.
    enum Setting: String, CaseIterable, Sendable {
        case rollupNode, rollupAddress, ticketer, operatorURL, provingURL, producerFee, producerAddress

        var title: String {
            switch self {
            case .rollupNode: "Rollup node"
            case .rollupAddress: "Rollup"
            case .ticketer: "Bridge ticketer"
            case .operatorURL: "Operator"
            case .provingURL: "Proving service"
            case .producerFee: "Producer fee"
            case .producerAddress: "Producer address"
            }
        }

        var prompt: String {
            switch self {
            case .rollupNode, .operatorURL, .provingURL: "http(s)://…"
            case .rollupAddress: "sr1…"
            case .ticketer: "KT1…"
            case .producerFee: "mutez"
            case .producerAddress: "The producer's payment address (JSON)"
            }
        }

        /// The text as kept, or `nil` when it is not valid for this item.
        func normalised(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch self {
            case .rollupNode, .operatorURL, .provingURL: return ShieldedConfig.serviceURL(from: trimmed)?.absoluteString
            case .rollupAddress: return ShieldedConfig.isRollupAddress(trimmed) ? trimmed : nil
            case .ticketer: return trimmed.hasPrefix("KT1") && Address(trimmed).isValidAccount ? trimmed : nil
            case .producerFee: return UInt64(trimmed).flatMap { $0 > 0 ? String($0) : nil }
            case .producerAddress: return ShieldedConfig.paymentAddressFields(from: trimmed).map(ShieldedConfig.compactJSON)
            }
        }

        var problem: String {
            switch self {
            case .rollupNode, .operatorURL, .provingURL: "Enter an http or https URL with a host name and no credentials."
            case .rollupAddress: "Enter a Smart Rollup address (sr1…)."
            case .ticketer: "Enter the bridge ticketer's contract address (KT1…)."
            case .producerFee: "Enter a whole number of mutez above zero."
            case .producerAddress: "Paste a payment address: JSON with d_j, auth_root, auth_pub_seed, nk_tag (32-byte hex) and ek_v, ek_d (1184-byte hex)."
            }
        }
    }

    func text(for setting: Setting) -> String {
        switch setting {
        case .rollupNode: rollupNode.absoluteString
        case .rollupAddress: rollupAddress
        case .ticketer: ticketer.value
        case .operatorURL: operatorURL.absoluteString
        case .provingURL: provingURL.absoluteString
        case .producerFee: String(producerFeeMutez)
        case .producerAddress: (try? producerAddressJSON()).map(Self.compactJSON) ?? ""
        }
    }

    init(rollupNode: URL, rollupAddress: String, ticketer: Address, operatorURL: URL, provingURL: URL, producerFeeMutez: UInt64, producer: ProducerAddress) {
        self.rollupNode = rollupNode
        self.rollupAddress = rollupAddress
        self.ticketer = ticketer
        self.operatorURL = operatorURL
        self.provingURL = provingURL
        self.producerFeeMutez = producerFeeMutez
        self.producer = producer
    }

    /// A deployment from one text per item (each already `normalised`); `nil` until every item is there.
    init?(fields: [Setting: String]) {
        guard let node = fields[.rollupNode].flatMap(URL.init(string:)), let rollup = fields[.rollupAddress], let ticketer = fields[.ticketer],
              let operatorURL = fields[.operatorURL].flatMap(URL.init(string:)), let proving = fields[.provingURL].flatMap(URL.init(string:)),
              let fee = fields[.producerFee].flatMap(UInt64.init), let producer = fields[.producerAddress].flatMap(Self.paymentAddressFields(from:))
        else { return nil }
        self.init(rollupNode: node, rollupAddress: rollup, ticketer: Address(ticketer), operatorURL: operatorURL, provingURL: proving, producerFeeMutez: fee, producer: .json(producer))
    }

    static func isRollupAddress(_ text: String) -> Bool {
        text.count == 36 && text.hasPrefix("sr1") && text.dropFirst(3).allSatisfy { "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0) }
    }

    /// A TzEL service URL: http or https (the Shadownet deployment serves plain HTTP), a host,
    /// no credentials. Note that App Transport Security only lets plain HTTP through for the
    /// hosts named in `Info.plist`.
    static func serviceURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://") {
            guard !trimmed.contains("://") else { return nil }
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let host = url.host(percentEncoded: false), !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// The six hex fields of a payment address in the reference JSON form (also accepting the
    /// reference CLI's `{index, address}` wrapper), checked for their lengths.
    static func paymentAddressFields(from text: String) -> [String: String]? {
        guard let data = text.data(using: .utf8), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let inner = object["address"] as? [String: Any] { object = inner }
        let lengths = ["d_j": 32, "auth_root": 32, "auth_pub_seed": 32, "nk_tag": 32, "ek_v": 1184, "ek_d": 1184]
        var fields: [String: String] = [:]
        for (key, length) in lengths {
            guard let value = (object[key] as? String)?.lowercased(), Hex.decode(value)?.count == length else { return nil }
            fields[key] = value
        }
        return fields
    }

    static func compactJSON(_ fields: [String: String]) -> String {
        (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func producerAddressJSON() throws -> [String: String] {
        switch producer {
        case .json(let fields):
            return fields
        case .resource(let name):
            #if SWIFT_PACKAGE
            let bundle = Bundle.module   // the GTK build's resources
            #else
            let bundle = Bundle.main
            #endif
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let fields = try JSONSerialization.jsonObject(with: data) as? [String: String]
            else { throw ShieldedError.badReply("the producer fee address \(name).json is missing from the app") }
            return fields
        }
    }
}

struct RollupHead: Hashable, Sendable {
    let hash: String
    let level: Int
}

/// What the proving service returns for a finished job: the compressed proof and the public outputs, hex.
struct ProofBundle: Hashable, Sendable {
    let proofBytes: String
    /// As the service returns them: the bootloader header (task count, output size, program
    /// hash, array length) and then the circuit's public outputs.
    let outputPreimage: [String]
    /// The program the job was proved against.
    var programHash: String = ""
}

enum ProofJob: Hashable, Sendable {
    case queued
    case running
    case done(ProofBundle)
    case failed(String)
    case unknown(String)
}

/// The operator's record of a relayed message.
struct OperatorSubmission: Hashable, Sendable {
    let id: String
    /// `pending_dal`, `commitment_included`, `attested`, `submitted_to_l1` or `failed`.
    let status: String
    let transport: String?
    let operationHash: String?
    let detail: String?

    var isTerminal: Bool { status == "submitted_to_l1" || status == "failed" }
    var succeeded: Bool { status == "submitted_to_l1" }
}

/// A message the rollup has queued for layer 1 and not yet seen executed: for an unshield, the
/// ticketer's `burn` paying `amountMutez` to the forged `receiver`.
struct OutboxEntry: Hashable, Sendable {
    let outboxLevel: Int
    let messageIndex: Int
    let destination: String
    let entrypoint: String
    /// The receiver as forged in the parameters (`Address.forgedContract`), hex.
    let receiver: String
    let amountMutez: UInt64
}

/// What executing an outbox message on layer 1 needs: the cemented commitment it is proved
/// against and the rollup node's proof, hex.
struct OutboxProof: Hashable, Sendable {
    let commitment: String
    let proof: String
}

/// The three services a shield talks to, behind one protocol so the flow can be tested
/// without a network (`MockShieldedRollup` in the tests).
protocol ShieldedRollup: Sendable {
    func head() async throws -> RollupHead
    func smartRollupAddress() async throws -> String
    /// The byte length of a durable-state value, or `nil` when the key is absent.
    func durableLength(block: String, key: String) async throws -> Int?
    /// A durable-state value, or `nil` when the key is absent.
    func durableValue(block: String, key: String) async throws -> [UInt8]?
    func programHash(named program: String) async throws -> String
    /// Starts a proving job; returns its id.
    func startProof(programHash: String, arguments: [String]) async throws -> String
    /// Long-polls a job once (the service waits up to 30 s for a change from `lastStatus`).
    func proofJob(id: String, lastStatus: String?) async throws -> ProofJob
    func submit(kind: String, payloadHex: String, rollupAddress: String, token: String) async throws -> OperatorSubmission
    func submission(id: String, token: String) async throws -> OperatorSubmission
    /// The level of the last cemented commitment: outbox messages up to it can be executed.
    func cementedLevel() async throws -> Int
    /// The outbox messages the rollup node has not seen executed.
    func pendingOutbox() async throws -> [OutboxEntry]
    /// The proof for executing one outbox message, against the last cemented commitment.
    func outboxProof(outboxLevel: Int, messageIndex: Int) async throws -> OutboxProof
}

/// The kernel's durable-state layout (`apps/wallet` of trilitech/tzel, `/tzel/v1/state/…`).
enum RollupState {
    static let authDomain = "/tzel/v1/state/auth_domain"
    static let verifierConfig = "/tzel/v1/state/verifier_config.bin"
    static let bridgeTicketer = "/tzel/v1/state/bridge/ticketer"
    static let lastInputLevel = "/tzel/v1/state/last_input_level"
    static let privateTxFeeLevel = "/tzel/v1/state/fees/private_tx_level"
    static let privateTxCountInLevel = "/tzel/v1/state/fees/private_tx_count_in_level"
    static let treeSize = "/tzel/v1/state/tree/size"
    static let treeRoot = "/tzel/v1/state/tree/root"
    static let notePrefix = "/tzel/v1/state/notes/"
    static let nullifierCount = "/tzel/v1/state/nullifiers/count"
    static let nullifierIndexPrefix = "/tzel/v1/state/nullifiers/index/"
    static let depositBalancePrefix = "/tzel/v1/state/deposits/balance/"
    /// A published note is `cm ‖ encrypted note`; large values are split into 1024-byte chunks.
    static let noteChunkBytes = 1024
    static let publishedNoteBytes = 32 + 3455

    /// The fee rule (`required_tx_fee_for_private_tx_count`): 0.1 tez, doubling for every
    /// private transaction beyond the second in the same level, up to 64 times.
    static let minTxFee: UInt64 = 100_000
    static let basePrivateTxsPerLevel: UInt64 = 2
    static let maxDynamicFeeStep: UInt64 = 6

    static func indexed(_ prefix: String, _ index: Int) -> String { prefix + String(format: "%016llx", UInt64(index)) }
    static func depositBalance(_ pubkeyHash: String) -> String { depositBalancePrefix + pubkeyHash }

    static func requiredTxFee(privateTxsInLevel count: UInt64) -> UInt64 {
        let step = min(count > basePrivateTxsPerLevel - 1 ? count - (basePrivateTxsPerLevel - 1) : 0, maxDynamicFeeStep)
        return minTxFee << step
    }
}

extension ShieldedRollup {
    func authDomain(at block: String) async throws -> String {
        guard let bytes = try await durableValue(block: block, key: RollupState.authDomain), bytes.count == 32 else {
            throw ShieldedError.rollupNotConfigured("its authentication domain is not set")
        }
        return Hex.encode(bytes)
    }

    func verifierConfigured(at block: String) async throws -> Bool {
        try await durableLength(block: block, key: RollupState.verifierConfig) != nil
    }

    func bridgeTicketer(at block: String) async throws -> String? {
        guard let bytes = try await durableValue(block: block, key: RollupState.bridgeTicketer) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func u64(at block: String, key: String) async throws -> UInt64? {
        guard let bytes = try await durableValue(block: block, key: key) else { return nil }
        guard bytes.count == 8 else { throw ShieldedError.badReply("\(key) is \(bytes.count) bytes, not 8") }
        return bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    private func i32(at block: String, key: String) async throws -> Int32? {
        guard let bytes = try await durableValue(block: block, key: key) else { return nil }
        guard bytes.count == 4 else { throw ShieldedError.badReply("\(key) is \(bytes.count) bytes, not 4") }
        return Int32(bitPattern: bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) })
    }

    /// The fee the rollup will demand of the next inbox level, read at `head`.
    func requiredTxFee(at head: RollupHead) async throws -> UInt64 {
        let nextInbox = Int32(clamping: head.level + 1)
        let lastInput = try await i32(at: head.hash, key: RollupState.lastInputLevel)
        let feeLevel = try await i32(at: head.hash, key: RollupState.privateTxFeeLevel)
        var count: UInt64 = 0
        if lastInput == nextInbox, feeLevel == nextInbox {
            count = try await u64(at: head.hash, key: RollupState.privateTxCountInLevel) ?? 0
        }
        return RollupState.requiredTxFee(privateTxsInLevel: count)
    }

    /// A deposit pool's balance in mutez, `nil` when the rollup has none for it.
    func poolBalance(at block: String, pubkeyHash: String) async throws -> UInt64? {
        try await u64(at: block, key: RollupState.depositBalance(pubkeyHash))
    }

    /// The commitment tree's current root, hex.
    func treeRoot(at block: String) async throws -> String {
        guard let bytes = try await durableValue(block: block, key: RollupState.treeRoot), bytes.count == 32 else {
            throw ShieldedError.badReply("the commitment tree root is missing")
        }
        return Hex.encode(bytes)
    }

    func treeSize(at block: String) async throws -> Int {
        guard let size = try await u64(at: block, key: RollupState.treeSize) else { return 0 }
        guard size <= UInt64(Int32.max) else { throw ShieldedError.badReply("tree size \(size)") }
        return Int(size)
    }

    /// The published note at `index`: the direct key, else its chunks.
    func publishedNote(at block: String, index: Int) async throws -> [UInt8]? {
        let key = RollupState.indexed(RollupState.notePrefix, index)
        if try await durableLength(block: block, key: key) != nil, let direct = try await durableValue(block: block, key: key) {
            return direct
        }
        guard let length = try await u64(at: block, key: key + "/len") else { return nil }
        guard length == UInt64(RollupState.publishedNoteBytes) else { throw ShieldedError.badReply("note \(index) is \(length) bytes") }
        var bytes: [UInt8] = []
        var chunk = 0
        while bytes.count < Int(length) {
            guard let part = try await durableValue(block: block, key: key + "/chunk/" + String(format: "%08x", chunk)) else {
                throw ShieldedError.badReply("note \(index) is missing chunk \(chunk)")
            }
            bytes += part
            chunk += 1
            if chunk > 8 { throw ShieldedError.badReply("note \(index) has too many chunks") }
        }
        guard bytes.count == Int(length) else { throw ShieldedError.badReply("note \(index) chunks make \(bytes.count) bytes") }
        return bytes
    }

    func nullifierCount(at block: String) async throws -> Int {
        guard let count = try await u64(at: block, key: RollupState.nullifierCount) else { return 0 }
        guard count <= UInt64(Int32.max) else { throw ShieldedError.badReply("nullifier count \(count)") }
        return Int(count)
    }

    func nullifier(at block: String, index: Int) async throws -> String {
        guard let bytes = try await durableValue(block: block, key: RollupState.indexed(RollupState.nullifierIndexPrefix, index)), bytes.count == 32 else {
            throw ShieldedError.badReply("nullifier \(index) is missing")
        }
        return Hex.encode(bytes)
    }

    /// Submits a proving job and waits for it: up to `polls` long-polls of 30 s each.
    func prove(program: String, arguments: [String], polls: Int = 60) async throws -> ProofBundle {
        let hash = try await programHash(named: program)
        let job = try await startProof(programHash: hash, arguments: arguments)
        var last: String?
        var unknown = 0
        for _ in 0..<polls {
            try Task.checkCancellation()
            switch try await proofJob(id: job, lastStatus: last) {
            case .queued: last = "queued"; unknown = 0
            case .running: last = "running"; unknown = 0
            case .done(var bundle): bundle.programHash = hash; return bundle
            case .failed(let detail): throw ShieldedError.proving(detail)
            case .unknown(let status):
                unknown += 1
                if unknown >= 3 { throw ShieldedError.proving("job \(job) keeps reporting status \(status)") }
            }
        }
        throw ShieldedError.proving("job \(job) did not finish in time")
    }

    /// Hands a message to the operator and waits until it is on layer 1 (or has failed).
    func deliver(kind: String, payloadHex: String, rollupAddress: String, token: String, timeout: Duration = .seconds(600)) async throws -> OperatorSubmission {
        try await awaitDelivery(of: try await submit(kind: kind, payloadHex: payloadHex, rollupAddress: rollupAddress, token: token), token: token, timeout: timeout)
    }

    /// Polls a submission until it is on layer 1 (or has failed).
    func awaitDelivery(of submitted: OperatorSubmission, token: String, timeout: Duration = .seconds(600)) async throws -> OperatorSubmission {
        var current = submitted
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !current.isTerminal {
            guard clock.now < deadline else {
                throw ShieldedError.submissionPending("submission \(current.id) is still \(current.status) after \(timeout)")
            }
            try await Task.sleep(for: .seconds(5))
            current = try await submission(id: current.id, token: token)
        }
        guard current.succeeded else { throw ShieldedError.submissionFailed(current.detail ?? "the operator marked submission \(current.id) \(current.status)") }
        return current
    }
}

/// The live services, read through `BoundedHTTP` (S19).
struct RollupNodeService: ShieldedRollup {
    let config: ShieldedConfig
    let session: URLSession

    init(config: ShieldedConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private static let smallReply = 16 << 10
    private static let noteReply = 64 << 10
    private static let pageReply = 4 << 20
    /// A proof bundle is a few hundred KB of hex; the kernel takes up to 8 MB of proof.
    private static let proofReply = 24 << 20
    private static let proofLimits = BoundedHTTP.JSONLimits(depth: 16, nodes: 10_000, string: 20 << 20)

    private func url(_ base: URL, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let trimmed = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = trimmed + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func getJSON(_ url: URL, limit: Int, json: BoundedHTTP.JSONLimits = .small, timeout: TimeInterval = 20, token: String? = nil) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: limit, json: json)
        guard reply.isSuccess else { throw Self.failure(reply, url: url) }
        return try JSONSerialization.jsonObject(with: reply.data, options: [.fragmentsAllowed])
    }

    private func postJSON(_ url: URL, body: [String: Any], limit: Int, json: BoundedHTTP.JSONLimits = .record, token: String? = nil) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: limit, json: json)
        guard reply.isSuccess else { throw Self.failure(reply, url: url) }
        return try JSONSerialization.jsonObject(with: reply.data, options: [.fragmentsAllowed])
    }

    private static func failure(_ reply: BoundedHTTP.Reply, url: URL) -> ShieldedError {
        let body = String(decoding: reply.data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let where_ = url.host() ?? url.absoluteString
        if reply.status == 401 || reply.status == 403 { return .operatorRefused("\(where_) did not accept the access token (HTTP \(reply.status))") }
        return .badReply("HTTP \(reply.status) from \(where_)\(body.isEmpty ? "" : ": \(body)")")
    }

    // MARK: Rollup node

    func head() async throws -> RollupHead {
        guard let hash = try await getJSON(url(config.rollupNode, "/global/block/head/hash"), limit: Self.smallReply) as? String, !hash.isEmpty else {
            throw ShieldedError.badReply("no head hash")
        }
        let level = try await getJSON(url(config.rollupNode, "/global/block/\(hash)/level"), limit: Self.smallReply)
        guard let number = (level as? NSNumber)?.intValue ?? (level as? String).flatMap(Int.init) else { throw ShieldedError.badReply("no head level") }
        return RollupHead(hash: hash, level: number)
    }

    func smartRollupAddress() async throws -> String {
        guard let address = try await getJSON(url(config.rollupNode, "/global/smart_rollup_address"), limit: Self.smallReply) as? String else {
            throw ShieldedError.badReply("no rollup address")
        }
        return address
    }

    func durableLength(block: String, key: String) async throws -> Int? {
        let value = try await getJSON(url(config.rollupNode, "/global/block/\(block)/durable/wasm_2_0_0/length", query: [URLQueryItem(name: "key", value: key)]), limit: Self.smallReply)
        switch value {
        case is NSNull: return nil
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text)
        default: throw ShieldedError.badReply("length of \(key)")
        }
    }

    func durableValue(block: String, key: String) async throws -> [UInt8]? {
        let value = try await getJSON(url(config.rollupNode, "/global/block/\(block)/durable/wasm_2_0_0/value", query: [URLQueryItem(name: "key", value: key)]), limit: Self.noteReply)
        switch value {
        case is NSNull: return nil
        case let text as String:
            let hex = text.hasPrefix("0x") ? String(text.dropFirst(2)) : text
            if hex.isEmpty { return [] }
            if let bytes = Hex.decode(hex) { return bytes }
            // The node answers a text value (the ticketer address) as the text itself.
            return Array(text.utf8)
        default: throw ShieldedError.badReply("value of \(key)")
        }
    }

    // MARK: Proving service

    func programHash(named program: String) async throws -> String {
        let reply = try await getJSON(url(config.provingURL, "/v1/programs"), limit: Self.smallReply)
        guard let programs = (reply as? [String: Any])?["programs"] as? [[String: Any]],
              let hash = programs.first(where: { $0["name"] as? String == program })?["program_hash"] as? String, Hex.decode(hash)?.count == 32
        else { throw ShieldedError.proving("the proving service has no program named \(program)") }
        return hash
    }

    func startProof(programHash: String, arguments: [String]) async throws -> String {
        let reply = try await postJSON(url(config.provingURL, "/v1/jobs"), body: ["program_hash": programHash, "arguments": arguments], limit: Self.smallReply)
        guard let id = (reply as? [String: Any])?["job_id"] as? String, !id.isEmpty, id.count < 200 else { throw ShieldedError.proving("the proving service returned no job id") }
        return id
    }

    func proofJob(id: String, lastStatus: String?) async throws -> ProofJob {
        var query = [URLQueryItem(name: "wait", value: "30")]
        if let lastStatus { query.append(URLQueryItem(name: "if_state_changed_from", value: lastStatus)) }
        let reply = try await getJSON(url(config.provingURL, "/v1/jobs/\(id)", query: query), limit: Self.proofReply, json: Self.proofLimits, timeout: 45)
        guard let object = reply as? [String: Any] else { throw ShieldedError.proving("unexpected job reply") }
        switch object["status"] as? String {
        case "queued": return .queued
        case "running": return .running
        case "done":
            guard let bundle = object["proof_bundle"] as? [String: Any], let proof = bundle["proof_bytes"] as? String, Hex.decode(proof) != nil,
                  let outputs = bundle["output_preimage"] as? [String], outputs.allSatisfy({ Hex.decode($0)?.count == 32 })
            else { throw ShieldedError.proving("the finished job carries no proof bundle") }
            return .done(ProofBundle(proofBytes: proof, outputPreimage: outputs))
        case "failed":
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? "unknown"
            return .failed(String(message.prefix(500)))
        case let other: return .unknown(other ?? "none")
        }
    }

    // MARK: Operator

    private static func parseSubmission(_ reply: Any) throws -> OperatorSubmission {
        guard let submission = (reply as? [String: Any])?["submission"] as? [String: Any], let id = submission["id"] as? String, let status = submission["status"] as? String else {
            throw ShieldedError.badReply("the operator returned no submission")
        }
        return OperatorSubmission(id: id, status: status, transport: submission["transport"] as? String, operationHash: submission["operation_hash"] as? String, detail: (submission["detail"] as? String).map { String($0.prefix(500)) })
    }

    func submit(kind: String, payloadHex: String, rollupAddress: String, token: String) async throws -> OperatorSubmission {
        try Self.parseSubmission(try await postJSON(url(config.operatorURL, "/v1/rollup/submissions"), body: ["kind": kind, "rollup_address": rollupAddress, "payload": payloadHex], limit: Self.noteReply, token: token))
    }

    func submission(id: String, token: String) async throws -> OperatorSubmission {
        try Self.parseSubmission(try await getJSON(url(config.operatorURL, "/v1/rollup/submissions/\(id)"), limit: Self.noteReply, json: .record, token: token))
    }

    // MARK: Outbox

    func cementedLevel() async throws -> Int {
        let level = try await getJSON(url(config.rollupNode, "/global/block/cemented/level"), limit: Self.smallReply)
        guard let number = (level as? NSNumber)?.intValue ?? (level as? String).flatMap(Int.init) else { throw ShieldedError.badReply("no cemented level") }
        return number
    }

    /// `/local/outbox/pending`: `[{outbox_level, messages: [{message_index, message: {transactions: [{destination, entrypoint, parameters}]}}]}]`.
    func pendingOutbox() async throws -> [OutboxEntry] {
        let reply = try await getJSON(url(config.rollupNode, "/local/outbox/pending"), limit: Self.pageReply, json: .page)
        guard let levels = reply as? [[String: Any]] else { throw ShieldedError.badReply("pending outbox") }
        var entries: [OutboxEntry] = []
        for level in levels {
            guard let outboxLevel = (level["outbox_level"] as? NSNumber)?.intValue ?? (level["outbox_level"] as? String).flatMap(Int.init),
                  let messages = level["messages"] as? [[String: Any]] else { continue }
            for message in messages {
                guard let index = (message["message_index"] as? NSNumber)?.intValue ?? (message["message_index"] as? String).flatMap(Int.init),
                      let transactions = (message["message"] as? [String: Any])?["transactions"] as? [[String: Any]], transactions.count == 1,
                      let transaction = transactions.first, let destination = transaction["destination"] as? String, let entrypoint = transaction["entrypoint"] as? String,
                      let entry = Self.burnEntry(outboxLevel: outboxLevel, index: index, destination: destination, entrypoint: entrypoint, parameters: transaction["parameters"])
                else { continue }
                entries.append(entry)
            }
        }
        return entries
    }

    /// The ticketer's `burn`: `Pair receiver (Pair ticketer (Pair (Pair 0 None) amount))`.
    static func burnEntry(outboxLevel: Int, index: Int, destination: String, entrypoint: String, parameters: Any?) -> OutboxEntry? {
        func args(_ node: Any?) -> [[String: Any]]? { ((node as? [String: Any])?["args"] as? [[String: Any]]) }
        guard let top = args(parameters), top.count == 2, let receiver = top[0]["bytes"] as? String,
              let second = args(top[1]), second.count == 2, let third = args(second[1]), third.count == 2,
              let amountText = third[1]["int"] as? String, let amount = UInt64(amountText)
        else { return nil }
        return OutboxEntry(outboxLevel: outboxLevel, messageIndex: index, destination: destination, entrypoint: entrypoint, receiver: receiver.lowercased(), amountMutez: amount)
    }

    func outboxProof(outboxLevel: Int, messageIndex: Int) async throws -> OutboxProof {
        let reply: Any
        do {
            reply = try await getJSON(url(config.rollupNode, "/global/block/cemented/helpers/proofs/outbox/\(outboxLevel)/messages", query: [URLQueryItem(name: "index", value: String(messageIndex))]), limit: Self.pageReply, json: .page, timeout: 60)
        } catch ShieldedError.badReply(let detail) where detail.contains("not_cemented") {
            throw ShieldedError.withdrawalNotReady("the rollup commitment covering it is not cemented yet (about 14 days after the unshield)")
        }
        guard let object = reply as? [String: Any], let commitment = object["commitment"] as? String, commitment.hasPrefix("src1"),
              let proof = object["proof"] as? String, Hex.decode(proof) != nil, !proof.isEmpty
        else { throw ShieldedError.badReply("outbox proof") }
        return OutboxProof(commitment: commitment, proof: proof)
    }
}
