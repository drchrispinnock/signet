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

    /// The most names of each kind the Domains tab asks for.
    static let pageSize = 200
    /// Up to 400 names with their owner, address and expiry.
    static let listBytes = 512 << 10

    /// Every name `address` owns or that points at it, its reverse record first, then by name.
    func domains(of address: Address) async throws -> [TezosDomain] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let fields = "items { name address owner expiresAtUtc }"
        let query = """
        query($a: Address!, $s: String!) {
          owned: domains(where: { owner: { equalTo: $a } }, first: \(Self.pageSize)) { \(fields) }
          pointing: domains(where: { address: { equalTo: $a } }, first: \(Self.pageSize)) { \(fields) }
          reverseRecord(address: $s) { domain { name } }
        }
        """
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["a": address.value, "s": address.value]])
        let reply = try await BoundedHTTP.data(for: request, session: session, limit: Self.listBytes, json: .page)
        guard reply.isSuccess else { throw DomainsError.badResponse("HTTP \(reply.status)") }
        return try Self.parseDomains(reply.data)
    }

    /// The Domains tab's list from the API's reply: owned and pointing names merged.
    static func parseDomains(_ data: Data) throws -> [TezosDomain] {
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw DomainsError.badResponse(errors.map(\.message).joined(separator: "; "))
        }
        let reverse = decoded.data?.reverseRecord?.domain?.name
        let iso = ISO8601DateFormatter()
        var byName: [String: TezosDomain] = [:]
        for item in (decoded.data?.owned?.items ?? []) + (decoded.data?.pointing?.items ?? []) {
            guard let name = item.name, !name.isEmpty, byName[name] == nil else { continue }
            byName[name] = TezosDomain(name: name, address: item.address.map(Address.init), owner: item.owner.map(Address.init),
                                       expires: item.expiresAtUtc.flatMap { iso.date(from: $0) }, isReverseRecord: name == reverse)
        }
        return byName.values.sorted { ($0.isReverseRecord ? 0 : 1, $0.name) < ($1.isReverseRecord ? 0 : 1, $1.name) }
    }

    private struct ListResponse: Decodable {
        struct Item: Decodable {
            let name: String?
            let address: String?
            let owner: String?
            let expiresAtUtc: String?
        }
        struct Page: Decodable { let items: [Item]? }
        struct Payload: Decodable {
            let owned: Page?
            let pointing: Page?
            let reverseRecord: Response.Payload.ReverseRecord?
        }
        let data: Payload?
        let errors: [Response.GraphQLError]?
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
