import Foundation

/// The one way native code reads an HTTP reply from a node, an indexer, a faucet or a name
/// service (S19). The body is taken as a stream and dropped the moment it passes the caller's
/// byte cap, declared length or not, so a misbehaving or hostile server cannot make the app
/// accumulate an arbitrarily large reply before rejecting it; a JSON reply is also checked
/// against structure and string budgets (`JSONBudget`) before anything parses it. The bridge's
/// own fetches have the same protections in `TaquitoBridge`; this is for the `URLSession`
/// readers outside it.
enum BoundedHTTP {
    struct Reply: Sendable {
        let data: Data
        let status: Int
        var isSuccess: Bool { (200..<300).contains(status) }
    }

    /// Structure budgets for a JSON body, checked before parsing.
    struct JSONLimits: Sendable {
        var depth: Int
        var nodes: Int
        var string: Int
        /// A chain id, a balance, a block header, a name lookup: a handful of values.
        static let small = JSONLimits(depth: 16, nodes: 2_000, string: 16 << 10)
        /// One account record, a faucet reply: a few hundred fields at most.
        static let record = JSONLimits(depth: 32, nodes: 20_000, string: 64 << 10)
        /// A page of operations, tokens or bakers; contract parameters nest deeply and token
        /// metadata can carry long URIs.
        static let page = JSONLimits(depth: 128, nodes: 250_000, string: 1 << 20)
    }

    enum Failure: LocalizedError, Equatable {
        case notHTTP
        case tooLarge(limit: Int)
        case overBudget

        var errorDescription: String? {
            switch self {
            case .notHTTP: "The server did not answer over HTTP."
            case .tooLarge(let limit): "The server's reply was larger than the \(limit / 1024) KB allowed."
            case .overBudget: "The server's reply was more complex than allowed."
            }
        }
    }

    /// Reads `request`, keeping at most `limit` body bytes; with `json` the body must also fit
    /// those limits. Status codes are returned, not judged: callers decide what a 404 means.
    static func data(for request: URLRequest, session: URLSession, limit: Int, json: JSONLimits? = .small) async throws -> Reply {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        if http.expectedContentLength > Int64(limit) { throw Failure.tooLarge(limit: limit) }
        var data = Data()
        data.reserveCapacity(min(limit, Int(max(http.expectedContentLength, 0))))
        for try await byte in bytes {
            data.append(byte)
            // Throwing out of the loop cancels the task, so the rest of the body is never read.
            if data.count > limit { throw Failure.tooLarge(limit: limit) }
        }
        if let json, !JSONBudget.accepts(data, depthLimit: json.depth, nodeLimit: json.nodes, stringLimit: json.string) {
            throw Failure.overBudget
        }
        return Reply(data: data, status: http.statusCode)
    }
}
