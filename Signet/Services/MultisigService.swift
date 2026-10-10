import Foundation

/// Octez-client's generic multisig, through the bridge (`TaquitoBridge/src/multisig.js`).
protocol MultisigService: Sendable {
    /// Counter, threshold, keys, balance and whether the code is the generic multisig script.
    func info(rpcURL: URL, address: Address) async throws -> MultisigInfo
    /// The public key an account has revealed on chain (needed to make it a signer), or `nil`.
    func revealedPublicKey(rpcURL: URL, address: Address) async throws -> String?
    func estimateOriginate(rpcURL: URL, from wallet: Wallet, threshold: Int, keys: [String]) async throws -> MultisigEstimate
    /// Deploys a multisig and waits one block. Returns the operation hash and the new address.
    func originate(rpcURL: URL, signer: SigningKey, threshold: Int, keys: [String]) async throws -> (hash: String, address: Address)
    /// The contract's state plus the bytes every signer signs for this action at its current counter.
    func prepare(rpcURL: URL, contract: Address, action: MultisigAction) async throws -> (info: MultisigInfo, chainID: String, bytes: String)
    func estimateSubmit(rpcURL: URL, from wallet: Wallet, proposal: MultisigProposal, signatures: [String]) async throws -> MultisigEstimate
    /// Calls the contract's `main` entrypoint with the signatures and waits one block. Returns the operation hash.
    func submit(rpcURL: URL, signer: SigningKey, proposal: MultisigProposal, signatures: [String]) async throws -> String
}

struct BridgeMultisigService: MultisigService {
    let bridge: TaquitoBridge

    init(bridge: TaquitoBridge = .shared) { self.bridge = bridge }

    static func info(from r: JSONValue) throws -> MultisigInfo {
        guard let address = r["address"]?.stringValue, let generic = r["isGenericMultisig"]?.boolValue, let hash = r["scriptHash"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected multisig payload: \(String(describing: r))")
        }
        return MultisigInfo(
            address: Address(address),
            isGenericMultisig: generic,
            scriptHash: hash,
            counter: Int(r["counter"]?.stringValue ?? "") ?? 0,
            threshold: Int(r["threshold"]?.stringValue ?? "") ?? 0,
            keys: r["keys"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            balance: Mutez.toTez(r["balanceMutez"]?.stringValue) ?? 0
        )
    }

    private static func estimate(from r: JSONValue) throws -> MultisigEstimate {
        guard let fee = Mutez.toTez(r["feeMutez"]?.stringValue), let burn = Mutez.toTez(r["burnMutez"]?.stringValue) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected estimate payload: \(String(describing: r))")
        }
        return MultisigEstimate(fee: fee, burn: burn, total: fee + burn, gasLimit: Int(r["gasLimit"]?.doubleValue ?? 0), storageLimit: Int(r["storageLimit"]?.doubleValue ?? 0))
    }

    private static func json(_ object: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    /// The action as `multisig.js` reads it.
    static func json(_ action: MultisigAction) throws -> String {
        switch action {
        case .transfer(let amountMutez, let destination):
            try json(["kind": "transfer", "amountMutez": amountMutez, "destination": destination])
        case .setDelegate(let delegate):
            try json(["kind": "delegate", "delegate": delegate.map { $0 as Any } ?? NSNull()] as [String: Any])
        }
    }

    func info(rpcURL: URL, address: Address) async throws -> MultisigInfo {
        try Self.info(from: try await bridge.call("multisigInfo", [rpcURL.absoluteString, address.value]))
    }

    func revealedPublicKey(rpcURL: URL, address: Address) async throws -> String? {
        try await bridge.call("multisigRevealedKey", [rpcURL.absoluteString, address.value])["publicKey"]?.stringValue
    }

    func estimateOriginate(rpcURL: URL, from wallet: Wallet, threshold: Int, keys: [String]) async throws -> MultisigEstimate {
        guard let publicKey = wallet.publicKey else { throw TaquitoBridge.BridgeError.javaScript("Account “\(wallet.alias)” has no public key, so its fees cannot be estimated.") }
        return try Self.estimate(from: try await bridge.call("multisigEstimateOriginate", [rpcURL.absoluteString, wallet.address.value, publicKey, threshold, try Self.json(keys)]))
    }

    func originate(rpcURL: URL, signer: SigningKey, threshold: Int, keys: [String]) async throws -> (hash: String, address: Address) {
        let r = try await bridge.call("multisigOriginate", [rpcURL.absoluteString, signer.bridgeSpec, threshold, try Self.json(keys)])
        guard let hash = r["hash"]?.stringValue, let address = r["address"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected origination payload: \(String(describing: r))") }
        return (hash, Address(address))
    }

    func prepare(rpcURL: URL, contract: Address, action: MultisigAction) async throws -> (info: MultisigInfo, chainID: String, bytes: String) {
        let r = try await bridge.call("multisigPrepare", [rpcURL.absoluteString, contract.value, try Self.json(action)])
        guard let chainID = r["chainId"]?.stringValue, let bytes = r["bytes"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected prepare payload: \(String(describing: r))") }
        return (try Self.info(from: r), chainID, bytes)
    }

    func estimateSubmit(rpcURL: URL, from wallet: Wallet, proposal: MultisigProposal, signatures: [String]) async throws -> MultisigEstimate {
        guard let publicKey = wallet.publicKey else { throw TaquitoBridge.BridgeError.javaScript("Account “\(wallet.alias)” has no public key, so its fees cannot be estimated.") }
        return try Self.estimate(from: try await bridge.call("multisigEstimateSubmit", [
            rpcURL.absoluteString, wallet.address.value, publicKey, proposal.contractAddress, try Self.json(proposal.action), proposal.counter, try Self.json(signatures),
        ]))
    }

    func submit(rpcURL: URL, signer: SigningKey, proposal: MultisigProposal, signatures: [String]) async throws -> String {
        let r = try await bridge.call("multisigSubmit", [
            rpcURL.absoluteString, signer.bridgeSpec, proposal.contractAddress, try Self.json(proposal.action), proposal.counter, try Self.json(signatures),
        ])
        guard let hash = r["hash"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected submit payload: \(String(describing: r))") }
        return hash
    }
}

/// For previews and tests: one generic multisig whose keys are whatever the test says.
final class MockMultisigService: MultisigService, @unchecked Sendable {
    static let sampleAddress = Address("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")
    var keys: [String]
    var threshold: Int
    var counter = 3
    var isGeneric = true
    var balance: Decimal = 12
    /// Public keys "revealed on chain" by address, for the tz-address path of Create.
    var revealed: [String: String] = [:]
    private(set) var submitted: [(proposal: MultisigProposal, signatures: [String])] = []

    init(keys: [String] = ["edpkMOCK1", "edpkMOCK2", "edpkMOCK3"], threshold: Int = 2) {
        self.keys = keys
        self.threshold = threshold
    }

    private func info(_ address: Address) -> MultisigInfo {
        MultisigInfo(address: address, isGenericMultisig: isGeneric, scriptHash: isGeneric ? "exprub9UzpxmhedNQnsv1J1DazWGJnj1dLhtG1fxkUoWSdFLBGLqJ4" : "exprOTHER",
                     counter: counter, threshold: threshold, keys: keys, balance: balance)
    }

    func info(rpcURL: URL, address: Address) async throws -> MultisigInfo { info(address) }
    func revealedPublicKey(rpcURL: URL, address: Address) async throws -> String? { revealed[address.value] }
    func estimateOriginate(rpcURL: URL, from wallet: Wallet, threshold: Int, keys: [String]) async throws -> MultisigEstimate {
        MultisigEstimate(fee: 0.002, burn: 0.5, total: 0.502, gasLimit: 1000, storageLimit: 500)
    }
    func originate(rpcURL: URL, signer: SigningKey, threshold: Int, keys: [String]) async throws -> (hash: String, address: Address) {
        self.keys = keys; self.threshold = threshold; counter = 0
        return ("ooMockOrigination", Self.sampleAddress)
    }
    func prepare(rpcURL: URL, contract: Address, action: MultisigAction) async throws -> (info: MultisigInfo, chainID: String, bytes: String) {
        // Different actions must give different bytes, as they do for real.
        let tag = switch action { case .transfer(let m, let d): "01" + m + d; case .setDelegate(let d?): "02" + d; case .setDelegate(nil): "03" }
        return (info(contract), "NetXMock", "0507070a00000004" + String(tag.utf8.map { String(format: "%02x", $0) }.joined()))
    }
    func estimateSubmit(rpcURL: URL, from wallet: Wallet, proposal: MultisigProposal, signatures: [String]) async throws -> MultisigEstimate {
        MultisigEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 1000, storageLimit: 0)
    }
    func submit(rpcURL: URL, signer: SigningKey, proposal: MultisigProposal, signatures: [String]) async throws -> String {
        submitted.append((proposal, signatures)); counter += 1
        return "ooMockSubmit"
    }
}

// MARK: - Proposals on disk

/// Proposals awaiting signatures, kept beside the wallet files.
protocol MultisigProposalStore: Sendable {
    func load() -> [MultisigProposal]
    func save(_ proposals: [MultisigProposal]) throws
}

/// `<wallet dir>/multisig-proposals.json`.
struct FileMultisigProposalStore: MultisigProposalStore {
    static let fileName = "multisig-proposals.json"
    let url: URL

    init(directory: URL) { url = directory.appendingPathComponent(Self.fileName) }

    func load() -> [MultisigProposal] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MultisigProposal].self, from: data)) ?? []
    }

    func save(_ proposals: [MultisigProposal]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(proposals).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

final class InMemoryMultisigProposalStore: MultisigProposalStore, @unchecked Sendable {
    private let lock = NSLock()
    private var proposals: [MultisigProposal] = []
    func load() -> [MultisigProposal] { lock.withLock { proposals } }
    func save(_ proposals: [MultisigProposal]) throws { lock.withLock { self.proposals = proposals } }
}
