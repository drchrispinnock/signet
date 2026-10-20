import Foundation

/// Token balances from the TzKT indexer, and the NFTs picked out of them.
struct TzKTService: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// One row of `/v1/tokens/balances`.
    struct TokenBalance: Decodable, Sendable {
        struct Token: Decodable, Sendable {
            struct Contract: Decodable, Sendable { let address: String }
            struct Metadata: Decodable, Sendable {
                let name: String?
                let symbol: String?
                let decimals: String?
                let thumbnailUri: String?
                let displayUri: String?
                let artifactUri: String?
                /// Fungible tokens often put their logo here instead of thumbnailUri.
                let icon: String?
                let formats: [Format]?

                struct Format: Decodable, Sendable {
                    let uri: String?
                    let mimeType: String?
                }

                /// Decimals come back as a string in TZIP-21 metadata. Only a whole number in
                /// 0...36 counts; anything else is treated as missing, so a token cannot claim
                /// nonsensical scaling (S26).
                var decimalPlaces: Int? {
                    guard let decimals else { return nil }
                    guard let value = Int(decimals.trimmingCharacters(in: .whitespaces)), (0...36).contains(value) else { return nil }
                    return value
                }
            }
            let contract: Contract
            let tokenId: String
            let standard: String?
            let metadata: Metadata?
        }
        let balance: String
        let token: Token
    }

    static let pageSize = 200
    /// Reply caps (S19): a page of 200 rows with metadata stays well inside this; one account record is far smaller.
    static let pageBytes = 4 << 20
    static let recordBytes = 256 << 10
    /// At most this many pages per snapshot; beyond that the portfolio is reported as partial.
    static let maxPages = 5

    /// One page of the tokens the account holds a positive balance of, most recently changed first.
    func tokenBalances(for address: Address, limit: Int = pageSize, offset: Int = 0) async throws -> [TokenBalance] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/tokens/balances"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "account", value: address.value),
            URLQueryItem(name: "balance.gt", value: "0"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sort.desc", value: "lastLevel"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.pageBytes, json: .page)
        guard reply.isSuccess else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "TzKT returned HTTP \(reply.status)"])
        }
        return Array(try Self.decode(reply.data).prefix(limit))
    }

    static func decode(_ data: Data) throws -> [TokenBalance] {
        try JSONDecoder().decode([TokenBalance].self, from: data)
    }

    /// Every page up to `maxPages`, and whether that was all of them (S26).
    func allTokenBalances(for address: Address) async throws -> (rows: [TokenBalance], complete: Bool) {
        var rows: [TokenBalance] = []
        for page in 0..<Self.maxPages {
            let batch = try await tokenBalances(for: address, limit: Self.pageSize, offset: page * Self.pageSize)
            rows += batch
            if batch.count < Self.pageSize { return (rows, true) }
        }
        return (rows, false)
    }

    /// Tokens and NFTs from one snapshot, marked partial when the account holds more than was fetched.
    func portfolio(for address: Address) async throws -> Portfolio {
        let (rows, complete) = try await allTokenBalances(for: address)
        return Portfolio(tokens: Self.fungibleTokens(from: rows), nfts: Self.nfts(from: rows), state: complete ? .complete : .partial(fetched: rows.count))
    }

    /// NFTs are tokens with no decimal places and some image to show.
    func nfts(for address: Address) async throws -> [NFT] {
        Self.nfts(from: try await allTokenBalances(for: address).rows)
    }

    /// Fungible (DeFi) tokens: anything with decimal places, or an FA1.2 token (always fungible).
    /// Tokens with zero decimals and no image, such as Tezos Domains, are neither NFT nor asset.
    func fungibleTokens(for address: Address) async throws -> [AssetBalance] {
        Self.fungibleTokens(from: try await allTokenBalances(for: address).rows)
    }

    static func fungibleTokens(from balances: [TokenBalance]) -> [AssetBalance] {
        balances.compactMap { row in
            let metadata = row.token.metadata
            let isFA12 = row.token.standard?.lowercased() == "fa1.2"
            // A token whose decimals are unreadable is not scaled by a guess: FA1.2 is taken as 0, anything else is skipped.
            guard let decimals = metadata?.decimalPlaces ?? (isFA12 ? 0 : nil) else { return nil }
            guard decimals > 0 || isFA12 else { return nil }
            guard let raw = Decimal(string: row.balance), raw.isFinite, raw >= 0 else { return nil }
            let amount = raw / pow(Decimal(10), decimals)
            let contract = row.token.contract.address
            let symbol = metadata?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let name = metadata?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let icons = [metadata?.thumbnailUri, metadata?.icon, metadata?.displayUri].compactMap { $0 }.flatMap(IPFS.candidateURLs(for:))
            return AssetBalance(
                id: "\(contract):\(row.token.tokenId)",
                kind: .token(contract: contract, tokenId: row.token.tokenId),
                name: name ?? symbol ?? Address(contract).shortened(),
                symbol: symbol ?? name ?? "",
                amount: amount,
                iconURLs: icons,
                standard: row.token.standard
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    static func nfts(from balances: [TokenBalance]) -> [NFT] {
        balances.compactMap { row in
            guard let metadata = row.token.metadata, metadata.decimalPlaces == 0 else { return nil }
            let images = bestImageURLs(in: metadata)
            guard !images.isEmpty else { return nil }
            return NFT(
                id: "\(row.token.contract.address):\(row.token.tokenId)",
                contract: row.token.contract.address,
                tokenId: row.token.tokenId,
                name: metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "#\(row.token.tokenId)",
                balance: Decimal(string: row.balance) ?? 1,
                imageURLs: images
            )
        }
    }

    /// Every URL worth trying for the tile, best first: displayUri is a sized-down render meant
    /// for galleries, so it comes first (one URL per gateway); then thumbnailUri, often a
    /// marketplace's generic placeholder but small, so it is the fallback when the display
    /// render is too large to download (`ImageLoader.maxBytes`) or missing from every gateway;
    /// then artifactUri, the full asset, only if it is an image.
    static func bestImageURLs(in metadata: TokenBalance.Token.Metadata) -> [URL] {
        var uris = [metadata.displayUri, metadata.thumbnailUri].compactMap { $0 }
        if let artifact = metadata.artifactUri {
            let mime = metadata.formats?.first { $0.uri == artifact }?.mimeType ?? ""
            if mime.hasPrefix("image/") { uris.append(artifact) }
        }
        var urls: [URL] = []
        for uri in uris {
            for url in IPFS.candidateURLs(for: uri) where !urls.contains(url) { urls.append(url) }
        }
        return urls
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension TzKTService {
    /// TzProfiles data as TzKT indexes it (`extras.profile`), falling back to TzKT's own alias.
    func accountProfile(for address: Address) async throws -> AccountProfile? {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/accounts/\(address.value)"))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.recordBytes, json: .record)
        if reply.status == 204 || reply.status == 404 { return nil }
        guard reply.isSuccess else { throw URLError(.badServerResponse) }
        return Self.profile(from: reply.data)
    }

    static func profile(from data: Data) -> AccountProfile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let profile = (object["extras"] as? [String: Any])?["profile"] as? [String: Any]
        let name = (profile?["alias"] as? String) ?? (object["alias"] as? String)
        let twitter = profile?["twitter"] as? String
        let description = profile?["description"] as? String
        guard name != nil || twitter != nil || description != nil else { return nil }
        return AccountProfile(name: name?.trimmingCharacters(in: .whitespaces), twitter: twitter, description: description)
    }
}

extension TzKTService {
    /// The sender of an operation's first row, or `nil` when TzKT has no such operation.
    func sender(ofOperation hash: String) async throws -> Address? {
        guard hash.count < 64, hash.allSatisfy(\.isLetter) || hash.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/operations/\(hash)"))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.pageBytes, json: .page)
        guard reply.isSuccess, let rows = try JSONSerialization.jsonObject(with: reply.data) as? [[String: Any]],
              let address = (rows.first?["sender"] as? [String: Any])?["address"] as? String, Address(address).isValidAccount
        else { return nil }
        return Address(address)
    }

    /// The account's most recent transactions and delegations, newest first.
    func recentOperations(for address: Address, limit: Int = 25) async throws -> [TezosTransaction] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/accounts/\(address.value)/operations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "transaction,delegation,origination"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort.desc", value: "id"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.pageBytes, json: .page)
        guard reply.isSuccess else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "TzKT returned HTTP \(reply.status)"])
        }
        return Array(Self.parseOperations(reply.data, for: address).prefix(limit))
    }

    /// Pure parser for `/v1/accounts/{address}/operations`.
    static func parseOperations(_ data: Data, for address: Address) -> [TezosTransaction] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let type = row["type"] as? String, let hash = row["hash"] as? String,
                  let stamp = row["timestamp"] as? String, let timestamp = iso.date(from: stamp)
            else { return nil }
            let sender = (row["sender"] as? [String: Any])
            let senderAddress = sender?["address"] as? String ?? ""
            let kind = Kind(rawValue: type) ?? .other
            let other: [String: Any]?
            switch kind {
            case .transaction: other = row["target"] as? [String: Any]
            case .delegation: other = row["newDelegate"] as? [String: Any]
            case .origination: other = row["originatedContract"] as? [String: Any]
            case .other: other = nil
            }
            // An internal operation a contract emitted because we called it (a multisig paying
            // out) is ours: the indexer lists it under our account with the contract as sender
            // and us as initiator, so it must not read as money coming in from the contract.
            let initiator = (row["initiator"] as? [String: Any])?["address"] as? String
            let initiatedByUs = senderAddress != address.value && initiator == address.value
            let outgoing = senderAddress == address.value || initiatedByUs
            let direction: Direction = outgoing
                ? ((other?["address"] as? String) == address.value ? .selfTransfer : .outgoing)
                : .incoming
            let counterpartyObject = outgoing ? other : sender
            let mutez = (row["amount"] as? NSNumber)?.decimalValue ?? 0
            let feeMutez = (row["bakerFee"] as? NSNumber)?.decimalValue ?? 0
            let entrypoint = (row["parameter"] as? [String: Any])?["entrypoint"] as? String ?? row["entrypoint"] as? String
            let idValue = (row["id"] as? NSNumber).map { "\($0)" } ?? hash
            // On a delegation `amount` is the delegator's balance, not a transfer.
            let isDelegation = kind == .delegation
            var tx = TezosTransaction(
                id: idValue, hash: hash, level: row["level"] as? Int ?? 0, timestamp: timestamp,
                kind: kind, direction: direction,
                counterparty: (counterpartyObject?["address"] as? String).map(Address.init),
                counterpartyAlias: counterpartyObject?["alias"] as? String,
                amount: isDelegation ? 0 : mutez / Mutez.perTez, fee: feeMutez / Mutez.perTez,
                entrypoint: entrypoint,
                isApplied: (row["status"] as? String ?? "applied") == "applied"
            )
            if isDelegation {
                tx.previousDelegate = ((row["prevDelegate"] as? [String: Any])?["address"] as? String).map(Address.init)
                tx.newDelegate = ((row["newDelegate"] as? [String: Any])?["address"] as? String).map(Address.init)
                tx.delegatedBalance = mutez / Mutez.perTez
                tx.delegationTarget = address
            }
            if initiatedByUs { tx.via = Address(senderAddress) }
            return tx
        }
    }

    typealias Kind = TezosTransaction.Kind
    typealias Direction = TezosTransaction.Direction
}


extension TzKTService {
    /// Active bakers, most delegators first.
    func bakers(limit: Int) async throws -> [BakerCandidate] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/delegates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "sort.desc", value: "numDelegators"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "select", value: "address,alias,stakingBalance,numDelegators,stakersCount,limitOfStakingOverBaking"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.pageBytes, json: .page)
        guard reply.isSuccess else { throw URLError(.badServerResponse) }
        return Array(Self.parseBakers(reply.data).prefix(limit))
    }

    static func parseBakers(_ data: Data) -> [BakerCandidate] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let address = row["address"] as? String else { return nil }
            let limit = row["limitOfStakingOverBaking"] as? NSNumber
            return BakerCandidate(
                address: Address(address), alias: row["alias"] as? String,
                stakingBalance: ((row["stakingBalance"] as? NSNumber)?.decimalValue ?? 0) / Mutez.perTez,
                delegators: (row["numDelegators"] as? NSNumber)?.intValue ?? 0,
                stakers: (row["stakersCount"] as? NSNumber)?.intValue ?? 0,
                acceptsStaking: limit.map { $0.intValue > 0 }
            )
        }
    }
}
