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
