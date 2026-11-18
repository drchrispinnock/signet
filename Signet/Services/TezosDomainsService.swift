import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reverse lookups against the Tezos Domains GraphQL API. An address maps to at most one
/// reverse record (the name its owner chose to publish), so this returns zero or one name.
struct TezosDomainsService: Sendable {
    enum DomainsError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(let detail): "Tezos Domains returned an unexpected response: \(detail)"
            }
        }
    }

    let endpoint: URL
    let session: URLSession
    /// A reverse or forward lookup answers with one name or address (S19).
    static let replyBytes = 16 << 10

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// The published `.tez` name for `address`, or `nil` when it has none.
    func reverseName(for address: Address) async throws -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let query = "query($address: String!) { reverseRecord(address: $address) { domain { name } } }"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["address": address.value]])

        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.replyBytes)
        guard reply.isSuccess else { throw DomainsError.badResponse("HTTP \(reply.status)") }
        let decoded = try JSONDecoder().decode(Response.self, from: reply.data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw DomainsError.badResponse(errors.map(\.message).joined(separator: "; "))
        }
        return decoded.data?.reverseRecord?.domain?.name
    }

    /// The API answers at most 50 names a request, so the list is read in pages of 50.
    static let pageSize = 50
    /// Pages read before stopping: 500 names of each kind, more than any account has.
    static let maximumPages = 10
    /// One page of up to 100 names with their owner, address and expiry.
    static let listBytes = 256 << 10

    /// Every name `address` owns or that points at it, its reverse record first, then by name.
    func domains(of address: Address) async throws -> [TezosDomain] {
        var items: [ListResponse.Item] = []
        var reverse: String?
        var ownedAfter: String?, pointingAfter: String?
        var ownedDone = false, pointingDone = false
        for _ in 0..<Self.maximumPages where !(ownedDone && pointingDone) {
            let page = try Self.parsePage(try await fetchPage(address, ownedAfter: ownedAfter, pointingAfter: pointingAfter,
                                                              owned: !ownedDone, pointing: !pointingDone))
            items += page.items
            reverse = reverse ?? page.reverse
            ownedDone = ownedDone || page.ownedNext == nil
            pointingDone = pointingDone || page.pointingNext == nil
            ownedAfter = page.ownedNext ?? ownedAfter
            pointingAfter = page.pointingNext ?? pointingAfter
        }
        return Self.merge(items, reverse: reverse)
    }

    private func fetchPage(_ address: Address, ownedAfter: String?, pointingAfter: String?, owned: Bool, pointing: Bool) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let fields = "items { name address owner expiresAtUtc } pageInfo { hasNextPage endCursor }"
        let order = "order: { field: NAME, direction: ASC }"
        let query = """
        query($a: Address!, $s: String!, $ownedAfter: String, $pointingAfter: String, $owned: Boolean!, $pointing: Boolean!) {
          owned: domains(where: { owner: { equalTo: $a } }, \(order), first: \(Self.pageSize), after: $ownedAfter) @include(if: $owned) { \(fields) }
          pointing: domains(where: { address: { equalTo: $a } }, \(order), first: \(Self.pageSize), after: $pointingAfter) @include(if: $pointing) { \(fields) }
          reverseRecord(address: $s) { domain { name } }
        }
        """
        let variables: [String: Any] = ["a": address.value, "s": address.value, "ownedAfter": ownedAfter ?? NSNull(), "pointingAfter": pointingAfter ?? NSNull(),
                                        "owned": owned, "pointing": pointing]
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.listBytes, json: .page)
        guard reply.isSuccess else { throw DomainsError.badResponse("HTTP \(reply.status)") }
        return reply.data
    }

    /// One page of the API's reply: its names, the cursor to each list's next page (`nil` when
    /// there is none) and the account's reverse record.
    struct Page {
        var items: [ListResponse.Item]
        var ownedNext: String?
        var pointingNext: String?
        var reverse: String?
    }

    static func parsePage(_ data: Data) throws -> Page {
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw DomainsError.badResponse(errors.map(\.message).joined(separator: "; "))
        }
        func next(_ list: ListResponse.Page?) -> String? { list?.pageInfo?.hasNextPage == true ? list?.pageInfo?.endCursor : nil }
        return Page(items: (decoded.data?.owned?.items ?? []) + (decoded.data?.pointing?.items ?? []),
                    ownedNext: next(decoded.data?.owned), pointingNext: next(decoded.data?.pointing),
                    reverse: decoded.data?.reverseRecord?.domain?.name)
    }

    /// The Domains tab's list from one reply (tests and single pages).
    static func parseDomains(_ data: Data) throws -> [TezosDomain] {
        let page = try parsePage(data)
        return merge(page.items, reverse: page.reverse)
    }

    /// Owned and pointing names as one list, each name once, the reverse record first.
    static func merge(_ items: [ListResponse.Item], reverse: String?) -> [TezosDomain] {
        let iso = ISO8601DateFormatter()
        var byName: [String: TezosDomain] = [:]
        for item in items {
            guard let name = item.name, !name.isEmpty, byName[name] == nil else { continue }
            byName[name] = TezosDomain(name: name, address: item.address.map(Address.init), owner: item.owner.map(Address.init),
                                       expires: item.expiresAtUtc.flatMap { iso.date(from: $0) }, isReverseRecord: name == reverse)
        }
        return byName.values.sorted { ($0.isReverseRecord ? 0 : 1, $0.name) < ($1.isReverseRecord ? 0 : 1, $1.name) }
    }

    struct ListResponse: Decodable {
        struct Item: Decodable {
            let name: String?
            let address: String?
            let owner: String?
            let expiresAtUtc: String?
        }
        struct PageInfo: Decodable {
            let hasNextPage: Bool?
            let endCursor: String?
        }
        struct Page: Decodable {
            let items: [Item]?
            let pageInfo: PageInfo?
        }
        struct Payload: Decodable {
            let owned: Page?
            let pointing: Page?
            let reverseRecord: ReverseRecord?
        }
        struct ReverseRecord: Decodable {
            struct Domain: Decodable { let name: String? }
            let domain: Domain?
        }
        struct GraphQLError: Decodable { let message: String }
        let data: Payload?
        let errors: [GraphQLError]?
    }

    /// The address a `.tez` name points at, or `nil` if the name is unregistered or has no address.
    func resolve(name: String) async throws -> Address? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        let query = "query($name: String!) { domain(name: $name) { address } }"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["name": name.lowercased()]])
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.replyBytes)
        guard reply.isSuccess else { throw DomainsError.badResponse("HTTP \(reply.status)") }
        let decoded = try JSONDecoder().decode(ForwardResponse.self, from: reply.data)
        return decoded.data?.domain?.address.map(Address.init)
    }

    private struct ForwardResponse: Decodable {
        struct Payload: Decodable {
            struct Domain: Decodable { let address: String? }
            let domain: Domain?
        }
        let data: Payload?
    }

    private struct Response: Decodable {
        struct Payload: Decodable {
            struct ReverseRecord: Decodable {
                struct Domain: Decodable { let name: String? }
                let domain: Domain?
            }
            let reverseRecord: ReverseRecord?
        }
        struct GraphQLError: Decodable { let message: String }
        let data: Payload?
        let errors: [GraphQLError]?
    }
}
