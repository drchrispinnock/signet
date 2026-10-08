import Foundation
import Testing
@testable import Signet

struct NodeMonitorTests {
    private func header(level: Int, ageSeconds: TimeInterval, now: Date) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let stamp = iso.string(from: now.addingTimeInterval(-ageSeconds))
        return Data("{\"level\": \(level), \"timestamp\": \"\(stamp)\", \"hash\": \"BL1\"}".utf8)
    }

    @Test func freshHeadIsGreen() {
        let now = Date()
        let status = NodeMonitor.evaluate(.success((header(level: 100, ageSeconds: 12, now: now), 200, 0.3)), now: now)
        guard case .healthy(let level, let age, let latency) = status else { Issue.record("expected healthy, got \(status)"); return }
        #expect(level == 100)
        #expect(abs(age - 12) < 1)
        #expect(latency == 0.3)
        #expect(status.light == .green)
    }

    @Test func staleHeadSlowReplyAndBadPayloadAreYellow() {
        let now = Date()
        let stale = NodeMonitor.evaluate(.success((header(level: 5, ageSeconds: 600, now: now), 200, 0.2)), now: now)
        #expect(stale.light == .yellow)
        #expect(stale.level == 5)
        #expect(stale.summary.contains("behind"))

        let slow = NodeMonitor.evaluate(.success((header(level: 7, ageSeconds: 5, now: now), 200, 6.0)), now: now)
        #expect(slow.light == .yellow)
        #expect(slow.summary.contains("slow"))

        let http = NodeMonitor.evaluate(.success((Data(), 503, 0.1)), now: now)
        #expect(http.light == .yellow)
        #expect(http.summary.contains("503"))

        let junk = NodeMonitor.evaluate(.success((Data("<html>".utf8), 200, 0.1)), now: now)
        #expect(junk.light == .yellow)
    }

    @Test func connectionFailureIsRed() {
        let status = NodeMonitor.evaluate(.failure(URLError(.cannotFindHost)), now: Date())
        #expect(status.light == .red)
        #expect(status.summary == "Node down")
        #expect(status.detail.hasPrefix("Cannot reach node"))
    }

    @MainActor
    @Test func monitorPublishesProbeResultsAndFollowsNetworkChanges() async {
        let monitor = NodeMonitor(network: .mainnet) { url in
            if url.host() == Network.mainnet.rpcURL.host() {
                return (Data("{\"level\": 1, \"timestamp\": \"\(ISO8601DateFormatter().string(from: Date()))\"}".utf8), 200, 0.1)
            }
            throw URLError(.timedOut)
        }
        await monitor.checkNow()
        #expect(monitor.status.light == .green)

        monitor.network = .shadownet
        #expect(monitor.status == .unknown)
        await monitor.checkNow()
        #expect(monitor.status.light == .red)
        monitor.stop()
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func mainnetIsReachable() async throws {
        let reply = try await NodeMonitor.urlSessionProbe(Network.mainnet.rpcURL.appendingPathComponent("chains/main/blocks/head/header"))
        let status = NodeMonitor.evaluate(.success(reply), now: Date())
        #expect(status.light != .red)
        #expect(status.level ?? 0 > 0)
    }
}


struct FaucetTests {
    @Test func testnetsHaveFaucetsAndMainnetDoesNot() {
        #expect(Network.mainnet.faucetURL == nil)
        for network in Network.all where !network.isMainnet && network.chain != "custom" {
            #expect(network.faucetURL?.host()?.contains("faucet") == true, Comment(rawValue: network.name))
        }
    }
}

struct NodeTextTests {
    @Test func bareHostsBecomeHTTPS() {
        #expect(Network.nodeURL(from: "rpc.tzbeta.net")?.absoluteString == "https://rpc.tzbeta.net")
        #expect(Network.nodeURL(from: " rpc.tzbeta.net/ ")?.absoluteString == "https://rpc.tzbeta.net")
        #expect(Network.nodeURL(from: "https://rpc.shadownet.teztnets.com")?.host() == "rpc.shadownet.teztnets.com")
        #expect(Network.nodeURL(from: "http://localhost:8732")?.absoluteString == "http://localhost:8732")
        #expect(Network.nodeURL(from: "node.example.org:8732/tezos")?.absoluteString == "https://node.example.org:8732/tezos")
        #expect(Network.nodeURL(from: "") == nil)
        #expect(Network.nodeURL(from: "not a host") == nil)
    }

    @Test func displayTextIsTheFullURL() {
        #expect(Network.mainnet.nodeDisplayText == "https://rpc.tzbeta.net")
        #expect(Network.custom.nodeDisplayText == "http://localhost:8732")
        #expect(Network.mainnet.usingNode(URL(string: "http://localhost:8732")!).nodeDisplayText == "http://localhost:8732")
    }
}

@MainActor
struct PerNetworkNodeTests {
    @Test func editsAnotherNetworksNodeWithoutSwitching() {
        let state = InMemoryAppStateStore()
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: state)
        #expect(model.network.name == "Mainnet")

        #expect(model.setNode("rpc.shadownet.example.org", for: .shadownet))
        #expect(model.network.name == "Mainnet")                       // still on mainnet
        #expect(model.nodeURL(for: .shadownet).host() == "rpc.shadownet.example.org")
        #expect(state.load().nodeURLs?["Shadownet"] == "https://rpc.shadownet.example.org")

        model.switchNetwork(to: .shadownet)                              // the saved node comes along
        #expect(model.network.rpcURL.host() == "rpc.shadownet.example.org")

        model.useDefaultNode(for: .shadownet)
        #expect(model.network.rpcURL == Network.shadownet.defaultRPCURL)
        #expect(state.load().nodeURLs?["Shadownet"] == nil)

        #expect(Network.all.contains { $0.name == "Custom" })
        #expect(model.setNode("node.mine.example:8732", for: .custom))
        #expect(model.nodeURL(for: .custom).absoluteString == "https://node.mine.example:8732")
        #expect(!model.setNode("not a host", for: .custom))
    }
}
