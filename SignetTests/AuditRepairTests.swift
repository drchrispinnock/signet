import Foundation
import Testing
import WebKit
@testable import Signet

struct AuditRepairTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signet-repair-\(UUID().uuidString)")
        try PrivateFile.hardenDirectory(url)
        return url
    }

    @Test func walletLockSerializesThreads() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let second = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            try? TezosClientStore.withWalletLock(in: root) {
                entered.signal()
                _ = release.wait(timeout: .now() + 3)
            }
        }
        #expect(entered.wait(timeout: .now() + 2) == .success)
        DispatchQueue.global().async {
            defer { done.signal() }
            try? TezosClientStore.withWalletLock(in: root) { second.signal() }
        }
        #expect(second.wait(timeout: .now() + 0.15) == .timedOut)
        release.signal()
        #expect(second.wait(timeout: .now() + 2) == .success)
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(done.wait(timeout: .now() + 2) == .success)
    }

    @Test func backupRecoversBeforeItsFirstSnapshot() throws {
        let root = try directory(), backup = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: backup) }
        let old = Data("[{\"name\":\"before\",\"value\":\"synthetic\"}]".utf8)
        let new = Data("[{\"name\":\"after\",\"value\":\"synthetic\"}]".utf8)
        let name = TezosClientStore.publicKeyHashesFile
        try PrivateFile.write(new, to: root.appendingPathComponent(name))
        let journal = try JSONSerialization.data(withJSONObject: ["version": 1, "files": [name: old.base64EncodedString()]])
        try PrivateFile.write(journal, to: root.appendingPathComponent(TezosClientStore.journalFile))
        let result = try WalletBackup(walletDirectory: root, backupDirectory: backup, generations: 2).run()
        guard case .created(let generation) = result else { Issue.record("Expected a recovered backup"); return }
        #expect(try Data(contentsOf: generation.appendingPathComponent(name)) == old)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(TezosClientStore.journalFile).path))
    }

    @MainActor @Test func failedGrantRefreshCannotUseTheCache() async throws {
        let manager = DAppConnectionManager(storage: InMemoryBridgeStorage(), permissionLoader: { throw URLError(.timedOut) }, wallets: { [] }, signer: { _, _ in nil })
        manager.permissionsOverride = [DAppGrantTests.grant()]
        await manager.reloadPermissions()
        #expect(manager.permissions.count == 1)
        manager.permissionsOverride = nil
        await #expect(throws: (any Error).self) { try await manager.grant(for: DAppGrantTests.sign) }
        await manager.reloadPermissions()
        #expect(manager.permissions.isEmpty)
    }

    @Test func journalSurvivesReconstructionAndRefusesAReplacement() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = OperationJournal(directory: root)
        let record = "{\"hash\":\"synthetic-op\",\"signedBytes\":\"abab\",\"rpcURL\":\"https://offline.invalid\",\"source\":\"synthetic-account\"}"
        try first.save(record)
        let reopened = OperationJournal(directory: root)
        #expect(try reopened.read().contains("synthetic-op"))
        #expect(throws: (any Error).self) { try reopened.save(record.replacingOccurrences(of: "synthetic-op", with: "replacement")) }
        try reopened.remove("synthetic-op")
        #expect(try reopened.read() == "[]")
        let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("pending_operations.json").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func publicConnectionsPinTheCheckedAddressAndRefusePrivateAnswers() throws {
        var request = URLRequest(url: URL(string: "https://example.org:8443/path?token=sensitive")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"value\":\"synthetic\"}".utf8)
        let config = try PublicHTTPClient.configuration(for: request, addresses: ["8.8.8.8"], limit: 1024)
        #expect(config.contains("resolve = \"example.org:8443:8.8.8.8\""))
        #expect(config.contains("noproxy = \"*\""))
        #expect(!config.contains("location"))
        #expect(throws: (any Error).self) { try PublicHTTPClient.configuration(for: request, addresses: ["8.8.8.8", "127.0.0.1"], limit: 1024) }
        #expect(throws: (any Error).self) { try PublicHTTPClient.configuration(for: request, addresses: ["::ffff:7f00:1"], limit: 1024) }
        let reply = try PublicHTTPClient.decode(Data("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\nabc".utf8), limit: 3)
        #expect(reply.status == 200 && reply.data == Data("abc".utf8))
        #expect(throws: (any Error).self) { try PublicHTTPClient.decode(Data("HTTP/1.1 200 OK\r\n\r\nabcdef".utf8), limit: 3) }
    }

    @Test func purchasePrivilegesIncludeThePortAndEndpointsIncludeQueries() {
        let provider = BuyProvider.mtPelerin
        #expect(!BuyWebView.isTrusted(URL(string: "https://widget.mtpelerin.com:8443/"), provider: provider))
        #expect(!BuyWebView.mayCaptureMedia(originProtocol: "https", originHost: "widget.mtpelerin.com", isMainFrame: true, frameProtocol: "https", frameHost: "widget.mtpelerin.com", provider: provider, originPort: 443, framePort: 8443))
        #expect(!DAppRequest.sameEndpoint(URL(string: "https://example.org/rpc?chain=a"), URL(string: "https://example.org/rpc?chain=b")))
    }

    @Test func aDefaultBridgeHasNoDiskStorage() {
        #expect(TaquitoBridge().storage is InMemoryBridgeStorage)
    }
    @Test func ledgerDeviceLeaseSerializesIndependentClients() async throws {
        let sessions = LedgerSessions()
        let first = try await sessions.acquire(device: "synthetic-device")
        actor Probe { var entered = false; func mark() { entered = true } }
        let probe = Probe()
        let other = Task {
            let lease = try await sessions.acquire(device: "synthetic-device")
            await probe.mark()
            return lease
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await probe.entered == false)
        await sessions.release(id: first, device: "synthetic-device")
        let second = try await other.value
        #expect(await probe.entered)
        await sessions.release(id: second, device: "synthetic-device")
    }

    @MainActor @Test func anInvalidatedDirectorySessionCannotReadANewGrant() async throws {
        let manager = DAppConnectionManager(storage: InMemoryBridgeStorage(), permissionLoader: { [DAppGrantTests.grant()] }, wallets: { [] }, signer: { _, _ in nil })
        manager.invalidate()
        await #expect(throws: (any Error).self) { try await manager.grant(for: DAppGrantTests.sign) }
    }

    @Test func HTTPParsingBudgetPrecedesSDKParsingAndDecryption() {
        #expect(!JSONBudget.accepts(Data((String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)).utf8)))
        #expect(!JSONBudget.accepts(Data(("[\"" + String(repeating: "a", count: (1 << 20) + 1) + "\"]").utf8)))
        #expect(!JSONBudget.accepts(Data("[0,0,0,0,0]".utf8), nodeLimit: 3))
        #expect(JSONBudget.accepts(Data("{\"quoted\":\"[[[\\\"\"}".utf8), depthLimit: 2))
    }

    @Test func artworkSlotsCoverActualDownloadWork() async {
        actor Meter {
            var active = 0, peak = 0
            func begin() { active += 1; peak = max(peak, active) }
            func end() { active -= 1 }
        }
        let meter = Meter()
        let loader = ImageLoader(download: { _ in
            await meter.begin()
            try? await Task.sleep(for: .milliseconds(30))
            await meter.end()
            return nil
        })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<24 {
                group.addTask { _ = await loader.image(for: [URL(string: "https://artwork.example.org/\(i)")!]) }
            }
        }
        #expect(await meter.peak <= ImageLoader.maxConcurrent)
        #expect(await meter.peak > 1)
        #expect(await meter.active == 0)
    }

}

/// Transport seams exercise timeout cleanup and wrong-chain refusal without using the network.
private final class AuditHTTPProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var stops: Set<String> = []
        func stopped(_ url: String) { lock.withLock { _ = stops.insert(url) } }
        func contains(_ url: String) -> Bool { lock.withLock { stops.contains { $0.hasPrefix(url) } } }
    }
    private static let state = State()
    static func wasStopped(_ url: String) -> Bool { state.contains(url) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "offline.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path.contains("wrong-chain") {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("\"NetWrongChain\"".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        // Other paths deliberately remain in flight until the bridge cancels them.
    }
    override func stopLoading() { Self.state.stopped(request.url?.absoluteString ?? "") }
}

struct BridgeBoundaryRepairTests {
    private func bridge() -> TaquitoBridge {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuditHTTPProtocol.self]
        return TaquitoBridge(session: URLSession(configuration: config))
    }

    @Test func timeoutCancelsHTTPAndRebuildsACleanContext() async throws {
        let bridge = bridge()
        let url = "https://offline.invalid/timeout-\(UUID().uuidString)"
        await #expect(throws: (any Error).self) { try await bridge.call("getHead", [url], timeout: 0.05) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(AuditHTTPProtocol.wasStopped(url))
        #expect(try await bridge.call("version").stringValue != nil)
    }

    @Test func multisigChecksTheSelectedChainBeforeReadingContractData() async throws {
        let network = Network.mainnet.usingNode(URL(string: "https://offline.invalid/wrong-chain")!)
        let service = BridgeMultisigService(bridge: bridge(), network: network)
        do {
            _ = try await service.info(rpcURL: network.rpcURL, address: MockMultisigService.sampleAddress)
            Issue.record("A wrong-chain multisig read must fail")
        } catch { #expect(error.localizedDescription.contains("serves chain NetWrongChain")) }
    }
}

private struct ContextSwitchingMultisig: MultisigService {
    let change: @MainActor @Sendable () -> Void
    func prepare(rpcURL: URL, contract: Address, action: MultisigAction) async throws -> (info: MultisigInfo, chainID: String, bytes: String) {
        await change()
        return (MultisigInfo(address: contract, isGenericMultisig: true, scriptHash: "fixture", counter: 0, threshold: 1, keys: ["fixture"], balance: 0), "NetFixture", "0500")
    }
    func info(rpcURL: URL, address: Address) async throws -> MultisigInfo { throw URLError(.unsupportedURL) }
    func revealedPublicKey(rpcURL: URL, address: Address) async throws -> String? { throw URLError(.unsupportedURL) }
    func address(forPublicKey publicKey: String) async throws -> Address { throw URLError(.unsupportedURL) }
    func sign(signer: SigningKey, proposal: MultisigProposal) async throws -> (bytes: String, signature: String) { throw URLError(.unsupportedURL) }
    func estimateOriginate(rpcURL: URL, from wallet: Wallet, threshold: Int, keys: [String]) async throws -> MultisigEstimate { throw URLError(.unsupportedURL) }
    func originate(rpcURL: URL, signer: SigningKey, threshold: Int, keys: [String], limits: OperationLimits) async throws -> (hash: String, address: Address) { throw URLError(.unsupportedURL) }
    func estimateSubmit(rpcURL: URL, from wallet: Wallet, proposal: MultisigProposal, signatures: [String]) async throws -> MultisigEstimate { throw URLError(.unsupportedURL) }
    func submit(rpcURL: URL, signer: SigningKey, proposal: MultisigProposal, signatures: [String], limits: OperationLimits) async throws -> String { throw URLError(.unsupportedURL) }
}

@MainActor
struct MultisigContextRepairTests {
    private final class Box { var model: WalletViewModel? }
    @Test(arguments: [false, true]) func proposalsRefuseSameNameEndpointAndAwayBackChanges(awayAndBack: Bool) async throws {
        let box = Box()
        let service = ContextSwitchingMultisig {
            guard let model = box.model else { return }
            if awayAndBack { model.network = .shadownet; model.network = .mainnet }
            else { model.network = model.network.usingNode(URL(string: "https://alternate.example.org")!) }
        }
        let model = WalletViewModel(wallets: [], chain: MockChainService(), multisig: service, walletStore: InMemoryWalletStore())
        box.model = model
        let contract = MultisigContract(alias: "fixture", address: MockMultisigService.sampleAddress)
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.proposeMultisig(.setDelegate(delegate: nil), from: contract) }
        #expect(model.multisigProposals.isEmpty)
    }
}
