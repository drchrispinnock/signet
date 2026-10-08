import Foundation

/// Live chain access through the Taquito bridge. Anything the bridge does not provide yet is
/// delegated to `fallback` so the UI stays complete while features land one at a time.
struct TaquitoChainService: ChainService {
    let network: Network
    let bridge: TaquitoBridge
    let fallback: any ChainService
    let session: URLSession

    init(network: Network = .mainnet, bridge: TaquitoBridge = .shared, fallback: any ChainService = MockChainService(), session: URLSession = .shared) {
        self.network = network
        self.bridge = bridge
        self.fallback = fallback
        self.session = session
    }

    func tezBalance(for address: Address) async throws -> TezBalance {
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
        let url = network.rpcURL.appendingPathComponent("chains/main/blocks/head/context/contracts/\(address.value)/\(field)")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RPCError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, field: field, address: address,
                           body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let text = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        try await fallback.etherlinkBalance(for: address)
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
        guard let publicKey = wallet.publicKey else {
            throw TaquitoBridge.BridgeError.javaScript("Account “\(wallet.alias)” has no public key, so its fees cannot be estimated.")
        }
        let result = try await bridge.call("estimateTransfer", [network.rpcURL.absoluteString, wallet.address.value, publicKey, destination.value, Mutez.fromTez(amount)])
        guard let fee = Mutez.toTez(result["feeMutez"]?.stringValue),
              let burn = Mutez.toTez(result["burnMutez"]?.stringValue),
              let total = Mutez.toTez(result["totalCostMutez"]?.stringValue)
        else { throw TaquitoBridge.BridgeError.javaScript("unexpected estimate payload: \(String(describing: result))") }
        return TransferEstimate(fee: fee, burn: burn, total: amount + fee + burn,
                                gasLimit: Int(result["gasLimit"]?.doubleValue ?? 0), storageLimit: Int(result["storageLimit"]?.doubleValue ?? 0))
    }

    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal) async throws -> String {
        let result = try await signing { try await bridge.call("sendTransfer", [network.rpcURL.absoluteString, signer.bridgeSpec, destination.value, Mutez.fromTez(amount)]) }
        guard let hash = result["hash"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected send payload: \(String(describing: result))")
        }
        return hash
    }

    /// Runs a bridge call that signs, turning the bridge's error text for wrong passwords and
    /// Ledger trouble into `ChainError`s the UI can word properly.
    private func signing(_ body: () async throws -> JSONValue) async throws -> JSONValue {
        do {
            return try await body()
        } catch let error as TaquitoBridge.BridgeError {
            if case .javaScript(let message) = error, let known = ChainError.fromBridgeMessage(message) { throw known }
            throw error
        }
    }

    func waitForConfirmation(of operationHash: String) async throws -> Int {
        do {
            let result = try await bridge.call("waitForConfirmation", [operationHash, 1])
            return Int(result.doubleValue ?? 0)
        } catch let error as TaquitoBridge.BridgeError {
            // Raw operations are not tracked by Taquito; watch the chain for them instead.
            guard case .javaScript(let message) = error, message.contains("unknown operation") else { throw error }
            let result = try await bridge.call("waitForRawOperation", [network.rpcURL.absoluteString, operationHash, 15])
            return Int(result.doubleValue ?? 0)
        }
    }

    func delegateInfo(for address: Address) async throws -> DelegateInfo {
        let r = try await bridge.call("getDelegateInfo", [network.rpcURL.absoluteString, address.value])
        var baker: DelegateInfo.Baker?
        if let b = r["baker"], b != .null, b.objectValue != nil {
            baker = DelegateInfo.Baker(
                deactivated: b["deactivated"]?.boolValue ?? false,
                gracePeriod: b["gracePeriod"]?.doubleValue.map(Int.init),
                consensusKey: b["consensusKey"]?.stringValue.map(Address.init),
                pendingConsensusKeys: b["pendingConsensusKeys"]?.arrayValue?.compactMap { $0["key"]?.stringValue.map(Address.init) } ?? [],
                companionKey: b["companionKey"]?.stringValue.map(Address.init),
                pendingCompanionKeys: b["pendingCompanionKeys"]?.arrayValue?.compactMap { $0["key"]?.stringValue.map(Address.init) } ?? []
            )
            if let p = b["stakingParameters"], let limit = p["limitMillionth"]?.doubleValue, let edge = p["edgeBillionth"]?.doubleValue {
                baker?.stakingParameters = StakingParameters(limitMillionth: Int(limit), edgeBillionth: Int(edge))
            }
            baker?.pendingStakingParameters = b["pendingStakingParameters"]?.arrayValue?.compactMap { p in
                guard let limit = p["limitMillionth"]?.doubleValue, let edge = p["edgeBillionth"]?.doubleValue else { return nil }
                return StakingParameters(limitMillionth: Int(limit), edgeBillionth: Int(edge), cycle: p["cycle"]?.doubleValue.map(Int.init))
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
        guard let publicKey = wallet.publicKey else {
            throw TaquitoBridge.BridgeError.javaScript("Account “\(wallet.alias)” has no public key, so its fees cannot be estimated.")
        }
        if let contents = rawContents(for: operation) {
            let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
            let r = try await bridge.call("estimateRawOperation", [network.rpcURL.absoluteString, wallet.address.value, publicKey, json])
            let fee = Mutez.toTez(r["feeMutez"]?.stringValue) ?? 0
            return TransferEstimate(fee: fee, burn: 0, total: fee, gasLimit: Int(r["gasLimit"]?.doubleValue ?? 0), storageLimit: 0)
        }
        let arg = String(data: try JSONSerialization.data(withJSONObject: operation.bridgeArgument), encoding: .utf8)!
        let r = try await bridge.call("estimateStakingOperation", [network.rpcURL.absoluteString, wallet.address.value, publicKey, operation.bridgeKind, arg])
        guard let fee = Mutez.toTez(r["feeMutez"]?.stringValue), let burn = Mutez.toTez(r["burnMutez"]?.stringValue) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected estimate payload: \(String(describing: r))")
        }
        let amount: Decimal = { if case .stake(let a) = operation { return a } else { return 0 } }()
        return TransferEstimate(fee: fee, burn: burn, total: amount + fee + burn, gasLimit: Int(r["gasLimit"]?.doubleValue ?? 0), storageLimit: Int(r["storageLimit"]?.doubleValue ?? 0))
    }

    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey) async throws -> String {
        let r = try await signing {
            if let contents = rawContents(for: operation) {
                let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
                return try await bridge.call("sendRawOperation", [network.rpcURL.absoluteString, signer.bridgeSpec, json])
            } else {
                let arg = String(data: try JSONSerialization.data(withJSONObject: operation.bridgeArgument), encoding: .utf8)!
                return try await bridge.call("sendStakingOperation", [network.rpcURL.absoluteString, signer.bridgeSpec, operation.bridgeKind, arg])
            }
        }
        guard let hash = r["hash"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("unexpected payload: \(String(describing: r))") }
        return hash
    }

    func proofOfPossession(signer: SigningKey) async throws -> String {
        let r = try await signing { try await bridge.call("provePossession", [signer.bridgeSpec]) }
        guard let proof = r["proof"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no proof returned") }
        return proof
    }

    /// Fungible tokens from TzKT. Indexer trouble is logged and shown as an empty list.
    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        guard let tzkt = network.tzktURL else { return [] }
        do {
            return try await TzKTService(baseURL: tzkt, session: session).fungibleTokens(for: address)
        } catch {
            NSLog("TzKT token lookup failed for %@: %@", address.value, error.localizedDescription)
            return []
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

    /// NFTs from the TzKT indexer. Indexer trouble is logged and shown as an empty grid rather
    /// than failing the whole refresh.
    func nfts(for address: Address) async throws -> [NFT] {
        guard let tzkt = network.tzktURL else { return [] }
        do {
            return try await TzKTService(baseURL: tzkt, session: session).nfts(for: address)
        } catch {
            NSLog("TzKT NFT lookup failed for % %@", address.value, error.localizedDescription)
            return []
        }
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
