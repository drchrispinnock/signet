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

/// A bounded reading of the bridge sources (F18): every top-level function, arrow constant and
/// alias in every file, what each one references, and which of them reach a signing root. Forms
/// it does not understand are refused rather than skipped, so a new way of writing an export
/// cannot slip past the guard.
struct BridgeSignatureScan {
    struct Unsupported: Error, CustomStringConvertible { let description: String }

    /// Functions reaching one of these, by name wherever it is defined, sign, inject or hold a
    /// Ledger session; so does any function that constructs a `LedgerSigner` itself.
    static let roots: Set<String> = ["signerFor", "injectSigned", "signAndInject", "sendApproved", "ledgerSignerFor"]

    /// A top-level definition: its stripped body (strings blanked, comments gone) and whether the file exports it.
    struct Definition { var body: String; var exported: Bool; var callable: Bool }
    struct Node: Hashable { let file: String; let name: String }

    private(set) var definitions: [String: [String: Definition]] = [:]       // file → name → definition
    private(set) var aliases: [Node: Node] = [:]                              // `export const b = a;`, `import { a as b }`
    /// Public name → the definition behind it, for index.js's surface.
    private(set) var surface: [String: Node] = [:]

    init(files: [String: String]) throws {
        for (file, text) in files { try read(file: file, text: Self.stripped(text)) }
        try buildSurface(files: files)
    }

    /// Public names whose definition reaches a root.
    var signingExports: Set<String> {
        var signing = Set<Node>()
        for (file, defs) in definitions {
            for (name, def) in defs where Self.roots.contains(name) || def.body.contains("new LedgerSigner(") { signing.insert(Node(file: file, name: name)) }
        }
        var grew = true
        while grew {
            grew = false
            for (file, defs) in definitions {
                for (name, def) in defs {
                    let node = Node(file: file, name: name)
                    guard !signing.contains(node) else { continue }
                    if references(in: def.body, from: file).contains(where: { signing.contains(resolve($0)) }) { signing.insert(node); grew = true }
                }
            }
            for (alias, target) in aliases where !signing.contains(alias) && signing.contains(resolve(target)) { signing.insert(alias); grew = true }
        }
        return Set(surface.filter { signing.contains(resolve($0.value)) }.keys)
    }

    private func resolve(_ node: Node) -> Node {
        var current = node
        var seen = Set<Node>()
        while let next = aliases[current], seen.insert(current).inserted { current = next }
        return current
    }

    /// Identifiers in `body` that name a top-level definition or import of `file`.
    private func references(in body: String, from file: String) -> [Node] {
        let known = Set((definitions[file] ?? [:]).keys).union(aliases.keys.filter { $0.file == file }.map(\.name))
        var found: [Node] = []
        let pattern = try! NSRegularExpression(pattern: #"(?<![.\w$])([A-Za-z_$][\w$]*)"#)
        for match in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            let name = String(body[Range(match.range(at: 1), in: body)!])
            if known.contains(name) { found.append(Node(file: file, name: name)) }
        }
        return found
    }

    // MARK: Reading one file

    private mutating func read(file: String, text: String) throws {
        var defs: [String: Definition] = [:]
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var index = 0
        var lineStarts: [Int] = []
        for line in lines { lineStarts.append(offset); offset += line.utf16.count + 1 }
        let function = try! NSRegularExpression(pattern: #"^(export\s+)?(async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\("#)
        let arrow = try! NSRegularExpression(pattern: #"^(export\s+)?const\s+([A-Za-z_$][\w$]*)\s*=\s*(async\s*)?(\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*"#)
        let alias = try! NSRegularExpression(pattern: #"^(export\s+)?const\s+([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)\s*;"#)
        let value = try! NSRegularExpression(pattern: #"^(export\s+)?(const|let|var)\s+([A-Za-z_$][\w$]*)\s*="#)
        let imported = try! NSRegularExpression(pattern: #"^import\s+\{([^}]*)\}\s+from\s+"\./([\w-]+\.js)"\s*;"#)
        while index < lines.count {
            let line = lines[index]
            let range = NSRange(line.startIndex..., in: line)
            if line.hasPrefix("export default") { throw Unsupported(description: "\(file):\(index + 1): default exports are not supported") }
            if let m = function.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 3), in: line)!])
                let (body, last) = try Self.block(from: lineStarts[index] + m.range.length, in: text, lines: lines, lineStarts: lineStarts, file: file, line: index)
                defs[name] = Definition(body: body, exported: m.range(at: 1).location != NSNotFound, callable: true)
                index = last + 1
                continue
            }
            if let m = arrow.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 2), in: line)!])
                let after = lineStarts[index] + m.range.length
                let rest = String(text.utf16.dropFirst(after).prefix(1)) ?? ""
                let (body, last) = rest == "{"
                    ? try Self.block(from: after, in: text, lines: lines, lineStarts: lineStarts, file: file, line: index)
                    : (String(line[line.index(line.startIndex, offsetBy: m.range.length)...]), index)
                defs[name] = Definition(body: body, exported: m.range(at: 1).location != NSNotFound, callable: true)
                index = last + 1
                continue
            }
            if let m = alias.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 2), in: line)!]), target = String(line[Range(m.range(at: 3), in: line)!])
                aliases[Node(file: file, name: name)] = Node(file: file, name: target)
                if m.range(at: 1).location != NSNotFound { defs[name] = Definition(body: target, exported: true, callable: true) }
                index += 1
                continue
            }
            if let m = value.firstMatch(in: line, range: range) {
                // A plain value (a string, a number, a frozen object): recorded so a body that
                // mentions a signing function is still caught, but not callable from Swift.
                let name = String(line[Range(m.range(at: 3), in: line)!])
                let (body, last) = line.contains("{") && !line.contains("}")
                    ? try Self.block(from: lineStarts[index] + (line.utf16.firstIndex(of: 123).map { line.utf16.distance(from: line.utf16.startIndex, to: $0) } ?? 0), in: text, lines: lines, lineStarts: lineStarts, file: file, line: index)
                    : (line, index)
                defs[name] = Definition(body: body, exported: m.range(at: 1).location != NSNotFound, callable: false)
                index = last + 1
                continue
            }
            if let m = imported.firstMatch(in: line, range: range) {
                let from = String(line[Range(m.range(at: 2), in: line)!])
                for item in line[Range(m.range(at: 1), in: line)!].split(separator: ",") {
                    let parts = item.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    guard let first = parts.first else { continue }
                    let (local, remote) = parts.count == 3 && parts[1] == "as" ? (parts[2], first) : (first, first)
                    aliases[Node(file: file, name: local)] = Node(file: from, name: remote)
                }
            }
            if line.hasPrefix("export class") { defs[String(line.dropFirst("export class ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })] = Definition(body: "", exported: true, callable: false) }
            index += 1
        }
        definitions[file] = defs
    }

    /// The `{ … }` block starting at the first brace at or after `from` (a UTF-16 offset), with
    /// the index of the line it ends on. Braces are balanced on stripped text, so a string or
    /// comment cannot open or close one.
    private static func block(from: Int, in text: String, lines: [String], lineStarts: [Int], file: String, line: Int) throws -> (String, Int) {
        let utf16 = Array(text.utf16)
        guard var i = utf16[from...].firstIndex(of: 123) else { throw Unsupported(description: "\(file):\(line + 1): no body") }   // {
        let start = i
        var depth = 0
        while i < utf16.count {
            if utf16[i] == 123 { depth += 1 } else if utf16[i] == 125 { depth -= 1; if depth == 0 { break } }
            i += 1
        }
        guard depth == 0 else { throw Unsupported(description: "\(file):\(line + 1): unbalanced braces") }
        let body = String(utf16CodeUnits: Array(utf16[start...i]), count: i - start + 1)
        let endLine = (lineStarts.lastIndex { $0 <= i }) ?? line
        return (body, endLine)
    }

    /// Comments removed and the contents of strings and template literals blanked (code inside
    /// `${…}` is kept, and so is a `./file.js` module path), so what remains is code and the
    /// identifiers in it.
    static func stripped(_ text: String) -> String {
        var out = ""
        var chars = Array(text)
        chars.append(" ")
        enum Mode { case code, template }
        var stack: [Mode] = [.code]
        var depthInTemplate: [Int] = []
        var i = 0
        while i < chars.count - 1 {
            let c = chars[i], n = chars[i + 1]
            switch stack.last! {
            case .code:
                if c == "/" && n == "/" { while i < chars.count - 1 && chars[i] != "\n" { i += 1 }; continue }
                if c == "/" && n == "*" { i += 2; while i < chars.count - 1 && !(chars[i] == "*" && chars[i + 1] == "/") { if chars[i] == "\n" { out.append("\n") }; i += 1 }; i += 2; continue }
                if c == "\"" || c == "'" {
                    // Blanked, except a module path, which import/export resolution needs.
                    out.append(c); i += 1
                    var content = ""
                    while i < chars.count - 1 && chars[i] != c { if chars[i] == "\\" { i += 1 }; content.append(chars[i]); i += 1 }
                    if content.hasPrefix("./"), content.hasSuffix(".js"), !content.contains(where: { $0 == "{" || $0 == "}" || $0 == "\"" }) { out.append(content) }
                    out.append(c); i += 1; continue
                }
                if c == "`" { out.append("`"); stack.append(.template); i += 1; continue }
                if c == "}" && !depthInTemplate.isEmpty && stack.count > 1 {
                    if depthInTemplate[depthInTemplate.count - 1] == 0 { out.append("}"); stack.removeLast(); depthInTemplate.removeLast(); i += 1; continue }
                    depthInTemplate[depthInTemplate.count - 1] -= 1
                }
                if c == "{" && !depthInTemplate.isEmpty && stack.count > 1 { depthInTemplate[depthInTemplate.count - 1] += 1 }
                out.append(c); i += 1
            case .template:
                if c == "\\" { i += 2; continue }
                if c == "`" { out.append("`"); stack.removeLast(); i += 1; continue }
                if c == "$" && n == "{" { out.append("${"); stack.append(.code); depthInTemplate.append(0); i += 2; continue }
                if c == "\n" { out.append("\n") }
                i += 1
            }
        }
        return out
    }

    // MARK: index.js's public surface

    private mutating func buildSurface(files: [String: String]) throws {
        guard let index = files["index.js"] else { throw Unsupported(description: "index.js missing") }
        let text = Self.stripped(index)
        for (name, def) in definitions["index.js"] ?? [:] where def.exported { surface[name] = Node(file: "index.js", name: name) }
        let star = try! NSRegularExpression(pattern: #"^export \* from "\./([\w-]+\.js)";"#, options: .anchorsMatchLines)
        for m in star.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let file = String(text[Range(m.range(at: 1), in: text)!])
            guard let defs = definitions[file] else { throw Unsupported(description: "export * from \(file): file not read") }
            for (name, def) in defs where def.exported { surface[name] = Node(file: file, name: name) }
        }
        let named = try! NSRegularExpression(pattern: #"^export \{([^}]*)\}(?: from "\./([\w-]+\.js)")?;"#, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
        let namedMatches = named.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // Every `export *` / `export {` line must be one of the two forms above, or it is refused.
        let anyList = try! NSRegularExpression(pattern: #"^export [{*]"#, options: .anchorsMatchLines)
        let listed = anyList.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard listed == star.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) + namedMatches.count else {
            throw Unsupported(description: "index.js: an export list in a form this scan does not understand")
        }
        for m in namedMatches {
            let file = m.range(at: 2).location == NSNotFound ? "index.js" : String(text[Range(m.range(at: 2), in: text)!])
            for item in text[Range(m.range(at: 1), in: text)!].split(separator: ",") {
                let parts = item.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
                guard let first = parts.first else { continue }
                let (local, public_) = parts.count == 3 && parts[1] == "as" ? (first, parts[2]) : (first, first)
                let node = Node(file: file, name: local)
                guard definitions[file]?[local] != nil || aliases[node] != nil else { throw Unsupported(description: "export { \(local) } from \(file): not a definition this scan understands") }
                surface[public_] = node
            }
        }
        for (name, node) in surface {
            let def = definitions[node.file]?[node.name] ?? definitions[resolve(node).file]?[resolve(node).name]
            if let def, !def.callable, def.body.isEmpty { throw Unsupported(description: "\(name): a class on the public surface is not supported") }
        }
    }
}

struct SigningExportsTests {
    /// The bridge sources, found from this file's location in the repository.
    private static func sources() throws -> [String: String] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dir = repo.appendingPathComponent("TaquitoBridge/src")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "js" }
        return try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) })
    }

    @Test func everyExportThatSignsIsProtected() throws {
        let scan = try BridgeSignatureScan(files: Self.sources())
        let exports = scan.signingExports
        try #require(!exports.isEmpty, "the bridge sources were not found")
        let unprotected = exports.subtracting(TaquitoBridge.signingCalls)
        #expect(unprotected.isEmpty, "exports that sign or inject without protection: \(unprotected.sorted())")
        // The exact set, so a declaration that no longer signs (or a new signer) is noticed too.
        // ledgerAppVersion is declared for the device lease it holds, not because it signs.
        #expect(exports == TaquitoBridge.signingCalls.subtracting(["ledgerAppVersion"]), "found: \(exports.sorted())")
        for name in ["sendEtherlinkDeposit", "injectSignedBytes", "sendTransfer", "octezConnectExecute", "ledgerGetAddress"] {
            #expect(TaquitoBridge.kind(of: name) == .signing)
        }
        #expect(TaquitoBridge.kind(of: "estimateEtherlinkDeposit") == .read && TaquitoBridge.kind(of: "getHead") == .read)
        // Reads the old scanner could have mistaken: present on the surface and not signing.
        for name in ["estimateTransfer", "octezConnectPrepare", "multisigInfo", "forgeRawForTest", "inspectSecretKey", "ledgerDevices"] {
            #expect(scan.surface[name] != nil && !exports.contains(name), Comment(rawValue: name))
        }
    }

    /// The forms the scanner must see through, on fixtures: direct, single-line, helper-mediated,
    /// aliased, re-exported, starred, `ForTest`, and a read that must stay a read.
    @Test func theScanSeesEveryWayOfWritingASigningExport() throws {
        let files = [
            "index.js": """
            import { helper, viaAlias as sendIt } from "./ops.js";
            import { signerFor } from "./signers.js";
            export * from "./star.js";
            export { ledgerThing as ledgerAlias } from "./ledger.js";
            export { sendIt };
            export const GATEWAY = "KT1 { not a brace } signerFor";
            export async function direct(spec) {
              const s = await signerFor(spec); // signerFor(
              return s;
            }
            export async function oneLine(spec) { return helper(spec); }
            export function afterOneLine(x) {
              return estimate(x) + `${x} injectSigned`;
            }
            export function readOnly(x) { return estimate(x); }
            export function viaForTest(spec) { return helper(spec); }
            export const arrow = async (spec) => {
              return helper(spec);
            };
            export const shortArrow = (spec) => helper(spec);
            export const dotted = (x) => x.signerFor(1);
            function estimate(x) { return "signerFor(" + x; }
            """,
            "ops.js": """
            import { signerFor } from "./signers.js";
            export async function helper(spec) { return signerFor(spec); }
            export const viaAlias = helper;
            """,
            "star.js": """
            export function starSigner(x) { return injectSigned(x); }
            export function starRead() { return 1; }
            function injectSigned(x) { return x; }
            """,
            "ledger.js": "export function ledgerThing(t) { return new LedgerSigner(t); }\nexport const LEDGER_TIMEOUT = 5 * 60;",
            "signers.js": "export async function signerFor(spec) { return spec; }",
        ]
        let scan = try BridgeSignatureScan(files: files)
        #expect(scan.signingExports == ["direct", "oneLine", "viaForTest", "arrow", "shortArrow", "sendIt", "ledgerAlias", "starSigner"])
        #expect(Set(scan.surface.keys).isSuperset(of: ["afterOneLine", "readOnly", "dotted", "starRead", "GATEWAY"]), "a single-line export must not swallow the next one")
        #expect(scan.surface["estimate"] == nil && scan.surface["helper"] == nil, "unexported helpers are not on the surface")
    }

    @Test func theScanRefusesWhatItDoesNotUnderstand() throws {
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["index.js": "export default function (x) { return x; }"]) }
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["index.js": "export function broken(x) {\n  if (x) {\n return 1;\n}"]) }
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["index.js": "export * from \"./missing.js\";"]) }
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["index.js": "export { nothing } from \"./ops.js\";", "ops.js": "export function other() { return 1; }"]) }
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["index.js": "export class Thing {\n  go() { return 1; }\n}"]) }
        #expect(throws: BridgeSignatureScan.Unsupported.self) { try BridgeSignatureScan(files: ["ops.js": "export function a() { return 1; }"]) }
    }

    @Test func theSigningEntryPointRefusesReads() async throws {
        await #expect(throws: TaquitoBridge.BridgeError.self) { _ = try await TaquitoBridge.shared.sign("version") }
        #expect(try await TaquitoBridge.shared.call("version").stringValue != nil)
    }
}

/// F02: every bridge failure goes through one conversion to `ChainError`.
struct BridgeErrorConversionTests {
    @Test func knownMessagesBecomeChainErrorsAndEverythingElsePassesThrough() async throws {
        let cases: [(String, ChainError)] = [
            ("Failed to decrypt the key", .wrongPassphrase), ("Invalid passphrase", .wrongPassphrase),
            ("Ledger device: Condition of use not satisfied (denied by the user?) (0x6985)", .ledgerDeclined),
            ("Ledger Device is busy (0x5515 LOCKED_DEVICE)", .ledgerLocked),
            ("CLA_NOT_SUPPORTED (0x6e00)", .ledgerAppNotOpen), ("INS_NOT_SUPPORTED", .ledgerAppNotOpen),
            ("No Ledger is connected", .ledgerNotConnected), ("the device was unplugged", .ledgerNotConnected),
            ("Ledger does not hold this key", .ledgerWrongDevice("Ledger does not hold this key")),
            ("the key does not derive the account's address tz1x", .keyAddressMismatch("the key does not derive the account's address tz1x")),
        ]
        for (message, expected) in cases {
            let typed = TaquitoBridge.BridgeError.javaScript(message).asChainError
            #expect(typed as? ChainError == expected, Comment(rawValue: message))
            await #expect(throws: expected) { try await TaquitoBridge.BridgeError.typed { throw TaquitoBridge.BridgeError.javaScript(message) } }
        }
        // Precedence is the message scan's: a decrypt failure wins over a Ledger code in the same text.
        #expect(TaquitoBridge.BridgeError.javaScript("could not decrypt (0x6985)").asChainError as? ChainError == .wrongPassphrase)
        // Unknown JavaScript text and every other bridge failure come back exactly as they were.
        for error in [TaquitoBridge.BridgeError.javaScript("something else"), .timedOut("getHead", 60), .notAFunction("x"), .responseTooLarge(1), .bundleMissing, .loadFailed("y"), .notASigningCall("z")] {
            let back = try #require(error.asChainError as? TaquitoBridge.BridgeError)
            #expect(String(describing: back) == String(describing: error))
        }
        // Other errors never enter the conversion, and a success comes back untouched.
        await #expect(throws: ChainError.accountNotOnChain(Address("tz1"))) { try await TaquitoBridge.BridgeError.typed { throw ChainError.accountNotOnChain(Address("tz1")) } }
        #expect(try await TaquitoBridge.BridgeError.typed { 7 } == 7)
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
