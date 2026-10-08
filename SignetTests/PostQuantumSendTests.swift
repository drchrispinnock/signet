import Foundation
import Testing
@testable import Signet

/// The whole tz5 story on a live testnet: make an ML-DSA-44 key, fund it from the faucet, let the
/// node see it, estimate and send tez from it (reveal + transaction, both ML-DSA signed).
///
/// Known blocker (2026-10-08): the Shadownet faucet rejects tz5 destinations with
/// "The address 'tz5…' is invalid", so this fails at the funding step until the faucet is fixed.
struct PostQuantumSendTests {
    @Test(.tags(.network), .timeLimit(.minutes(5)))
    func tz5WalletCanReceiveAndSendOnShadownet() async throws {
        let generator = KeyGenerator()
        let quantum = try await generator.generate(scheme: .tz5)
        #expect(quantum.address.hasPrefix("tz5"))
        let wallet = Wallet(alias: "pq-test", address: Address(quantum.address), scheme: .tz5, publicKey: quantum.publicKey, keyKind: .unencrypted)

        let faucet = FaucetService(baseURL: Network.shadownet.faucetURL!)
        let fundingHash = try await faucet.requestTez(to: wallet.address, amount: 2)
        #expect(fundingHash.hasPrefix("o"))

        let chain = TaquitoChainService(network: .shadownet)
        var balance: TezBalance?
        for _ in 0..<24 {
            try await Task.sleep(for: .seconds(5))
            if let b = try? await chain.tezBalance(for: wallet.address), b.spendable > 0 { balance = b; break }
        }
        let funded = try #require(balance, "faucet transfer to the tz5 address never showed up")
        #expect(funded.spendable >= 2)

        let destination = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let estimate = try await chain.estimateTransfer(from: wallet, to: destination, amount: Decimal(string: "0.5")!)
        #expect(estimate.fee > 0)

        let hash = try await chain.sendTransfer(from: wallet, secretKey: quantum.secretKey, passphrase: nil, to: destination, amount: Decimal(string: "0.5")!)
        #expect(hash.hasPrefix("o"))
        let level = try await chain.waitForConfirmation(of: hash)
        #expect(level > 0)
    }
}

/// The same story on Quantumnet, whose faucet accepts tz5 and whose blocks are 6 s apart.
struct QuantumnetPostQuantumSendTests {
    @Test(.tags(.network), .timeLimit(.minutes(4)))
    func tz5WalletCanReceiveAndSendOnQuantumnet() async throws {
        let quantum = try await KeyGenerator().generate(scheme: .tz5)
        let wallet = Wallet(alias: "pq-test", address: Address(quantum.address), scheme: .tz5, publicKey: quantum.publicKey, keyKind: .unencrypted)
        let chain = TaquitoChainService(network: .quantumnet)

        let faucet = try #require(FaucetService(network: .quantumnet))
        let fundingHash = try await faucet.requestTez(to: wallet.address, amount: 2)
        #expect(fundingHash.hasPrefix("o"))

        var balance: TezBalance?
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(4))
            if let b = try? await chain.tezBalance(for: wallet.address), b.spendable > 0 { balance = b; break }
        }
        let funded = try #require(balance, "faucet transfer to the tz5 address never showed up")
        #expect(funded.spendable >= 2)

        let destination = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let estimate = try await chain.estimateTransfer(from: wallet, to: destination, amount: Decimal(string: "0.5")!)
        #expect(estimate.fee > 0)

        let hash = try await chain.sendTransfer(from: wallet, secretKey: quantum.secretKey, passphrase: nil, to: destination, amount: Decimal(string: "0.5")!)
        #expect(hash.hasPrefix("o"))
        let level = try await chain.waitForConfirmation(of: hash)
        #expect(level > 0)
        print("tz5 send on Quantumnet confirmed in block \(level): \(hash)")
    }
}
