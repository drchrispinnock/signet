import Foundation
import Testing
@testable import Signet

/// F17: exercise the shipped watcher through JavaScriptCore and the native read-call boundary.
private final class ConfirmationProtocol: URLProtocol, @unchecked Sendable {
    final class Fixture: @unchecked Sendable {
        enum Mode { case included, malformed, held, exhausted }
        let mode: Mode
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        private let lock = NSLock()
        private var requests: [String] = []
        private var headers = 0
        func headLevel() -> Int { lock.withLock { headers += 1; return mode == .exhausted ? 109 + headers : 102 } }
        init(_ mode: Mode) { self.mode = mode }
        func record(_ path: String) { lock.withLock { requests.append(path) }; started.continuation.yield(()) }
        var paths: [String] { lock.withLock { requests } }
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: Fixture] = [:]
        func set(_ fixture: Fixture?, for host: String) { lock.withLock { fixtures[host] = fixture } }
        func get(_ host: String) -> Fixture? { lock.withLock { fixtures[host] } }
    }
    private static let registry = Registry()
    static func register(_ fixture: Fixture, host: String) { registry.set(fixture, for: host) }
    static func remove(host: String) { registry.set(nil, for: host) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host()?.hasSuffix(".confirmation.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let fixture = Self.registry.get(url.host()!), let client else { return }
        fixture.record(url.path)
        if fixture.mode == .held { return }
        let body: String
        if url.path.hasSuffix("/header") { body = "{\"level\":\(fixture.headLevel())}" }
        else if fixture.mode == .malformed { body = "{\"operations\":42}" }
        else { body = fixture.mode == .included && url.path.hasSuffix("/101") ? "{\"operations\":[[],[],[],[{\"hash\":\"ooFixture\"}]]}" : "{\"operations\":[[],[],[],[]]}" }
        client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Data(body.utf8))
        client.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        if let host = request.url?.host() { Self.registry.get(host)?.stopped.continuation.yield(()) }
    }
}

struct ConfirmationWatcherTests {
    private func fixture(_ mode: ConfirmationProtocol.Fixture.Mode) throws -> (ConfirmationProtocol.Fixture, TaquitoChainService, String) {
        let host = "\(UUID().uuidString.lowercased()).confirmation.invalid"
        let f = ConfirmationProtocol.Fixture(mode)
        ConfirmationProtocol.register(f, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConfirmationProtocol.self]
        let bridge = TaquitoBridge(session: URLSession(configuration: configuration), systemLog: { _ in })
        let url = URL(string: "https://\(host)/selected-node")!
        try bridge.operationJournal.save("{\"hash\":\"ooFixture\",\"signedBytes\":\"fixture\",\"rpcURL\":\"\(url.absoluteString)\",\"headLevel\":100}")
        return (f, TaquitoChainService(network: Network.mainnet.usingNode(url), bridge: bridge), host)
    }

    @Test(.timeLimit(.minutes(1))) func nativeConfirmationUsesSelectedNodeHashAndRemovesJournalRecord() async throws {
        let (f, chain, host) = try fixture(.included)
        defer { ConfirmationProtocol.remove(host: host) }
        #expect(try await chain.waitForConfirmation(of: "ooFixture") == 101)
        #expect(f.paths == ["/selected-node/chains/main/blocks/head/header", "/selected-node/chains/main/blocks/99", "/selected-node/chains/main/blocks/100", "/selected-node/chains/main/blocks/101"])
        #expect(try chain.bridge.operationJournal.read() == "[]")
    }

    @Test(.timeLimit(.minutes(1))) func nativeWatcherUsesFifteenBlockBudgetAndRetainsCursorOnExhaustion() async throws {
        let (f, chain, host) = try fixture(.exhausted)
        defer { ConfirmationProtocol.remove(host: host) }
        let error = await #expect(throws: TaquitoBridge.BridgeError.self) { try await chain.waitForConfirmation(of: "ooFixture") }
        guard case .javaScript(let message)? = error else {
            Issue.record("expected watcher exhaustion")
            return
        }
        #expect(message == "operation ooFixture not seen in 15 blocks")
        #expect(f.paths.filter { $0.hasSuffix("/header") }.count == 4)
        #expect(try chain.bridge.operationJournal.read().contains("\"lastCheckedLevel\":113"))
    }

    @Test(.timeLimit(.minutes(1))) func malformedBlockRetainsRecoveryRecord() async throws {
        let (_, chain, host) = try fixture(.malformed)
        defer { ConfirmationProtocol.remove(host: host) }
        await #expect(throws: TaquitoBridge.BridgeError.self) { try await chain.waitForConfirmation(of: "ooFixture") }
        #expect(try chain.bridge.operationJournal.read().contains("ooFixture"))
    }

    @Test(.timeLimit(.minutes(1))) func cancellationStopsHTTPAndKeepsRecoveryRecord() async throws {
        let (f, chain, host) = try fixture(.held)
        defer { ConfirmationProtocol.remove(host: host) }
        let pending = Task { try await chain.waitForConfirmation(of: "ooFixture") }
        var started = f.started.stream.makeAsyncIterator()
        _ = await started.next()
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        var stopped = f.stopped.stream.makeAsyncIterator()
        _ = await stopped.next()
        #expect(try chain.bridge.operationJournal.read().contains("ooFixture"))
        #expect(try await chain.bridge.call("version").stringValue != nil, "cancelled read context can be replaced safely")
    }

    @Test(.timeLimit(.minutes(1))) func watcherDeadlineStopsHTTPAndKeepsRecoveryRecord() async throws {
        let (f, chain, host) = try fixture(.held)
        defer { ConfirmationProtocol.remove(host: host) }
        let error = await #expect(throws: TaquitoBridge.BridgeError.self) {
            try await chain.bridge.call("waitForRawOperation", [chain.network.rpcURL.absoluteString, "ooFixture", 15], timeout: 0.1)
        }
        guard case .timedOut(let name, let timeout)? = error else {
            Issue.record("expected the watcher deadline error")
            return
        }
        #expect(name == "waitForRawOperation" && timeout == 0.1)
        var stopped = f.stopped.stream.makeAsyncIterator()
        _ = await stopped.next()
        #expect(try chain.bridge.operationJournal.read().contains("ooFixture"))
    }
}
