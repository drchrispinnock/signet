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
            throw TaquitoBridge.BridgeError.javaScript("Wallet “\(wallet.alias)” has no public key, so its fees cannot be estimated.")
        }
        let result = try await bridge.call("estimateTransfer", [network.rpcURL.absoluteString, wallet.address.value, publicKey, destination.value, Mutez.fromTez(amount)])
        guard let fee = Mutez.toTez(result["feeMutez"]?.stringValue),
              let burn = Mutez.toTez(result["burnMutez"]?.stringValue),
              let total = Mutez.toTez(result["totalCostMutez"]?.stringValue)
        else { throw TaquitoBridge.BridgeError.javaScript("unexpected estimate payload: \(String(describing: result))") }
        return TransferEstimate(fee: fee, burn: burn, total: amount + fee + burn,
                                gasLimit: Int(result["gasLimit"]?.doubleValue ?? 0), storageLimit: Int(result["storageLimit"]?.doubleValue ?? 0))
    }

    func sendTransfer(from wallet: Wallet, secretKey: String, passphrase: String?, to destination: Address, amount: Decimal) async throws -> String {
        let result: JSONValue
        do {
            result = try await bridge.call("sendTransfer", [network.rpcURL.absoluteString, secretKey, passphrase ?? "", destination.value, Mutez.fromTez(amount)])
        } catch let error as TaquitoBridge.BridgeError {
            if case .javaScript(let message) = error, message.contains("decrypt") || message.contains("passphrase") {
                throw ChainError.wrongPassphrase
            }
            throw error
        }
        guard let hash = result["hash"]?.stringValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected send payload: \(String(describing: result))")
        }
        return hash
    }

    func waitForConfirmation(of operationHash: String) async throws -> Int {
        let result = try await bridge.call("waitForConfirmation", [operationHash, 1])
        return Int(result.doubleValue ?? 0)
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        try await fallback.tokenBalances(for: address)
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
