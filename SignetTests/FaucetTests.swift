import Foundation
import Testing
@testable import Signet

struct FaucetServiceTests {
    @Test func solvesAProofOfWorkChallenge() throws {
        let challenge = FaucetService.Challenge(challenge: "abc123", difficulty: 3, challengeCounter: 1, challengesNeeded: 1)
        let (nonce, solution) = try FaucetService.solve(challenge)
        #expect(solution.hasPrefix("000"))
        #expect(solution.count == 64)
        // Reproducible: the same nonce gives the same hash.
        #expect(try FaucetService.solve(challenge).nonce == nonce)
    }

    /// S21: the faucet is untrusted. A negative difficulty used to reach `String(repeating:count:)`
    /// and trap; a huge one would run forever. Both are refused before any hashing.
    @Test(arguments: [-1, Int.min, 9, 64, 1_000_000, Int.max])
    func refusesUnreasonableDifficulty(difficulty: Int) {
        let challenge = FaucetService.Challenge(challenge: "abc", difficulty: difficulty, challengeCounter: 1, challengesNeeded: 1)
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.solve(challenge) }
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.validate(challenge) }
        let json = Data(#"{"challenge":"c1","difficulty":\#(difficulty),"challengeCounter":1,"challengesNeeded":1}"#.utf8)
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.challenge(from: json) }
    }

    @Test func refusesUnreasonableCountsAndLengths() throws {
        func challenge(_ json: String) throws -> FaucetService.Challenge { try FaucetService.challenge(from: Data(json.utf8)) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1,"challengeCounter":0,"challengesNeeded":1}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1,"challengeCounter":1,"challengesNeeded":0}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1,"challengeCounter":1,"challengesNeeded":1001}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1,"challengeCounter":99,"challengesNeeded":5}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"","difficulty":1,"challengeCounter":1,"challengesNeeded":1}"#) }
        let long = String(repeating: "x", count: FaucetService.Limits.challengeLength + 1)
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"\#(long)","difficulty":1,"challengeCounter":1,"challengesNeeded":1}"#) }
        // Fractions, booleans and absurd numbers are not counters.
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1.5,"challengeCounter":1,"challengesNeeded":1}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":true,"challengeCounter":1,"challengesNeeded":1}"#) }
        #expect(throws: FaucetService.FaucetError.self) { try challenge(#"{"challenge":"c","difficulty":1,"challengeCounter":1e30,"challengesNeeded":1}"#) }
        // The sequence must move forward and never grow.
        let first = try challenge(#"{"challenge":"c1","difficulty":1,"challengeCounter":1,"challengesNeeded":3}"#)
        #expect(try FaucetService.challenge(from: Data(#"{"challenge":"c2","difficulty":1,"challengeCounter":2}"#.utf8), after: first).challengesNeeded == 3)
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.challenge(from: Data(#"{"challenge":"c2","difficulty":1,"challengeCounter":1}"#.utf8), after: first) }
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.challenge(from: Data(#"{"challenge":"c2","difficulty":1,"challengeCounter":2,"challengesNeeded":50}"#.utf8), after: first) }
        // Faucet limits and amounts must be finite and positive.
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.checked(FaucetService.Info(faucetAddress: "tz1", challengesEnabled: true, minTez: -1, maxTez: 10)) }
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.checked(FaucetService.Info(faucetAddress: "tz1", challengesEnabled: true, minTez: 10, maxTez: 1)) }
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.checked(FaucetService.Info(faucetAddress: "tz1", challengesEnabled: true, minTez: 1, maxTez: .infinity)) }
        #expect(!FaucetService.isReasonableAmount(.nan) && !FaucetService.isReasonableAmount(0) && FaucetService.isReasonableAmount(100))
    }

    /// A hard challenge stops when its task is cancelled or its deadline passes, instead of
    /// burning CPU forever.
    @Test(.timeLimit(.minutes(1))) func hardChallengesAreCancellableAndBounded() async throws {
        let hard = FaucetService.Challenge(challenge: "never", difficulty: 8, challengeCounter: 1, challengesNeeded: 1)
        let worker = Task.detached { () throws -> (nonce: Int, solution: String) in try FaucetService.solve(hard) }
        try await Task.sleep(for: .milliseconds(200))
        worker.cancel()
        await #expect(throws: FaucetService.FaucetError.cancelled) { try await worker.value }

        let started = Date()
        #expect(throws: FaucetService.FaucetError.timedOut) { try FaucetService.solve(hard, deadline: Date().addingTimeInterval(0.3)) }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func parsesChallengeAndHashReplies() throws {
        let first = Data(#"{"challenge":"c1","difficulty":4,"challengeCounter":1,"challengesNeeded":5}"#.utf8)
        let parsed = try FaucetService.challenge(from: first)
        #expect(parsed == FaucetService.Challenge(challenge: "c1", difficulty: 4, challengeCounter: 1, challengesNeeded: 5))

        let later = Data(#"{"challenge":"c2","difficulty":4,"challengeCounter":2}"#.utf8)
        #expect(try FaucetService.challenge(from: later).challengeCounter == 2)

        #expect(try FaucetService.txHash(from: Data(#"{"txHash":"ooABC"}"#.utf8)) == "ooABC")
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.txHash(from: later) }
        #expect(throws: FaucetService.FaucetError.self) { try FaucetService.challenge(from: Data(#"{"message":"Too many requests"}"#.utf8)) }
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(3)))
    func shadownetFaucetFundsAFreshAddress() async throws {
        let fresh = Address(try await KeyGenerator().generate(scheme: .tz1).address)
        let faucet = FaucetService(baseURL: Network.shadownet.faucetURL!)
        let info = try await faucet.info()
        #expect(info.minTez >= 0)

        let hash = try await faucet.requestTez(to: fresh, amount: info.minTez)
        #expect(hash.hasPrefix("o"))
        #expect(hash.count == 51)
    }
}

struct QuantumnetTests {
    @Test func quantumnetIsConfiguredOffTeztnets() {
        let q = Network.quantumnet
        #expect(q.rpcURL.absoluteString == "https://quantumnet.pqpark.dal.nomadic-labs.com/rpc")
        #expect(q.tzktURL?.host() == "quantumnet-tzkt.pqpark.dal.nomadic-labs.com")
        #expect(q.faucetKind == .pqpark)
        #expect(q.explorerURL(operation: "ooX")?.absoluteString == "https://quantumnet-tzkt.pqpark.dal.nomadic-labs.com/#op/ooX")
        #expect(Network.mainnet.explorerURL(operation: "ooX")?.absoluteString == "https://tzkt.io/ooX")
        #expect(Network.shadownet.explorerURL(operation: "ooX") == URL(string: "https://shadownet.tzkt.io/ooX"))
        #expect(Network.all.map(\.name).contains("Quantumnet"))
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func quantumnetNodeFaucetAndIndexerAnswer() async throws {
        let faucet = try #require(FaucetService(network: .quantumnet))
        let info = try await faucet.info()
        #expect(info.faucetAddress.hasPrefix("tz"))
        #expect(info.minTez == 1)
        let header = try await NodeMonitor.urlSessionProbe(Network.quantumnet.rpcURL.appendingPathComponent("chains/main/blocks/head/header"))
        #expect(NodeMonitor.evaluate(.success(header), now: Date()).light != .red)
    }
}
