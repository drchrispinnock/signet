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
                let formats: [Format]?

                struct Format: Decodable, Sendable {
                    let uri: String?
                    let mimeType: String?
                }

                /// Decimals come back as a string in TZIP-21 metadata.
                var decimalPlaces: Int { Int(decimals ?? "") ?? 0 }
            }
            let contract: Contract
            let tokenId: String
            let standard: String?
            let metadata: Metadata?
        }
        let balance: String
        let token: Token
    }

    /// All tokens the account holds a positive balance of.
    func tokenBalances(for address: Address, limit: Int = 200) async throws -> [TokenBalance] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/tokens/balances"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "account", value: address.value),
            URLQueryItem(name: "balance.gt", value: "0"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort.desc", value: "lastLevel"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "TzKT returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [TokenBalance] {
        try JSONDecoder().decode([TokenBalance].self, from: data)
    }

    /// NFTs are tokens with no decimal places and some image to show.
    func nfts(for address: Address) async throws -> [NFT] {
        Self.nfts(from: try await tokenBalances(for: address))
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

    /// displayUri is a sized-down render meant for galleries, so prefer it; thumbnailUri is often a
    /// marketplace's generic placeholder; artifactUri is the full asset, used only if it is an image.
    static func bestImageURLs(in metadata: TokenBalance.Token.Metadata) -> [URL] {
        for candidate in [metadata.displayUri, metadata.thumbnailUri] {
            if let candidate {
                let urls = IPFS.candidateURLs(for: candidate)
                if !urls.isEmpty { return urls }
            }
        }
        if let artifact = metadata.artifactUri {
            let mime = metadata.formats?.first { $0.uri == artifact }?.mimeType ?? ""
            if mime.hasPrefix("image/") { return IPFS.candidateURLs(for: artifact) }
        }
        return []
    }

    static func bestImageURL(in metadata: TokenBalance.Token.Metadata) -> URL? {
        bestImageURLs(in: metadata).first
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 204 || http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return Self.profile(from: data)
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "TzKT returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        return Self.parseOperations(data, for: address)
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
            let outgoing = senderAddress == address.value
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
            return tx
        }
    }

    typealias Kind = TezosTransaction.Kind
    typealias Direction = TezosTransaction.Direction
}
