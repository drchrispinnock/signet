import Foundation
import Testing
@testable import Signet

// MARK: - S07: a session-only Forget removes only the entry it verified

/// A key importer whose password check runs a caller's closure first, so a test can change the
/// model while Forget is waiting on the password.
private struct InterferingImporter: KeyImporter {
    let during: @MainActor @Sendable () async throws -> Void
    private let fallback = MockKeyImporter()
    func inspect(secretKey: String, passphrase: String?) async throws -> InspectedSecretKey { try await fallback.inspect(secretKey: secretKey, passphrase: passphrase) }
    func check(mnemonic: String) async throws -> MnemonicCheck { try await fallback.check(mnemonic: mnemonic) }
    func key(fromMnemonic mnemonic: String, passphrase: String?, derivationPath: String, curve: MnemonicCurve) async throws -> KeyMaterial { try await fallback.key(fromMnemonic: mnemonic, passphrase: passphrase, derivationPath: derivationPath, curve: curve) }
    func key(fromFundraiserEmail email: String, password: String, mnemonic: String) async throws -> KeyMaterial { try await fallback.key(fromFundraiserEmail: email, password: password, mnemonic: mnemonic) }
    func decrypt(secretKey: String, passphrase: String) async throws -> String {
        try await during()
        return try await fallback.decrypt(secretKey: secretKey, passphrase: passphrase)
    }
}

@MainActor
struct SessionKeyRemovalTests {
    static let paper = KeyMaterial(scheme: .tz1, publicKey: "edpkuPAPER", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", secretKey: "edeskPAPER")
    static let other = KeyMaterial(scheme: .tz1, publicKey: "edpkuOTHER", address: "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N", secretKey: "edeskOTHER")

    private final class Box: @unchecked Sendable { var model: WalletViewModel? }

    @Test func forgetRefusesAnAliasReusedDuringThePasswordCheck() async throws {
        let box = Box()
        let importer = InterferingImporter {
            guard let model = box.model else { return }
            // While the password is being checked: the account is renamed and another one takes its alias.
            try model.renameSelectedWallet(to: "Saved")
            try await model.importAccount(alias: "Paper", material: Self.other, alreadyEncrypted: true, keepForSession: true)
        }
        let model = WalletViewModel(chain: MockChainService(), keyImporter: importer)
        box.model = model
        try await model.importAccount(alias: "Paper", material: Self.paper, alreadyEncrypted: true, keepForSession: true)
        let original = try #require(model.selectedWallet)

        await #expect(throws: SessionKeyStore.StoreError.self) { try await model.forgetSelectedWallet(passphrase: "correct horse") }

        // Nothing was removed: the original lives on as "Saved", the replacement "Paper" is intact.
        #expect(Set(model.wallets.map(\.alias)) == ["Saved", "Paper"])
        let saved = try #require(model.wallets.first { $0.alias == "Saved" })
        let replacement = try #require(model.wallets.first { $0.alias == "Paper" })
        #expect(saved.address == original.address && replacement.address.value == Self.other.address)
        guard case .secret(let secret, _, _)? = try model.signingKey(for: replacement, passphrase: "correct horse") else {
            Issue.record("the replacement lost its key"); return
        }
        #expect(secret == Self.other.secretKey)
        guard case .secret(let kept, _, _)? = try model.signingKey(for: saved, passphrase: "correct horse") else {
            Issue.record("the renamed original lost its key"); return
        }
        #expect(kept == Self.paper.secretKey)
    }

    @Test func forgetRefusesARenameDuringThePasswordCheck() async throws {
        let box = Box()
        let importer = InterferingImporter {
            try box.model?.renameSelectedWallet(to: "Moved")
        }
        let model = WalletViewModel(chain: MockChainService(), keyImporter: importer)
        box.model = model
        try await model.importAccount(alias: "Paper", material: Self.paper, alreadyEncrypted: true, keepForSession: true)
        await #expect(throws: SessionKeyStore.StoreError.self) { try await model.forgetSelectedWallet(passphrase: "correct horse") }
        #expect(model.wallets.map(\.alias) == ["Moved"])
        // Asked again for what is there now, Forget works.
        try await model.forgetSelectedWallet(passphrase: "correct horse")
        #expect(model.wallets.isEmpty)
    }

    @Test func sessionStoreNeverReplacesAnEntry() throws {
        let store = SessionKeyStore()
        var a = Wallet(alias: "a", address: Address(Self.paper.address), scheme: .tz1, publicKey: "edpkA", keyKind: .unencrypted)
        try store.add(a, secretKey: "edskA")
        #expect(throws: SessionKeyStore.StoreError.self) { try store.add(a, secretKey: "edskA2") }                       // same alias
        a.alias = "b"
        #expect(throws: SessionKeyStore.StoreError.self) { try store.add(a, secretKey: "edskA2") }                       // same address
        let b = Wallet(alias: "b", address: Address(Self.other.address), scheme: .tz1, publicKey: "edpkB", keyKind: .unencrypted)
        try store.add(b, secretKey: "edskB")
        #expect(throws: SessionKeyStore.StoreError.self) { try store.rename(alias: "a", to: "b") }
        #expect(try store.secretKey(for: store.wallets[0]) == "edskA")

        // A snapshot is only good for the entry as it was: rename or removal in between refuses it.
        let snapshot = try #require(try store.removalSnapshot(for: store.wallets[0]))
        try store.rename(alias: "a", to: "c")
        #expect(throws: SessionKeyStore.StoreError.self) { try store.remove(matching: snapshot) }
        #expect(store.wallets.map(\.alias) == ["c", "b"])
        let fresh = try #require(try store.removalSnapshot(for: store.wallets[0]))
        try store.remove(matching: fresh)
        #expect(store.wallets.map(\.alias) == ["b"])
        #expect(throws: SessionKeyStore.StoreError.self) { try store.remove(matching: fresh) }
    }

    @Test func concurrentImportsOfTheSameAliasAdmitOnlyOne() async throws {
        let model = WalletViewModel(chain: MockChainService())
        let one = try await KeyGenerator().generate(scheme: .tz1)
        let two = try await KeyGenerator().generate(scheme: .tz1)
        // Both pass the first check and encrypt (an await); the second must fail the recheck.
        // Two unstructured tasks on the main actor interleave at the encryption await.
        let first = Task { @MainActor in
            (try? await model.importAccount(alias: "Paper", material: one, storePassphrase: "correct horse battery", keepForSession: true)) != nil
        }
        let second = Task { @MainActor in
            (try? await model.importAccount(alias: "Paper", material: two, storePassphrase: "correct horse battery", keepForSession: true)) != nil
        }
        let successes = (await first.value ? 1 : 0) + (await second.value ? 1 : 0)
        #expect(successes == 1)
        #expect(model.wallets.map(\.alias) == ["Paper"])
    }
}

// MARK: - S09: import reads a recovered, locked source snapshot

struct ImportSourceBoundaryTests {
    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signet-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func importRecoversTheSourceJournalBeforeReading() throws {
        let source = try tempDir("source")
        // A finished state: alice with her key. Then an unfinished change replaced the address
        // file (new address, no matching key yet) and left the journal holding the old address.
        let oldHashes = Data("""
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" } ]
        """.utf8)
        try """
        [ { "name": "alice", "value": "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq" } ]
        """.write(to: source.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": { "locator": "unencrypted:edpkALICE", "key": "edpkALICE" } } ]
        """.write(to: source.appendingPathComponent("public_keys"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": "unencrypted:edskALICE" } ]
        """.write(to: source.appendingPathComponent("secret_keys"), atomically: true, encoding: .utf8)
        let journal = ["version": 1, "files": ["public_key_hashs": oldHashes.base64EncodedString()]] as [String: Any]
        try JSONSerialization.data(withJSONObject: journal).write(to: source.appendingPathComponent(TezosClientStore.journalFile))

        let target = try tempDir("target")
        let store = TezosClientStore(directory: target)
        #expect(try store.importWallets(from: source) == 1)

        // The copy is of the recovered source: the old address, which the key belongs to.
        let imported = try #require(try store.load().first)
        #expect(imported.address.value == "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" && imported.publicKey == "edpkALICE")
        #expect(try store.secretKey(for: imported) == "edskALICE")
        // The source itself was rolled back and its journal removed.
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent(TezosClientStore.journalFile).path))
        #expect(try TezosClientStore(directory: source).load().first?.address.value == "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
    }

    @Test func importRecoversBeforeCheckingWhetherTheHashFileExists() throws {
        let source = try tempDir("missing-hashes"), target = try tempDir("target")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        let hashes = Data("[{\"name\":\"alice\",\"value\":\"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb\"}]".utf8)
        let journal = try JSONSerialization.data(withJSONObject: ["version": 1, "files": [TezosClientStore.publicKeyHashesFile: hashes.base64EncodedString()]])
        try PrivateFile.write(journal, to: source.appendingPathComponent(TezosClientStore.journalFile))
        #expect(!TezosClientStore(directory: source).hasWallets)
        let destination = TezosClientStore(directory: target)
        #expect(try destination.importWallets(from: source) == 1)
        #expect(try destination.load().map(\.alias) == ["alice"])
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent(TezosClientStore.journalFile).path))
    }

    @Test func importFiltersRejectedAliasesEvenWhenTargetKeyFilesAreMissing() throws {
        let source = try tempDir("source"), target = try tempDir("contracts-only")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        let from = TezosClientStore(directory: source), to = TezosClientStore(directory: target)
        try from.add(Wallet(alias: "reserved", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkRejected", keyKind: .unencrypted), secretKey: "edskRejected")
        try from.add(Wallet(alias: "accepted", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkAccepted", keyKind: .unencrypted), secretKey: "spskAccepted")
        try to.addContract(MultisigContract(alias: "reserved", address: Address("KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton")))
        #expect(try to.importWallets(from: source) == 1)
        #expect(try to.load().first { $0.alias == "reserved" }?.address.isContract == true)
        #expect(try to.load().filter { !$0.address.isContract }.map(\.alias) == ["accepted"])
        for file in TezosClientStore.walletFiles {
            let data = try #require(try PrivateFile.read(target.appendingPathComponent(file)))
            #expect(!String(decoding: data, as: UTF8.self).contains("reserved"))
        }
    }

    @Test func importRefusesTheDirectoryItself() throws {
        let dir = try tempDir("self")
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: "me", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkME", keyKind: .unencrypted), secretKey: "edskME")
        let viaSymlink = try tempDir("links").appendingPathComponent("wallet")
        try FileManager.default.createSymbolicLink(at: viaSymlink, withDestinationURL: dir)
        #expect(throws: TezosClientStore.StoreError.self) { try store.importWallets(from: dir) }
        #expect(throws: TezosClientStore.StoreError.self) { try store.importWallets(from: viaSymlink) }
        #expect(try store.load().count == 1)
    }

    @Test func importWaitsForAWriterHoldingTheSourceLock() throws {
        let source = try tempDir("source")
        try """
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" } ]
        """.write(to: source.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        let target = try tempDir("target")
        let store = TezosClientStore(directory: target)
        let holding = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let writer = Thread {
            _ = try? TezosClientStore.withWalletLock(in: source) {
                holding.signal()
                _ = release.wait(timeout: .now() + 3)
            }
        }
        writer.start()
        #expect(holding.wait(timeout: .now() + 2) == .success)
        let started = Date()
        let finished = DispatchSemaphore(value: 0)
        let reader = Thread {
            _ = try? store.importWallets(from: source)
            finished.signal()
        }
        reader.start()
        #expect(finished.wait(timeout: .now() + 0.3) == .timedOut)   // blocked on the source lock
        release.signal()
        #expect(finished.wait(timeout: .now() + 3) == .success)
        #expect(Date().timeIntervalSince(started) >= 0.3)
        #expect(try store.load().map(\.alias) == ["alice"])
    }

    @Test func oppositeImportsDoNotDeadlock() throws {
        let a = try tempDir("a"), b = try tempDir("b")
        try TezosClientStore(directory: a).add(Wallet(alias: "fromA", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        try TezosClientStore(directory: b).add(Wallet(alias: "fromB", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkB", keyKind: .unencrypted), secretKey: "spskB")
        let done = DispatchGroup()
        for (from, to) in [(a, b), (b, a)] {
            done.enter()
            Thread {
                for _ in 0..<20 { _ = try? TezosClientStore(directory: to).importWallets(from: from) }
                done.leave()
            }.start()
        }
        #expect(done.wait(timeout: .now() + 10) == .success)
        #expect(Set(try TezosClientStore(directory: a).load().map(\.alias)) == ["fromA", "fromB"])
        #expect(Set(try TezosClientStore(directory: b).load().map(\.alias)) == ["fromA", "fromB"])
    }
}

// MARK: - S11: every log sink gets the redacted line

struct LoggingPolicyTests {
    @Test func consoleLinesFromJavaScriptAreRedactedAndCapped() async throws {
        let key = "edskRuR3azSfg5xTz6dLovR7yr7hgP9Qt6Ub8rgqJG7VTH6RhJ1vXXhfSwtxw1E2Lc3b3TvsgrnWXKVyLRQgm3Rx8cFXqQhd3"
        let hex = String(repeating: "ab", count: 64)
        let filler = String(repeating: "x", count: TaquitoBridge.maxLineLength + 200)
        _ = try await TaquitoBridge.shared.call("bridgeEcho", ["\(key) \(hex) \(filler)"])
        let lines = TaquitoBridge.shared.consoleLines
        let echoed = try #require(lines.last { $0.hasPrefix("[log] echo: ") })
        #expect(!echoed.contains(key) && !echoed.contains(hex))
        #expect(echoed.contains("edsk<redacted>") && echoed.contains("<128 hex chars>"))
        #expect(echoed.count <= TaquitoBridge.maxLineLength + 1)
    }

    @Test func bridgeNotesGoThroughTheSamePolicy() {
        let bridge = TaquitoBridge()
        let key = "edskRuR3azSfg5xTz6dLovR7yr7hgP9Qt6Ub8rgqJG7VTH6RhJ1vXXhfSwtxw1E2Lc3b3TvsgrnWXKVyLRQgm3Rx8cFXqQhd3"
        bridge.note("uncaught: \(key)")
        let line = bridge.consoleLines.last ?? ""
        #expect(line == "[app] uncaught: edsk<redacted>")
    }

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        var lines: [String] { lock.withLock { recorded } }
        func append(_ line: String) { lock.withLock { recorded.append(line) } }
    }

    @Test func systemConsoleAndFileReceiveTheSameRedactedText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bridge.log"), sink = Sink()
        let bridge = TaquitoBridge(logURL: file, systemLog: { sink.append($0) })
        let input = "edsk" + String(repeating: "R", count: 50) + " " + String(repeating: "ab", count: 64) + " " + String(repeating: "x", count: 1200)
        _ = try await bridge.call("bridgeEcho", [input])
        let console = bridge.consoleLines
        #expect(sink.lines == console)
        let data = try #require(try PrivateFile.read(file))
        let text = String(decoding: data, as: UTF8.self)
        for line in console {
            #expect(!line.contains(String(repeating: "R", count: 50)))
            #expect(!line.contains(String(repeating: "ab", count: 64)))
            #expect(line.count <= TaquitoBridge.maxLineLength + 1)
            #expect(text.contains(line))
        }
    }
}

// MARK: - S19: native HTTP readers are bounded while streaming

/// Serves canned replies for `bounded.invalid`: the path picks the body shape.
private final class BoundedHTTPProtocol: URLProtocol, @unchecked Sendable {
    private final class Stops: @unchecked Sendable {
        let lock = NSLock()
        var urls: Set<String> = []
        func add(_ value: String) { lock.withLock { _ = urls.insert(value) } }
        func contains(_ value: String) -> Bool { lock.withLock { urls.contains(value) } }
    }
    private static let stops = Stops()
    static func wasStopped(_ request: URLRequest) -> Bool { stops.contains(request.url!.absoluteString) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "bounded.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let client else { return }
        func respond(_ body: Data, declared: Bool, chunk: Int = 64 << 10, status: Int = 200) {
            var headers = ["Content-Type": "application/json"]
            if declared { headers["Content-Length"] = String(body.count) }
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            var offset = 0
            while offset < body.count {
                let end = min(offset + chunk, body.count)
                client.urlProtocol(self, didLoad: body[offset..<end])
                offset = end
            }
            client.urlProtocolDidFinishLoading(self)
        }
        switch url.pathComponents.dropFirst().first.map({ "/" + $0 }) ?? "/" {
        case "/pending-large":
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "1048576"])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(repeating: 0x20, count: 64 << 10))
        case "/pending-chunked":
            client.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(repeating: 0x20, count: 64 << 10))
        case "/declared-large": respond(Data(repeating: 0x20, count: 1 << 20), declared: true)
        case "/chunked-large": respond(Data(repeating: 0x20, count: 1 << 20), declared: false)
        case "/deep": respond(Data((String(repeating: "[", count: 500) + String(repeating: "]", count: 500)).utf8), declared: true)
        case "/small": respond(Data("\"NetXdQprcVkpaWU\"".utf8), declared: true)
        case "/rows": respond(Data("[\(Array(repeating: "{\"type\":\"transaction\",\"hash\":\"oo1\",\"sender\":{\"address\":\"tz1a\"},\"target\":{\"address\":\"tz1b\"},\"amount\":1,\"timestamp\":\"2026-01-01T00:00:00Z\",\"status\":\"applied\"}", count: 40).joined(separator: ","))]".utf8), declared: true)
        default: respond(Data("{}".utf8), declared: true, status: 404)
        }
    }
    override func stopLoading() { Self.stops.add(request.url!.absoluteString) }
}

struct BoundedHTTPTests {
    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BoundedHTTPProtocol.self]
        return URLSession(configuration: config)
    }
    private func request(_ path: String) -> URLRequest { URLRequest(url: URL(string: "https://bounded.invalid\(path)")!) }

    @Test func declaredAndUndeclaredOversizeRepliesAreRefused() async throws {
        await #expect(throws: BoundedHTTP.Failure.tooLarge(limit: 4096)) { _ = try await BoundedHTTP.data(for: request("/declared-large"), session: session, limit: 4096) }
        await #expect(throws: BoundedHTTP.Failure.tooLarge(limit: 4096)) { _ = try await BoundedHTTP.data(for: request("/chunked-large"), session: session, limit: 4096) }
    }

    @Test func excessiveNestingIsRefusedBeforeParsing() async throws {
        await #expect(throws: BoundedHTTP.Failure.overBudget) { _ = try await BoundedHTTP.data(for: request("/deep"), session: session, limit: 4096, json: .small) }
        let raw = try await BoundedHTTP.data(for: request("/deep"), session: session, limit: 4096, json: nil)
        #expect(raw.data.count == 1000)
    }

    @Test func fittingRepliesPassWithTheirStatus() async throws {
        let reply = try await BoundedHTTP.data(for: request("/small"), session: session, limit: 4096)
        #expect(reply.isSuccess && String(decoding: reply.data, as: UTF8.self) == "\"NetXdQprcVkpaWU\"")
        let missing = try await BoundedHTTP.data(for: request("/nothing"), session: session, limit: 4096)
        #expect(missing.status == 404 && !missing.isSuccess)
    }

    @Test func refusalCancelsTheUnderlyingUnfinishedResponse() async throws {
        for path in ["/pending-large", "/pending-chunked"] {
            var request = request(path + "?id=" + UUID().uuidString)
            request.timeoutInterval = 3
            await #expect(throws: BoundedHTTP.Failure.tooLarge(limit: 4096)) {
                _ = try await BoundedHTTP.data(for: request, session: session, limit: 4096)
            }
            for _ in 0..<50 where !BoundedHTTPProtocol.wasStopped(request) { try await Task.sleep(for: .milliseconds(10)) }
            #expect(BoundedHTTPProtocol.wasStopped(request), "An over-budget response must stop even before the server finishes")
        }
    }

    @Test func nativeReadersUseTheBoundedPath() async throws {
        let base = URL(string: "https://bounded.invalid/declared-large")!
        // TzKT: an account record over its cap fails before anything is parsed.
        await #expect(throws: BoundedHTTP.Failure.tooLarge(limit: TzKTService.recordBytes)) {
            _ = try await TzKTService(baseURL: base, session: session).accountProfile(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        }
        // The node monitor's probe (on the shared session) refuses a block header that is anything but small.
        URLProtocol.registerClass(BoundedHTTPProtocol.self)
        defer { URLProtocol.unregisterClass(BoundedHTTPProtocol.self) }
        await #expect(throws: BoundedHTTP.Failure.self) { _ = try await NodeMonitor.urlSessionProbe(base) }
        // Rows beyond the requested page size are dropped even when the server sends more.
        let rowsBase = URL(string: "https://bounded.invalid/rows")!
        let rows = try await TzKTService(baseURL: rowsBase, session: session).recentOperations(for: Address("tz1a"), limit: 10)
        #expect(rows.count == 10)
    }
}

// MARK: - S30: every export that signs is declared as such

struct SigningExportsTests {
    /// The bridge sources, found from this file's location in the repository.
    private var sources: [URL] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dir = repo.appendingPathComponent("TaquitoBridge/src")
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "js" }
    }

    /// Every top-level `export function` in a file, with its body (up to the closing brace in column 0).
    private func exportedFunctions(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?
        var body: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let current_ = current {
                body.append(line)
                if line == "}" { result[current_] = body.joined(separator: "\n"); current = nil; body = [] }
                continue
            }
            if let range = line.range(of: #"^export (async )?function (\w+)\("#, options: .regularExpression) {
                current = String(line[range].split(separator: " ").last!.dropLast())
                body = [line]
            }
        }
        return result
    }

    /// The names Swift can call: index.js's own functions, its re-exports and everything from `export *`.
    private func publicSurface() throws -> [String: String] {
        let byFile = try Dictionary(uniqueKeysWithValues: sources.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) })
        let index = try #require(byFile["index.js"])
        var surface = exportedFunctions(in: index)
        let star = try NSRegularExpression(pattern: #"export \* from "\./([\w-]+\.js)""#)
        for match in star.matches(in: index, range: NSRange(index.startIndex..., in: index)) {
            let file = String(index[Range(match.range(at: 1), in: index)!])
            surface.merge(exportedFunctions(in: byFile[file] ?? "")) { a, _ in a }
        }
        let named = try NSRegularExpression(pattern: #"export \{([^}]*)\} from "\./([\w-]+\.js)""#, options: [.dotMatchesLineSeparators])
        for match in named.matches(in: index, range: NSRange(index.startIndex..., in: index)) {
            let names = index[Range(match.range(at: 1), in: index)!].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let functions = exportedFunctions(in: byFile[String(index[Range(match.range(at: 2), in: index)!])] ?? "")
            for name in names { if let body = functions[name] { surface[name] = body } }
        }
        return surface
    }

    /// Public functions whose body reaches a signer, local signing and injection, or a Ledger device.
    private func signingExports() throws -> Set<String> {
        let markers = ["signerFor(", "injectSigned(", "signAndInject(", "sendApproved(", "new LedgerSigner(", "ledgerSignerFor("]
        return Set(try publicSurface().filter { name, body in !name.hasSuffix("ForTest") && markers.contains { body.contains($0) } }.keys)
    }

    @Test func everyExportThatSignsIsProtected() throws {
        let exports = try signingExports()
        try #require(!exports.isEmpty, "the bridge sources were not found")
        let unprotected = exports.subtracting(TaquitoBridge.signingCalls)
        #expect(unprotected.isEmpty, "exports that sign or inject without protection: \(unprotected.sorted())")
        for name in ["sendEtherlinkDeposit", "injectSignedBytes", "sendTransfer", "octezConnectExecute", "ledgerGetAddress"] {
            #expect(TaquitoBridge.kind(of: name) == .signing)
        }
        #expect(TaquitoBridge.kind(of: "estimateEtherlinkDeposit") == .read && TaquitoBridge.kind(of: "getHead") == .read)
    }

    @Test func theSigningEntryPointRefusesReads() async throws {
        await #expect(throws: TaquitoBridge.BridgeError.self) { _ = try await TaquitoBridge.shared.sign("version") }
        #expect(try await TaquitoBridge.shared.call("version").stringValue != nil)
    }
}

@MainActor
struct RememberKeyTests {
    static let paper = KeyMaterial(scheme: .tz1, publicKey: "edpkuPAPER", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", secretKey: "edeskPAPER")

    @Test func rememberMovesASessionKeyIntoTheDirectory() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        #expect(!model.canRememberSelectedKey)
        try await model.importAccount(alias: "Paper", material: Self.paper, alreadyEncrypted: true, keepForSession: true)
        #expect(model.canRememberSelectedKey && model.selectedWallet?.isSessionOnly == true)
        #expect(try store.load().isEmpty)

        try await model.rememberSelectedWallet()

        let kept = try #require(model.selectedWallet)
        #expect(kept.alias == "Paper" && !kept.isSessionOnly && kept.keyKind == .encrypted)
        #expect(!model.canRememberSelectedKey && model.sessionWallets.isEmpty)
        #expect(try store.load().map(\.alias) == ["Paper"])
        #expect(try store.secretKey(for: kept) == Self.paper.secretKey)
        // Asked again, there is nothing session-only to remember.
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.rememberSelectedWallet() }
    }

    @Test func rememberCanEncryptAClearKeyOnTheWay() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        let material = try await KeyGenerator().generate(scheme: .tz1)
        try await model.importAccount(alias: "Clear", material: material, keepForSession: true)
        await #expect(throws: WalletViewModel.WalletError.passphraseTooShort) { try await model.rememberSelectedWallet(storePassphrase: "short") }
        #expect(model.selectedWallet?.isSessionOnly == true)

        try await model.rememberSelectedWallet(storePassphrase: "correct horse battery")
        let kept = try #require(model.selectedWallet)
        #expect(kept.keyKind == .encrypted && !kept.isSessionOnly)
        let stored = try #require(try store.secretKey(for: kept))
        #expect(stored.hasPrefix("edesk"))
        #expect(try await BridgeKeyImporter().decrypt(secretKey: stored, passphrase: "correct horse battery") == material.secretKey)
    }

    @Test func rememberRefusesAnAliasOrAddressAlreadyStoredAndKeepsTheKey() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.importAccount(alias: "Paper", material: Self.paper, alreadyEncrypted: true, keepForSession: true)
        let session = try #require(model.selectedWallet)
        // The same address lands in the directory under another name behind the model's back.
        try store.add(Wallet(alias: "Disk", address: session.address, scheme: .tz1, publicKey: "edpkuPAPER", keyKind: .encrypted), secretKey: "edeskPAPER")

        await #expect(throws: WalletViewModel.WalletError.self) { try await model.rememberSelectedWallet() }
        #expect(model.sessionWallets.map(\.alias) == ["Paper"])
        guard case .secret(let secret, _, _)? = try model.signingKey(for: session, passphrase: "x") else {
            Issue.record("the session key was lost"); return
        }
        #expect(secret == Self.paper.secretKey)
    }
}
