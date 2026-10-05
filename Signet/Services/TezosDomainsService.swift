import Foundation

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
        request.timeoutInterval = 15
        let query = "query($address: String!) { reverseRecord(address: $address) { domain { name } } }"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["address": address.value]])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DomainsError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let errors = decoded.errors, !errors.isEmpty {
            throw DomainsError.badResponse(errors.map(\.message).joined(separator: "; "))
        }
        return decoded.data?.reverseRecord?.domain?.name
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
