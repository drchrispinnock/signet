import CryptoKit
import Foundation

/// Client for the teztnets faucets (github.com/tacoinfra/tezos-faucet), the same HTTP API the
/// `get-tez` command line uses: request a proof-of-work challenge, solve it, verify, repeat until
/// the faucet returns the transaction hash. No captcha is needed on this path.
///
/// The faucet is an untrusted service (S21): every challenge is checked against fixed bounds
/// before any work is done, the solver checks for cancellation as it goes and gives up at a
/// deadline, and the whole exchange is capped in rounds and elapsed time.
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

    enum FaucetError: LocalizedError, Equatable {
        case server(String)
        case unexpectedReply
        /// The faucet asked for something outside the bounds Signet will do.
        case unreasonableChallenge(String)
        case tooManyRounds
        case timedOut
        case cancelled
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .server(let message): "Faucet: \(message)"
            case .unexpectedReply: "Faucet returned an unexpected reply."
            case .unreasonableChallenge(let why): "Faucet sent a challenge Signet will not attempt (\(why))."
            case .tooManyRounds: "Faucet kept asking for more challenges than it announced; gave up."
            case .timedOut: "Faucet challenges took too long; gave up."
            case .cancelled: "Faucet request cancelled."
            case .invalidAmount: "Faucet amount is not a valid number of tez."
            }
        }
    }

    /// Bounds on what a faucet may ask for. Difficulty is in leading hex zeros: 8 is already
    /// 2^32 hashes on average, far beyond what any public faucet sets.
    enum Limits {
        static let difficulty = 0...8
        static let challengesNeeded = 1...1000
        /// The teztnets faucet sends 4096-character challenges; allow double that, no more.
        static let challengeLength = 8192
        /// Extra `verify` rounds tolerated beyond `challengesNeeded` before giving up.
        static let roundSlack = 5
        /// Wall-clock budget for one `requestTez`, solving included.
        static let totalDuration: TimeInterval = 10 * 60
        /// Wall-clock budget for one challenge.
        static let solveDuration: TimeInterval = 2 * 60
        /// How often the solver looks at the clock and at cancellation.
        static let checkEvery = 4096
        static let maxTez: Double = 1_000_000
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
        let info: Info
        switch kind {
        case .teztnets:
            info = try JSONDecoder().decode(Info.self, from: data)
        case .pqpark:
            // {"address": "tz1…", "balance": 96587895.65, "defaultAmount": 100}; no stated limits.
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let defaultAmount = (object?["defaultAmount"] as? NSNumber)?.doubleValue ?? 100
            info = Info(faucetAddress: object?["address"] as? String ?? "", challengesEnabled: false,
                        minTez: 1, maxTez: max(defaultAmount * 10, 1000))
        }
        return try Self.checked(info)
    }

    /// Limits must be finite, positive and ordered, or the faucet is not worth talking to.
    static func checked(_ info: Info) throws -> Info {
        guard isReasonableAmount(info.minTez), isReasonableAmount(info.maxTez), info.minTez <= info.maxTez else {
            throw FaucetError.unreasonableChallenge("limits \(info.minTez)…\(info.maxTez) tez")
        }
        return info
    }

    static func isReasonableAmount(_ amount: Double) -> Bool {
        amount.isFinite && amount > 0 && amount <= Limits.maxTez
    }

    /// Asks the faucet to send `amount` tez to `address`. Returns the operation hash.
    func requestTez(to address: Address, amount: Double, progress: Progress? = nil) async throws -> String {
        guard Self.isReasonableAmount(amount) else { throw FaucetError.invalidAmount }
        let deadline = Date().addingTimeInterval(Limits.totalDuration)
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
        let total = current.challengesNeeded
        var rounds = 0
        while true {
            try Task.checkCancellation()
            guard Date() < deadline else { throw FaucetError.timedOut }
            rounds += 1
            guard rounds <= total + Limits.roundSlack else { throw FaucetError.tooManyRounds }
            progress?(min(current.challengeCounter - 1, total), total)
            let (nonce, solution) = try Self.solve(current, deadline: min(deadline, Date().addingTimeInterval(Limits.solveDuration)))
            payload["nonce"] = nonce
            payload["solution"] = solution
            let reply = try await request("verify", body: payload)
            if let hash = try? Self.txHash(from: reply) {
                progress?(total, total)
                return hash
            }
            let next = try Self.challenge(from: reply, after: current)
            current = Challenge(challenge: next.challenge, difficulty: next.difficulty,
                                challengeCounter: next.challengeCounter, challengesNeeded: total)
        }
    }

    /// Finds `nonce` such that hex(SHA-256("\(challenge):\(nonce)")) starts with `difficulty` zeros.
    /// Checks the clock and cancellation every `Limits.checkEvery` hashes and throws past `deadline`.
    static func solve(_ challenge: Challenge, deadline: Date = .distantFuture) throws -> (nonce: Int, solution: String) {
        try validate(challenge)
        let prefix = String(repeating: "0", count: challenge.difficulty)
        var nonce = 0
        while true {
            if nonce % Limits.checkEvery == 0 {
                if Task.isCancelled { throw FaucetError.cancelled }
                if Date() >= deadline { throw FaucetError.timedOut }
            }
            let digest = SHA256.hash(data: Data("\(challenge.challenge):\(nonce)".utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if hex.hasPrefix(prefix) { return (nonce, hex) }
            nonce += 1
        }
    }

    /// Refuses anything outside `Limits` before any work is done.
    static func validate(_ challenge: Challenge) throws {
        guard Limits.difficulty.contains(challenge.difficulty) else { throw FaucetError.unreasonableChallenge("difficulty \(challenge.difficulty)") }
        guard challenge.challengeCounter >= 1 else { throw FaucetError.unreasonableChallenge("counter \(challenge.challengeCounter)") }
        guard Limits.challengesNeeded.contains(challenge.challengesNeeded) else { throw FaucetError.unreasonableChallenge("\(challenge.challengesNeeded) challenges") }
        guard challenge.challengeCounter <= challenge.challengesNeeded + Limits.roundSlack else { throw FaucetError.unreasonableChallenge("counter \(challenge.challengeCounter) of \(challenge.challengesNeeded)") }
        guard !challenge.challenge.isEmpty, challenge.challenge.utf8.count <= Limits.challengeLength else { throw FaucetError.unreasonableChallenge("challenge length \(challenge.challenge.utf8.count)") }
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
        let reply: BoundedHTTP.Reply
        do { reply = try await BoundedHTTP.data(for: request, session: session, limit: 64 << 10, json: .record) }
        catch BoundedHTTP.Failure.notHTTP { throw FaucetError.unexpectedReply }
        guard reply.isSuccess else {
            let object = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any]
            let message = (object?["message"] ?? object?["error"]) as? String
            throw FaucetError.server(message ?? "HTTP \(reply.status)")
        }
        return reply.data
    }

    /// Parses a challenge reply and checks it against `Limits`; with `previous`, the counter must
    /// have moved forward and the number of challenges must not have grown.
    static func challenge(from data: Data, after previous: Challenge? = nil) throws -> Challenge {
        // challengesNeeded is only present on the first reply; later ones carry the rest.
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challenge = object["challenge"] as? String,
              let difficulty = (object["difficulty"] as? NSNumber).flatMap(Self.exactInt),
              let counter = (object["challengeCounter"] as? NSNumber).flatMap(Self.exactInt)
        else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw FaucetError.server(message ?? "no challenge in reply")
        }
        let needed = (object["challengesNeeded"] as? NSNumber).flatMap(Self.exactInt) ?? previous?.challengesNeeded ?? counter
        let parsed = Challenge(challenge: challenge, difficulty: difficulty, challengeCounter: counter, challengesNeeded: needed)
        try validate(parsed)
        if let previous {
            guard parsed.challengeCounter > previous.challengeCounter else { throw FaucetError.unreasonableChallenge("counter did not advance") }
            guard parsed.challengesNeeded <= previous.challengesNeeded else { throw FaucetError.unreasonableChallenge("more challenges than announced") }
        }
        return parsed
    }

    /// JSON numbers that are whole and in range; booleans and fractions are not counters.
    private static func exactInt(_ number: NSNumber) -> Int? {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    static func txHash(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = object["txHash"] as? String
        else { throw FaucetError.unexpectedReply }
        return hash
    }
}
