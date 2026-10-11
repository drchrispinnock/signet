import Foundation
import Testing
@testable import Signet

/// S16: a load started for one account or network never lands on the screen of another.
@MainActor
struct RefreshContextTests {
    nonisolated static let a = Wallet(alias: "A", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted)
    nonisolated static let b = Wallet(alias: "B", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), keyKind: .unencrypted)

    /// Answers for account A slowly and for B at once; records which network each call saw.
    final class SlowChain: TestChainService, @unchecked Sendable {
        let network: Network
        init(network: Network) { self.network = network }
        func tezBalance(for address: Address) async throws -> TezBalance {
            if address == RefreshContextTests.a.address { try await Task.sleep(for: .milliseconds(700)) }
            return TezBalance(spendable: address == RefreshContextTests.a.address ? 5 : 7, staked: 0)
        }
        func domains(for address: Address) async throws -> [String] { ["\(network.name.lowercased()).tez"] }
    }

    @Test func aSlowLoadForThePreviousAccountIsDropped() async throws {
        let model = WalletViewModel(wallets: [Self.a, Self.b], chainFactory: { SlowChain(network: $0) })
        let slow = Task { await model.refresh() }           // loading A, takes 700 ms
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.isLoading)
        model.select(Self.b)                                   // B answers at once
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.tezBalance?.spendable == 7)
        await slow.value                                       // A's answer arrives late
        #expect(model.tezBalance?.spendable == 7)
        #expect(model.selectedWallet?.alias == "B")
        #expect(!model.isLoading)
    }

    @Test func aSlowLoadForThePreviousNetworkIsDropped() async throws {
        let model = WalletViewModel(wallets: [Self.a], chainFactory: { SlowChain(network: $0) })
        let slow = Task { await model.refresh() }           // mainnet, slow
        try await Task.sleep(for: .milliseconds(100))
        model.switchNetwork(to: .shadownet)                    // clears and reloads on Shadownet (also slow for A)
        #expect(model.tezBalance == nil && model.domains.isEmpty)
        await slow.value
        #expect(model.domains.isEmpty, "mainnet's answer must not appear")
        try await Task.sleep(for: .milliseconds(900))
        #expect(model.domains == ["shadownet.tez"])
        #expect(model.tezBalance?.spendable == 5)
    }
}
