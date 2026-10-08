import CryptoKit
import Foundation

/// Client for the teztnets faucets (github.com/tacoinfra/tezos-faucet), the same HTTP API the
/// `get-tez` command line uses: request a proof-of-work challenge, solve it, verify, repeat until
/// the faucet returns the transaction hash. No captcha is needed on this path.
struct FaucetService: Sendable {
    struct Info: Decodable, Sendable {
        let faucetAddress: String
        let challengesEnabled: Bool
        let minTez: Double
        let maxTez: Double
    }

    struct Challenge: Decodable, Sendable, Equatable {
        let challenge: String
        let difficulty: Int
        let challengeCounter: Int
        let challengesNeeded: Int
    }

    enum FaucetError: LocalizedError {
        case server(String)
        case unexpectedReply

        var errorDescription: String? {
            switch self {
            case .server(let message): "Faucet: \(message)"
            case .unexpectedReply: "Faucet returned an unexpected reply."
            }
        }
    }

    /// Progress while solving: challenges done so far out of the total.
    typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    let baseURL: URL
    let kind: Network.FaucetKind
    let session: URLSession

    init(baseURL: URL, kind: Network.FaucetKind = .teztnets, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.kind = kind
        self.session = session
    }

    /// Convenience for a network's own faucet.
    init?(network: Network, session: URLSession = .shared) {
        guard let url = network.faucetURL else { return nil }
        self.init(baseURL: url, kind: network.faucetKind, session: session)
    }

    func info() async throws -> Info {
        let data = try await request("info", body: nil)
        switch kind {
        case .teztnets:
            return try JSONDecoder().decode(Info.self, from: data)
        case .pqpark:
            // {"address": "tz1…", "balance": 96587895.65, "defaultAmount": 100}; no stated limits.
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let defaultAmount = (object?["defaultAmount"] as? NSNumber)?.doubleValue ?? 100
            return Info(faucetAddress: object?["address"] as? String ?? "", challengesEnabled: false,
                        minTez: 1, maxTez: max(defaultAmount * 10, 1000))
        }
    }

    /// Asks the faucet to send `amount` tez to `address`. Returns the operation hash.
    func requestTez(to address: Address, amount: Double, progress: Progress? = nil) async throws -> String {
        if kind == .pqpark {
            let reply = try await request("send", body: ["to": address.value, "amount": amount])
            guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any], let hash = object["hash"] as? String else {
                throw FaucetError.unexpectedReply
            }
            return hash
        }
        let info = try await info()
        let amount = min(max(amount, info.minTez), info.maxTez)
        var payload: [String: Any] = ["address": address.value, "amount": amount]

        guard info.challengesEnabled else {
            payload["nonce"] = 0
            payload["solution"] = ""
            return try Self.txHash(from: try await request("verify", body: payload))
        }

        var current = try Self.challenge(from: try await request("challenge", body: payload))
        while true {
            progress?(current.challengeCounter - 1, current.challengesNeeded)
            let (nonce, solution) = Self.solve(current)
            payload["nonce"] = nonce
            payload["solution"] = solution
            let reply = try await request("verify", body: payload)
            if let hash = try? Self.txHash(from: reply) {
                progress?(current.challengesNeeded, current.challengesNeeded)
                return hash
            }
            let next = try Self.challenge(from: reply)
            current = Challenge(challenge: next.challenge, difficulty: next.difficulty,
                                challengeCounter: next.challengeCounter, challengesNeeded: current.challengesNeeded)
        }
    }

    /// Finds `nonce` such that hex(SHA-256("\(challenge):\(nonce)")) starts with `difficulty` zeros.
    static func solve(_ challenge: Challenge) -> (nonce: Int, solution: String) {
        let prefix = String(repeating: "0", count: challenge.difficulty)
        var nonce = 0
        while true {
            let digest = SHA256.hash(data: Data("\(challenge.challenge):\(nonce)".utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if hex.hasPrefix(prefix) { return (nonce, hex) }
            nonce += 1
        }
    }

    // MARK: - Wire

    private func request(_ path: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FaucetError.unexpectedReply }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (object?["message"] ?? object?["error"]) as? String
            throw FaucetError.server(message ?? "HTTP \(http.statusCode)")
        }
        return data
    }

    static func challenge(from data: Data) throws -> Challenge {
        // challengesNeeded is only present on the first reply; later ones carry the rest.
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challenge = object["challenge"] as? String,
              let difficulty = object["difficulty"] as? Int,
              let counter = object["challengeCounter"] as? Int
        else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw FaucetError.server(message ?? "no challenge in reply")
        }
        return Challenge(challenge: challenge, difficulty: difficulty, challengeCounter: counter,
                         challengesNeeded: object["challengesNeeded"] as? Int ?? counter)
    }

    static func txHash(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = object["txHash"] as? String
        else { throw FaucetError.unexpectedReply }
        return hash
    }
}
