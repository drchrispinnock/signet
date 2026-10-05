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
