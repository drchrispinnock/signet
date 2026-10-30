import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Token metadata Signet reads for itself when the indexer has none. TzKT normally resolves a
/// token's TZIP-21 document within minutes of its mint, but an indexer without a metadata
/// resolver (Etherlink's TzKT, October 2026) or a very fresh mint leaves `metadata` null, and a
/// token without metadata is neither an asset nor an NFT to Signet. So for such rows the
/// contract's `token_metadata` big map is read through the same indexer (TZIP-12: a
/// `token_info` map of bytes; its `""` entry is the URI of the document, the others override
/// fields of it), the document is fetched from IPFS gateways or a public HTTPS address with
/// the same bounds as artwork (S13, S19), and the result is classified as if TzKT had sent it.
/// Resolved metadata is cached for the process; a miss is retried after a while.
struct TokenMetadataResolver: Sendable {
    typealias Metadata = TzKTService.TokenBalance.Token.Metadata

    /// Rows resolved per portfolio load beyond what the cache answers; the rest wait for the next refresh.
    static let maxPerLoad = 12
    /// A TZIP-21 document is a few hundred bytes; a page of attributes still fits comfortably.
    static let maxDocumentBytes = 256 << 10
    static let missLifetime: TimeInterval = 10 * 60

    /// Keeps one indexer's tokens apart from another's in the cache.
    let scope: String
    /// The hex-decoded `token_info` of the contract's `token_metadata` entry, or `nil` without one.
    let tokenInfo: @Sendable (_ contract: String, _ tokenId: String) async throws -> [String: String]?
    /// The document at a URL from `documentURLs`, or `nil` when it cannot be read.
    let document: @Sendable (URL) async throws -> Data?

    static func live(tzkt: TzKTService) -> TokenMetadataResolver {
        TokenMetadataResolver(scope: tzkt.baseURL.absoluteString,
                              tokenInfo: { try await tzkt.tokenInfo(contract: $0, tokenId: $1) },
                              document: fetchDocument)
    }

    /// `rows` with metadata filled in where the indexer had none and it could be read.
    func fill(_ rows: [TzKTService.TokenBalance]) async -> [TzKTService.TokenBalance] {
        var rows = rows
        var budget = Self.maxPerLoad
        for index in rows.indices where rows[index].token.metadata == nil {
            guard !Task.isCancelled else { break }
            let token = rows[index].token
            let key = "\(scope)|\(token.contract.address):\(token.tokenId)"
            if let cached = await TokenMetadataCache.shared.lookup(key) {
                rows[index].token.metadata = cached.metadata
                continue
            }
            guard budget > 0 else { continue }
            budget -= 1
            let metadata = await resolve(contract: token.contract.address, tokenId: token.tokenId)
            await TokenMetadataCache.shared.store(metadata, for: key)
            rows[index].token.metadata = metadata
        }
        return rows
    }

    /// Reads the big map entry and its document; `nil` when either the entry is missing or
    /// nothing in it describes the token.
    func resolve(contract: String, tokenId: String) async -> Metadata? {
        guard Self.isContract(contract), Self.isTokenID(tokenId) else { return nil }
        guard let info = try? await tokenInfo(contract, tokenId) else { return nil }
        var document: Data?
        if let uri = info[""] {
            for url in Self.documentURLs(for: uri) {
                guard !Task.isCancelled else { return nil }
                if let data = try? await self.document(url) { document = data; break }
            }
        }
        return Self.metadata(from: info, document: document)
    }

    /// Where a `token_info` URI can be fetched from: every gateway for `ipfs://`, the address
    /// itself for public HTTPS, nothing for anything else (`tezos-storage:` is not followed).
    static func documentURLs(for uri: String) -> [URL] {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("ipfs://") { return IPFS.candidateURLs(for: trimmed) }
        guard let url = URL(string: trimmed), EndpointPolicy.isPublicHTTPS(url) else { return [] }
        return [url]
    }

    /// The document's fields, overridden by any the big map states directly (TZIP-12 lets a
    /// contract put `name`, `symbol`, `decimals` and the URIs straight into `token_info`).
    /// `nil` when nothing usable results.
    static func metadata(from info: [String: String], document: Data?) -> Metadata? {
        var metadata = document.flatMap(Self.decodeDocument) ?? Metadata()
        func direct(_ key: String) -> String? {
            info[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        if let value = direct("name") { metadata.name = value }
        if let value = direct("symbol") { metadata.symbol = value }
        if let value = direct("decimals") { metadata.decimals = value }
        if let value = direct("thumbnailUri") { metadata.thumbnailUri = value }
        if let value = direct("displayUri") { metadata.displayUri = value }
        if let value = direct("artifactUri") { metadata.artifactUri = value }
        if let value = direct("icon") { metadata.icon = value }
        return metadata.isEmpty ? nil : metadata
    }

    /// A TZIP-21 document as the indexer would have reported it; `nil` unless it is a JSON object
    /// within the usual budget.
    static func decodeDocument(_ data: Data) -> Metadata? {
        guard data.count <= maxDocumentBytes,
              JSONBudget.accepts(data, depthLimit: 32, nodeLimit: 4_000, stringLimit: 64 << 10),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data) else { return nil }
        return metadata
    }

    /// Fetches a document through the pinned public client, as artwork is fetched (S13).
    static func fetchDocument(_ url: URL) async throws -> Data? {
        guard EndpointPolicy.isPublicHTTPS(url) else { return nil }
        let reply = try await PublicHTTPClient.data(for: URLRequest(url: url), limit: maxDocumentBytes, followRedirects: true)
        guard (200..<300).contains(reply.status), reply.data.count <= maxDocumentBytes else { return nil }
        return reply.data
    }

    static func isContract(_ address: String) -> Bool {
        address.hasPrefix("KT1") && address.count == 36 && address.allSatisfy { $0.isLetter || $0.isNumber }
    }

    static func isTokenID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.allSatisfy(\.isNumber)
    }
}

/// Metadata resolved this process, hits and misses, so a refresh asks for each token once.
actor TokenMetadataCache {
    static let shared = TokenMetadataCache()

    struct Entry: Sendable {
        let metadata: TokenMetadataResolver.Metadata?
        let date: Date
    }

    private var entries: [String: Entry] = [:]
    private let limit = 2_000

    func lookup(_ key: String) -> Entry? {
        guard let entry = entries[key] else { return nil }
        if entry.metadata == nil, Date().timeIntervalSince(entry.date) > TokenMetadataResolver.missLifetime {
            entries[key] = nil
            return nil
        }
        return entry
    }

    func store(_ metadata: TokenMetadataResolver.Metadata?, for key: String) {
        if entries.count >= limit { entries.removeAll() }
        entries[key] = Entry(metadata: metadata, date: Date())
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
