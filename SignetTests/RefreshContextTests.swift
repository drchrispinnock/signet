import Foundation
import Testing
@testable import Signet

/// S16: a load started for one account or network never lands on the screen of another.
/// The fixture answers only when the test says so, so ordering is stated, never timed (F25).
@MainActor
struct RefreshContextTests {
    nonisolated static let a = Wallet(alias: "A", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted)
    nonisolated static let b = Wallet(alias: "B", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), keyKind: .unencrypted)

    /// Opened once by the test; waiters before and after that all pass.
    actor Latch {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() { opened = true; for w in waiters { w.resume() }; waiters = [] }
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// One pair of latches per (account, network) request: `started` is opened by the chain when
    /// the balance request arrives, `release` by the test when the answer may go out.
    final class Gates: @unchecked Sendable {
        private let lock = NSLock()
        private var started: [String: Latch] = [:]
        private var release: [String: Latch] = [:]
        private func key(_ address: Address, _ network: Network) -> String { "\(address.value)@\(network.name)" }
        func started(_ wallet: Wallet, _ network: Network) -> Latch { latch(&started, key(wallet.address, network)) }
        func release(_ wallet: Wallet, _ network: Network) -> Latch { latch(&release, key(wallet.address, network)) }
        func startedLatch(_ address: Address, _ network: Network) -> Latch { latch(&started, key(address, network)) }
        func releaseLatch(_ address: Address, _ network: Network) -> Latch { latch(&release, key(address, network)) }
        private func latch(_ map: inout [String: Latch], _ key: String) -> Latch {
            lock.lock(); defer { lock.unlock() }
            if let l = map[key] { return l }
            let l = Latch(); map[key] = l; return l
        }
    }

    /// Reports each balance request and holds its answer until released; names its network in the domain.
    final class GatedChain: TestChainService, @unchecked Sendable {
        let network: Network
        let gates: Gates
        init(network: Network, gates: Gates) { self.network = network; self.gates = gates }
        func tezBalance(for address: Address) async throws -> TezBalance {
            await gates.startedLatch(address, network).open()
            await gates.releaseLatch(address, network).wait()
            return TezBalance(spendable: address == RefreshContextTests.a.address ? 5 : 7, staked: 0)
        }
        func domains(for address: Address) async throws -> [String] { ["\(network.name.lowercased()).tez"] }
    }

    /// Polls the main actor until `condition` holds; a refresh started by `select` or a network
    /// switch runs in its own task, so its publication can only be waited for, not awaited.
    private func settle(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), "the model did not settle in time")
    }

    @Test(.timeLimit(.minutes(1))) func aSlowLoadForThePreviousAccountIsDropped() async throws {
        let gates = Gates()
        let model = WalletViewModel(wallets: [Self.a, Self.b], chainFactory: { GatedChain(network: $0, gates: gates) })
        let slow = Task { await model.refresh() }                       // A's load starts…
        await gates.started(Self.a, .mainnet).wait()
        #expect(model.isLoading)
        model.select(Self.b)                                             // …and is superseded.
        #expect(model.tezBalance == nil && !model.isLoading, "switching clears the dashboard at once")
        await gates.started(Self.b, .mainnet).wait()
        await gates.release(Self.b, .mainnet).open()                     // B answers first.
        try await settle { model.tezBalance != nil }
        #expect(model.tezBalance?.spendable == 7 && model.domains == ["mainnet.tez"] && !model.isLoading)
        await gates.release(Self.a, .mainnet).open()                     // A's answer arrives late.
        await slow.value
        #expect(model.tezBalance?.spendable == 7)
        #expect(model.selectedWallet?.alias == "B" && model.network == .mainnet && !model.isLoading)
    }

    @Test(.timeLimit(.minutes(1))) func aSlowLoadForThePreviousNetworkIsDropped() async throws {
        let gates = Gates()
        let model = WalletViewModel(wallets: [Self.a], chainFactory: { GatedChain(network: $0, gates: gates) })
        let slow = Task { await model.refresh() }                       // mainnet's load starts…
        await gates.started(Self.a, .mainnet).wait()
        model.switchNetwork(to: .shadownet)                              // …and Shadownet's replaces it.
        #expect(model.tezBalance == nil && model.domains.isEmpty)
        await gates.started(Self.a, .shadownet).wait()
        await gates.release(Self.a, .mainnet).open()                     // mainnet answers first, too late.
        await slow.value
        #expect(model.tezBalance == nil && model.domains.isEmpty, "mainnet's answer must not appear")
        await gates.release(Self.a, .shadownet).open()
        try await settle { model.tezBalance != nil }
        #expect(model.domains == ["shadownet.tez"] && model.tezBalance?.spendable == 5)
        #expect(model.network == .shadownet && !model.isLoading)
    }
}
