import Foundation
import Testing
@testable import Signet

struct FaucetServiceTests {
    @Test func solvesAProofOfWorkChallenge() {
        let challenge = FaucetService.Challenge(challenge: "abc123", difficulty: 3, challengeCounter: 1, challengesNeeded: 1)
        let (nonce, solution) = FaucetService.solve(challenge)
        #expect(solution.hasPrefix("000"))
        #expect(solution.count == 64)
        // Reproducible: the same nonce gives the same hash.
        #expect(FaucetService.solve(challenge).nonce == nonce)
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

    @Test(.tags(.network), .timeLimit(.minutes(3)))
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
        #expect(Network.shadownet.explorerURL(operation: "ooX") == nil)
        #expect(Network.all.map(\.name).contains("Quantumnet"))
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func quantumnetNodeFaucetAndIndexerAnswer() async throws {
        let faucet = try #require(FaucetService(network: .quantumnet))
        let info = try await faucet.info()
        #expect(info.faucetAddress.hasPrefix("tz"))
        #expect(info.minTez == 1)
        let header = try await NodeMonitor.urlSessionProbe(Network.quantumnet.rpcURL.appendingPathComponent("chains/main/blocks/head/header"))
        #expect(NodeMonitor.evaluate(.success(header), now: Date()).light != .red)
    }
}
