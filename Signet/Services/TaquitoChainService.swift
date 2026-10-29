import Foundation

/// Live chain access through the Taquito bridge.
struct TaquitoChainService: ChainService {
    let network: Network
    let bridge: TaquitoBridge
    let session: URLSession

    init(network: Network = .mainnet, bridge: TaquitoBridge = .shared, session: URLSession = .shared) {
        self.network = network
        self.bridge = bridge
        self.session = session
    }

    func tezBalance(for address: Address) async throws -> TezBalance {
        // The Michelson interface has no staking and no full_balance: `balance` is the whole story,
        // and an account the rollup has never seen is simply 0.
        if network.layerNumber == 2 {
            let mutez = try await rpcMutez("balance", for: address)
            guard let balance = TezBalance(mutezSpendable: mutez, staked: "0", unstakedFrozen: "0", unstakedFinalizable: "0") else {
                throw URLError(.cannotParseResponse)
            }
            return balance
        }
        // Taquito rejects tz5/tz6 addresses, so ask the node directly for those.
        if let scheme = address.scheme, !scheme.isSupported {
            return try await directTezBalance(for: address)
        }
        let result = try await bridge.call("getTezBalances", [network.rpcURL.absoluteString, address.value])
        if result["exists"] == .bool(false) { throw ChainError.accountNotOnChain(address) }
        guard let balance = TezBalance(
            mutezSpendable: result["spendable"]?.stringValue,
            staked: result["staked"]?.stringValue,
            unstakedFrozen: result["unstakedFrozen"]?.stringValue,
            unstakedFinalizable: result["unstakedFinalizable"]?.stringValue
        ) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected balance payload: \(String(describing: result))")
        }
        return balance
    }

    /// The same breakdown straight from the node: `/context/contracts/<pkh>/{spendable,staked_balance,...}`.
    func directTezBalance(for address: Address) async throws -> TezBalance {
        // full_balance is refused with a "missing_key" storage error for accounts the chain has never seen.
        do {
            _ = try await rpcMutez("full_balance", for: address)
        } catch let error as RPCError where error.body.contains("missing_key") || error.body.contains("storage_error") {
            throw ChainError.accountNotOnChain(address)
        }
        async let spendable = rpcMutez("spendable", for: address)
        async let staked = rpcMutez("staked_balance", for: address)
        async let frozen = rpcMutez("unstaked_frozen_balance", for: address)
        async let finalizable = rpcMutez("unstaked_finalizable_balance", for: address)
        guard let balance = TezBalance(mutezSpendable: try await spendable, staked: try await staked,
                                       unstakedFrozen: try await frozen, unstakedFinalizable: try await finalizable)
        else { throw URLError(.cannotParseResponse) }
        return balance
    }

    /// `GET /chains/main/blocks/head/context/contracts/<pkh>/<field>` → `"<mutez>"`.
    private func rpcMutez(_ field: String, for address: Address) async throws -> String {
        try await rpcMutez(field, for: address, at: network.rpcURL)
    }

    private func rpcMutez(_ field: String, for address: Address, at node: URL) async throws -> String {
        let url = node.appendingPathComponent("chains/main/blocks/head/context/contracts/\(address.value)/\(field)")
        let reply = try await BoundedHTTP.data(for: URLRequest(url: url), session: session, limit: Self.smallReplyBytes)
        guard reply.isSuccess else {
            throw RPCError(status: reply.status, field: field, address: address, body: String(data: reply.data, encoding: .utf8) ?? "")
        }
        guard let text = try JSONSerialization.jsonObject(with: reply.data, options: [.fragmentsAllowed]) as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    /// `GET <node>/<path>` → a JSON string (such as `/chains/main/chain_id`).
    private func rpcString(_ path: String, at node: URL) async throws -> String {
        var request = URLRequest(url: node.appendingPathComponent(path))
        request.timeoutInterval = 20
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.smallReplyBytes)
        guard reply.isSuccess, let text = try JSONSerialization.jsonObject(with: reply.data, options: [.fragmentsAllowed]) as? String else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    /// A balance, a chain id: a short JSON string, or a short error body (S19).
    static let smallReplyBytes = 16 << 10

    /// The account's tez on Etherlink, through the rollup's Tezos-style RPC (`Network.l2RPCURL`):
    /// the same `…/contracts/<pkh>/balance` call as a layer 1 node answers. An account the
    /// rollup has never seen is simply 0. The node must report the pinned Etherlink chain id.
    func etherlinkBalance(for address: Address) async throws -> Decimal {
        guard network.hasL2, let l2 = network.l2RPCURL else { throw ChainError.noEtherlinkNode }
        if let expected = network.expectedL2ChainID {
            let found = try await rpcString("chains/main/chain_id", at: l2)
            guard found == expected else { throw ChainError.wrongChain(expected: expected, found: found) }
        }
        let mutez = try await rpcMutez("balance", for: address, at: l2)
        guard let amount = Decimal(string: mutez) else { throw URLError(.cannotParseResponse) }
        return amount / Mutez.perTez
    }

    func recentTransactions(for address: Address, limit: Int) async throws -> [TezosTransaction] {
        guard let tzkt = network.tzktURL else { return [] }
        do {
            return try await TzKTService(baseURL: tzkt, session: session).recentOperations(for: address, limit: limit)
        } catch {
            NSLog("TzKT history lookup failed for %@: %@", address.value, error.localizedDescription)
            return []
        }
    }

    func resolveDomain(_ name: String) async throws -> Address? {
        guard let endpoint = network.tezosDomainsURL else { return nil }
        return try await TezosDomainsService(endpoint: endpoint, session: session).resolve(name: name)
    }

    /// Always mainnet: TzProfiles are mainnet identities regardless of the network in use.
    func accountProfile(for address: Address) async throws -> AccountProfile? {
        try await TzKTService(baseURL: Profiles.profileIndexer, session: session).accountProfile(for: address)
    }

    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateTransfer", [network.rpcURL.absoluteString, wallet.address.value, publicKey, destination.value, Mutez.fromTez(amount)], timeout: 120) }
        return try Self.estimate(from: result, amount: amount)
    }

    /// The `publicKey` argument of the bridge's estimates: the key alone, or, for a tz4 account
    /// whose proof of possession has been made, the key and the proof the reveal will carry.
    static func publicKeyArgument(for wallet: Wallet) throws -> any Sendable {
        guard let publicKey = wallet.publicKey else {
            throw TaquitoBridge.BridgeError.javaScript("Account “\(wallet.alias)” has no public key, so its fees cannot be estimated.")
        }
        if wallet.scheme == .tz4, let proof = wallet.proofOfPossession { return ["publicKey": publicKey, "proof": proof] }
        return publicKey
    }

    /// An estimate as the bridge reports it: fee, burn and the limits to send with (S14, S20).
    static func estimate(from result: JSONValue, amount: Decimal = 0) throws -> TransferEstimate {
        guard let fee = Mutez.toTez(result["feeMutez"]?.stringValue),
              let burn = Mutez.toTez(result["burnMutez"]?.stringValue),
              let gasLimit = result["gasLimit"]?.intValue, let storageLimit = result["storageLimit"]?.intValue,
              let limits = OperationLimits(result["limits"])
        else { throw TaquitoBridge.BridgeError.javaScript("unexpected estimate payload: \(String(describing: result))") }
        return TransferEstimate(fee: fee, burn: burn, total: amount + fee + burn, gasLimit: gasLimit, storageLimit: storageLimit, limits: limits)
    }

    /// Refuses the node before anything is estimated or signed when it serves another chain (S12).
    func verifyChain() async throws {
        guard let expected = network.expectedChainID else { return }
        _ = try await bridge.call("assertChain", [network.rpcURL.absoluteString, expected], timeout: 60)
    }

    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendTransfer", [network.rpcURL.absoluteString, signer.bridgeSpec, destination.value, Mutez.fromTez(amount), limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected send payload: \(String(describing: result))")
        }
        return sent
    }

    func estimateEtherlinkDeposit(from wallet: Wallet, amount: Decimal) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        guard network.canDepositToL2, let helper = network.l2BridgeHelper, let rollup = network.l2Rollup else { throw ChainError.noEtherlinkBridge }
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateEtherlinkDeposit", [network.rpcURL.absoluteString, wallet.address.value, publicKey, helper.value, rollup, wallet.address.value, Mutez.fromTez(amount)], timeout: 120) }
        return try Self.estimate(from: result, amount: amount)
    }

    func sendEtherlinkDeposit(from wallet: Wallet, signer: SigningKey, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
        guard network.canDepositToL2, let helper = network.l2BridgeHelper, let rollup = network.l2Rollup else { throw ChainError.noEtherlinkBridge }
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendEtherlinkDeposit", [network.rpcURL.absoluteString, signer.bridgeSpec, helper.value, rollup, wallet.address.value, Mutez.fromTez(amount), limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected deposit payload: \(String(describing: result))")
        }
        return sent
    }

    // MARK: Shielded tez (TzEL)

    func estimateShieldDeposit(from wallet: Wallet, deposit: ShieldDeposit) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateShieldDeposit", [network.rpcURL.absoluteString, wallet.address.value, publicKey, deposit.ticketer.value, deposit.rollup, deposit.pubkeyHash, Mutez.fromTez(deposit.amount)], timeout: 120) }
        return try Self.estimate(from: result, amount: deposit.amount)
    }

    func sendShieldDeposit(from wallet: Wallet, signer: SigningKey, deposit: ShieldDeposit, limits: OperationLimits) async throws -> SentOperation {
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendShieldDeposit", [network.rpcURL.absoluteString, signer.bridgeSpec, deposit.ticketer.value, deposit.rollup, deposit.pubkeyHash, Mutez.fromTez(deposit.amount), limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected deposit payload: \(String(describing: result))")
        }
        return sent
    }

    func estimateOutboxExecution(from wallet: Wallet, execution: OutboxExecution) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateOutboxExecution", [network.rpcURL.absoluteString, wallet.address.value, publicKey, execution.rollup, execution.cementedCommitment, execution.outputProof], timeout: 120) }
        return try Self.estimate(from: result, amount: 0)
    }

    func sendOutboxExecution(from wallet: Wallet, signer: SigningKey, execution: OutboxExecution, limits: OperationLimits) async throws -> SentOperation {
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendOutboxExecution", [network.rpcURL.absoluteString, signer.bridgeSpec, execution.rollup, execution.cementedCommitment, execution.outputProof, limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected outbox execution payload: \(String(describing: result))")
        }
        return sent
    }

    // MARK: Etherlink alias (0.9.3), on the Layer 2 service

    /// Asks the gateway's `resolveAddress` view (Tezos runtime 0 → Ethereum runtime 1) on the
    /// Layer 2 node: `Some (Pair 0 addr)` is recorded, `Some (Pair 1 addr)` only derived.
    func etherlinkAliasStatus(for address: Address) async throws -> EtherlinkAliasStatus {
        guard network.layerNumber == 2 else { throw ChainError.notALayer2Service }
        try await verifyChain()
        var request = URLRequest(url: network.rpcURL.appendingPathComponent("chains/main/blocks/head/helpers/scripts/run_script_view"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contract": Network.etherlinkGateway.value, "view": "resolveAddress",
            "input": ["prim": "Pair", "args": [["string": address.value], ["int": "0"], ["int": "1"]]],
            "chain_id": network.expectedChainID ?? "", "unparsing_mode": "Readable",
        ])
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.smallReplyBytes)
        guard reply.isSuccess else { throw URLError(.badServerResponse) }
        return try Self.aliasStatus(from: reply.data, for: address)
    }

    /// Pure parser for the view's reply; the address it names must be the one we derive.
    static func aliasStatus(from data: Data, for address: Address) throws -> EtherlinkAliasStatus {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let some = object["data"] as? [String: Any], some["prim"] as? String == "Some",
              let pair = (some["args"] as? [[String: Any]])?.first, pair["prim"] as? String == "Pair",
              let args = pair["args"] as? [[String: Any]], args.count == 2,
              let kind = args[0]["int"] as? String, let named = args[1]["string"] as? String
        else { throw URLError(.cannotParseResponse) }
        let expected = EtherlinkAlias.address(for: address)
        guard named.lowercased() == expected else { throw URLError(.cannotParseResponse) }
        switch kind {
        case "0": return .linked(evmAddress: expected)
        case "1": return .unlinked(evmAddress: expected)
        default: throw URLError(.cannotParseResponse)
        }
    }

    func estimateEtherlinkLink(from wallet: Wallet) async throws -> TransferEstimate {
        guard network.layerNumber == 2 else { throw ChainError.notALayer2Service }
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateEtherlinkLink", [network.rpcURL.absoluteString, wallet.address.value, publicKey, Network.etherlinkGateway.value], timeout: 120) }
        return try Self.estimate(from: result)
    }

    func sendEtherlinkLink(from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        guard network.layerNumber == 2 else { throw ChainError.notALayer2Service }
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendEtherlinkLink", [network.rpcURL.absoluteString, signer.bridgeSpec, Network.etherlinkGateway.value, limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected link payload: \(String(describing: result))")
        }
        return sent
    }

    func pendingOperation(for address: Address) async throws -> SentOperation? {
        try await verifyChain()
        let value = try await bridge.call("pendingOperation", [network.rpcURL.absoluteString, address.value], timeout: 30)
        return value == .null ? nil : SentOperation(value)
    }

    func rebroadcast(_ sent: SentOperation) async throws -> SentOperation {
        guard let bytes = sent.signedBytes else { throw TaquitoBridge.BridgeError.javaScript("There are no signed bytes to send again for \(sent.hash).") }
        let result = try await bridge.sign("injectSignedBytes", [network.rpcURL.absoluteString, bytes])
        guard let again = SentOperation(result) else { throw TaquitoBridge.BridgeError.javaScript("unexpected injection payload: \(String(describing: result))") }
        return again
    }

    /// Runs a bridge call that signs, turning the bridge's error text for wrong passwords and
    /// Ledger trouble into `ChainError`s the UI can word properly.
    private func signing(_ body: () async throws -> JSONValue) async throws -> JSONValue {
        try await TaquitoBridge.BridgeError.typed(body)
    }

    /// Every operation is forged and injected locally, so the block watcher is the one way to
    /// see it land: it scans up to 15 blocks from the recorded level and returns the block's.
    func waitForConfirmation(of operationHash: String) async throws -> Int {
        let result = try await bridge.call("waitForRawOperation", [network.rpcURL.absoluteString, operationHash, 15])
        guard let level = result.intValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected confirmation payload: \(String(describing: result))") }
        return level
    }

    func delegateInfo(for address: Address) async throws -> DelegateInfo {
        let r = try await bridge.call("getDelegateInfo", [network.rpcURL.absoluteString, address.value])
        var baker: DelegateInfo.Baker?
        if let b = r["baker"], b != .null, b.objectValue != nil {
            baker = DelegateInfo.Baker(
                deactivated: b["deactivated"]?.boolValue ?? false,
                gracePeriod: b["gracePeriod"]?.intValue,
                consensusKey: b["consensusKey"]?.stringValue.map(Address.init),
                pendingConsensusKeys: b["pendingConsensusKeys"]?.arrayValue?.compactMap { $0["key"]?.stringValue.map(Address.init) } ?? [],
                companionKey: b["companionKey"]?.stringValue.map(Address.init),
                pendingCompanionKeys: b["pendingCompanionKeys"]?.arrayValue?.compactMap { $0["key"]?.stringValue.map(Address.init) } ?? []
            )
            if let p = b["stakingParameters"], let limit = p["limitMillionth"]?.intValue, let edge = p["edgeBillionth"]?.intValue {
                baker?.stakingParameters = StakingParameters(limitMillionth: limit, edgeBillionth: edge)
            }
            baker?.pendingStakingParameters = b["pendingStakingParameters"]?.arrayValue?.compactMap { p in
                guard let limit = p["limitMillionth"]?.intValue, let edge = p["edgeBillionth"]?.intValue else { return nil }
                return StakingParameters(limitMillionth: limit, edgeBillionth: edge, cycle: p["cycle"]?.intValue)
            } ?? []
        }
        return DelegateInfo(delegate: r["delegate"]?.stringValue.map(Address.init), baker: baker, delegateAcceptsStaking: r["acceptsStaking"]?.boolValue)
    }

    func bakers(limit: Int) async throws -> [BakerCandidate] {
        guard let tzkt = network.tzktURL else { return [] }
        return try await TzKTService(baseURL: tzkt, session: session).bakers(limit: limit)
    }

    /// Operations Taquito cannot encode itself (keys of schemes it does not know) go through the node.
    private func rawContents(for operation: StakingOperation) -> [[String: Any]]? {
        switch operation {
        case .updateConsensusKey(let pk, let proof) where !Self.taquitoEncodablePublicKey(pk):
            return [["kind": "update_consensus_key", "pk": pk] .merging(proof.map { ["proof": $0] } ?? [:]) { $1 }]
        case .updateCompanionKey(let pk, let proof) where !Self.taquitoEncodablePublicKey(pk):
            return [["kind": "update_companion_key", "pk": pk].merging(proof.map { ["proof": $0] } ?? [:]) { $1 }]
        default:
            return nil
        }
    }

    static func taquitoEncodablePublicKey(_ pk: String) -> Bool {
        ["edpk", "sppk", "p2pk", "BLpk", "mdpk"].contains { pk.hasPrefix($0) }
    }

    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        if let contents = rawContents(for: operation) {
            let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
            return try Self.estimate(from: try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateRawOperation", [network.rpcURL.absoluteString, wallet.address.value, publicKey, json], timeout: 120) })
        }
        let arg = String(data: try JSONSerialization.data(withJSONObject: operation.bridgeArgument), encoding: .utf8)!
        let r = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateStakingOperation", [network.rpcURL.absoluteString, wallet.address.value, publicKey, operation.bridgeKind, arg], timeout: 120) }
        let amount: Decimal = { if case .stake(let a) = operation { return a } else { return 0 } }()
        return try Self.estimate(from: r, amount: amount)
    }

    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        try await verifyChain()
        let r = try await signing {
            if let contents = rawContents(for: operation) {
                let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
                return try await bridge.sign("sendRawOperation", [network.rpcURL.absoluteString, signer.bridgeSpec, json, limits.json])
            } else {
                let arg = String(data: try JSONSerialization.data(withJSONObject: operation.bridgeArgument), encoding: .utf8)!
                return try await bridge.sign("sendStakingOperation", [network.rpcURL.absoluteString, signer.bridgeSpec, operation.bridgeKind, arg, limits.json])
            }
        }
        guard let sent = SentOperation(r) else { throw TaquitoBridge.BridgeError.javaScript("unexpected payload: \(String(describing: r))") }
        return sent
    }

    func proofOfPossession(signer: SigningKey) async throws -> String {
        let r = try await signing { try await bridge.sign("provePossession", [signer.bridgeSpec]) }
        guard let proof = r["proof"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no proof returned") }
        return proof
    }

    /// Fungible tokens from TzKT. Indexer trouble is logged and shown as an empty list.
    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload {
        let r = try await signing { try await bridge.sign("signPayload", [signer.bridgeSpec, payloadHex]) }
        guard let pk = r["publicKey"]?.stringValue, let signature = r["signature"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected signature payload: \(String(describing: r))")
        }
        return SignedPayload(publicKey: pk, signature: signature)
    }

    func governanceInfo(for address: Address) async throws -> GovernanceInfo {
        Self.governanceInfo(from: try await bridge.call("getGovernanceInfo", [network.rpcURL.absoluteString, address.value]))
    }

    static func governanceInfo(from r: JSONValue) -> GovernanceInfo {
        let decimal = { (v: JSONValue?) -> Decimal in v?.stringValue.flatMap { Decimal(string: $0) } ?? v?.doubleValue.map { Decimal($0) } ?? 0 }
        var info = GovernanceInfo()
        info.kind = r["kind"]?.stringValue.flatMap(VotingPeriodKind.init(rawValue:))
        info.index = r["index"]?.intValue
        info.position = r["position"]?.intValue
        info.remaining = r["remaining"]?.intValue
        info.proposals = (r["proposals"]?.arrayValue ?? []).compactMap { p in
            p["hash"]?.stringValue.map { GovernanceInfo.Proposal(hash: $0, votingPower: decimal(p["votingPower"])) }
        }.sorted { $0.votingPower > $1.votingPower }
        info.currentProposal = r["currentProposal"]?.stringValue
        info.votingPower = r["votingPower"]?.stringValue.flatMap { Decimal(string: $0) }
        info.totalVotingPower = decimal(r["totalVotingPower"])
        info.quorumPerTenThousand = r["quorumPerTenThousand"]?.intValue
        info.ballots = GovernanceInfo.Ballots(yay: decimal(r["ballots"]?["yay"]), nay: decimal(r["ballots"]?["nay"]), pass: decimal(r["ballots"]?["pass"]))
        info.myBallot = r["myBallot"]?.stringValue.flatMap(BallotVote.init(rawValue:))
        info.proposalCount = r["proposalCount"]?.intValue ?? 0
        return info
    }

    func performGovernance(_ operation: GovernanceOperation, from wallet: Wallet, signer: SigningKey) async throws -> String {
        try await verifyChain()
        let arg = String(data: try JSONSerialization.data(withJSONObject: operation.bridgeArgument), encoding: .utf8)!
        let r = try await signing { try await bridge.sign("sendGovernanceOperation", [network.rpcURL.absoluteString, signer.bridgeSpec, operation.bridgeKind, arg]) }
        guard let hash = r["hash"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected payload: \(String(describing: r))") }
        return hash
    }

    // MARK: Etherlink governance (layer 1 contracts)

    func etherlinkVotingRights(for address: Address, contract: Address) async throws -> [Address] {
        try await verifyChain()
        let r = try await bridge.call("etherlinkVotingRights", [network.rpcURL.absoluteString, contract.value, address.value], timeout: 60)
        guard let list = r.arrayValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected voting rights payload: \(String(describing: r))") }
        return try list.map {
            guard let value = $0.stringValue, Address(value).isValidAccount else { throw TaquitoBridge.BridgeError.javaScript("unexpected voting rights payload: \(String(describing: r))") }
            return Address(value)
        }
    }

    func etherlinkGovernanceState(contract: Address, for address: Address) async throws -> EtherlinkGovernance.State {
        try await verifyChain()
        let r = try await bridge.call("getEtherlinkGovernanceState", [network.rpcURL.absoluteString, contract.value, address.value, network.tzktURL?.absoluteString ?? ""], timeout: 90)
        return try Self.etherlinkGovernanceState(from: r, contract: contract)
    }

    /// Pure parser for the bridge's state payload (S20: every number is checked).
    static func etherlinkGovernanceState(from r: JSONValue, contract: Address) throws -> EtherlinkGovernance.State {
        func bad() -> TaquitoBridge.BridgeError { .javaScript("unexpected governance state payload: \(String(describing: r))") }
        func power(_ v: JSONValue?) throws -> Decimal {
            guard let text = v?.stringValue, Mutez.isValid(text), let value = Decimal(string: text) else { throw bad() }
            return value
        }
        func count(_ v: JSONValue?) throws -> Int {
            guard let n = v?.intValue, n >= 0 else { throw bad() }
            return n
        }
        var state = EtherlinkGovernance.State(contract: contract)
        state.periodIndex = try count(r["periodIndex"])
        guard let kind = r["periodKind"]?.stringValue.flatMap(EtherlinkGovernance.PeriodKind.init(rawValue:)) else { throw bad() }
        state.periodKind = kind
        state.remainingBlocks = try count(r["remainingBlocks"])
        let c = r["config"]
        state.config = EtherlinkGovernance.Config(periodLength: try count(c?["periodLength"]), upvotingLimit: try count(c?["upvotingLimit"]), scale: try count(c?["scale"]),
                                                  proposalQuorum: try count(c?["proposalQuorum"]), promotionQuorum: try count(c?["promotionQuorum"]), promotionSupermajority: try count(c?["promotionSupermajority"]))
        state.totalVotingPower = try power(r["totalVotingPower"])
        state.proposals = try (r["proposals"]?.arrayValue ?? []).map { p in
            guard let hash = p["hash"]?.stringValue.flatMap(EtherlinkGovernance.kernelHash(from:)) else { throw bad() }
            let proposers = (p["proposers"]?.arrayValue ?? []).compactMap { $0.stringValue }.map(Address.init)
            return EtherlinkGovernance.Proposal(hash: hash, proposers: proposers, upvotes: try power(p["upvotes"]), upvoted: p["upvoted"]?.boolValue ?? false)
        }
        state.proposalsKnown = r["proposalsKnown"]?.boolValue ?? true
        if let candidate = r["candidate"]?.stringValue {
            guard let hash = EtherlinkGovernance.kernelHash(from: candidate) else { throw bad() }
            state.candidate = hash
        }
        state.tallies = EtherlinkGovernance.Tallies(yea: try power(r["tallies"]?["yea"]), nay: try power(r["tallies"]?["nay"]), pass: try power(r["tallies"]?["pass"]))
        state.votingPower = try power(r["votingPower"])
        state.votesFor = (r["votesFor"]?.arrayValue ?? []).compactMap { $0.stringValue }.map(Address.init)
        state.upvotesUsed = try count(r["upvotesUsed"])
        state.myVote = r["myVote"]?.stringValue.flatMap(EtherlinkGovernance.Vote.init(rawValue:))
        return state
    }

    func estimateEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet) async throws -> TransferEstimate {
        let publicKey = try Self.publicKeyArgument(for: wallet)
        try await verifyChain()
        let result = try await TaquitoBridge.BridgeError.typed { try await bridge.call("estimateEtherlinkGovernance", [network.rpcURL.absoluteString, wallet.address.value, publicKey, contract.value, operation.entrypoint, operation.payload], timeout: 120) }
        return try Self.estimate(from: result)
    }

    func sendEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        try await verifyChain()
        let result = try await signing { try await bridge.sign("sendEtherlinkGovernance", [network.rpcURL.absoluteString, signer.bridgeSpec, contract.value, operation.entrypoint, operation.payload, limits.json]) }
        guard let sent = SentOperation(result) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected governance payload: \(String(describing: result))")
        }
        return sent
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        guard let tzkt = network.tzktURL else { return [] }
        return try await TzKTService(baseURL: tzkt, session: session).fungibleTokens(for: address)
    }

    /// One paginated indexer snapshot for both tabs. Indexer trouble is reported as
    /// `.unavailable`, never as an account with nothing in it (S26).
    func portfolio(for address: Address) async throws -> Portfolio {
        guard let tzkt = network.tzktURL else { return .empty }
        do {
            return try await TzKTService(baseURL: tzkt, session: session).portfolio(for: address)
        } catch {
            NSLog("TzKT portfolio lookup failed for %@: %@", address.value, error.localizedDescription)
            return Portfolio(tokens: [], nfts: [], state: .unavailable(error.localizedDescription))
        }
    }

    /// The address's published Tezos Domains name, if any. A lookup failure is logged and
    /// treated as "no name" so a flaky domains API never hides the balances.
    func domains(for address: Address) async throws -> [String] {
        guard let endpoint = network.tezosDomainsURL else { return [] }
        do {
            let name = try await TezosDomainsService(endpoint: endpoint, session: session).reverseName(for: address)
            return name.map { [$0] } ?? []
        } catch {
            NSLog("Tezos Domains lookup failed for % %@", address.value, error.localizedDescription)
            return []
        }
    }

    /// NFTs from the TzKT indexer.
    func nfts(for address: Address) async throws -> [NFT] {
        guard let tzkt = network.tzktURL else { return [] }
        return try await TzKTService(baseURL: tzkt, session: session).nfts(for: address)
    }
}

/// A non-2xx answer from the node's RPC, with the body kept for classification.
struct RPCError: LocalizedError {
    let status: Int
    let field: String
    let address: Address
    let body: String

    var errorDescription: String? {
        "RPC error \(status) for \(address.shortened()) \(field): \(body.prefix(200))"
    }
}
