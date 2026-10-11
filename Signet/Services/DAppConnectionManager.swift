import Foundation
import Observation

/// Owns the Octez Connect session: starts the SDK in the bridge, surfaces incoming dApp
/// requests one at a time for the UI to approve, and sends the responses.
///
/// The bridge only forwards requests it has rebuilt from authenticated peer state and checked
/// against the stored grants (S04, S08); this side checks the grant again right before signing,
/// keeps a bounded queue (S19), and never treats a reply that failed to reach the dApp as done
/// (S17): the signed outcome is kept and only the reply is retried, so nothing is signed or
/// injected twice.
@MainActor
@Observable
final class DAppConnectionManager {
    enum ConnectError: LocalizedError {
        case notOurWallet(Address)
        case noUsableKey(String)
        case unsupportedNetwork(String)
        case refusedPayload(String)
        case notGranted(String)

        var errorDescription: String? {
            switch self {
            case .notOurWallet(let address): "The dApp asked for \(address.shortened()), which is not one of your accounts."
            case .noUsableKey(let alias): "Signet cannot sign with “\(alias)” (no key on disk or Ledger)."
            case .unsupportedNetwork(let type): "The dApp wants the “\(type)” network, which Signet does not have."
            case .refusedPayload(let why): why
            case .notGranted(let why): why
            }
        }
    }

    /// Where a pairing stands: the dApp has to join the relay room before it can ask anything.
    enum PairingState: Equatable, Sendable {
        case idle
        case waiting(name: String)
        case paired(name: String)
        case failed(String)
    }

    /// The most requests that may wait for the user at once; later ones are refused.
    static let maxPending = 16

    private(set) var isStarted = false
    private(set) var pending: [DAppRequest] = []
    private(set) var permissions: [DAppPermission] = []
    private(set) var lastError: String?
    /// Something to show briefly after a request completes, e.g. "Sent ooABC…".
    private(set) var lastOutcome: String?
    private(set) var pairing: PairingState = .idle
    /// Requests whose work is done (operation injected, message signed, permission chosen) but
    /// whose reply the dApp has not received yet: id → the reply to resend (S17).
    private(set) var undelivered: [String: UndeliveredReply] = [:]

    struct UndeliveredReply: Equatable, Sendable {
        let responseJSON: String
        /// What was done, for the user: an operation hash, "signed", "connected".
        let summary: String
        var attempts: Int
    }

    private let bridge: TaquitoBridge
    private let storage: any BridgeStorage
    private let walletsProvider: @MainActor () -> [Wallet]
    private let signerProvider: @MainActor (Wallet, String?) throws -> SigningKey?
    private var startTask: Task<Void, Never>?
    /// Only when the user turned developer diagnostics on (S11): the SDK logs decrypted traffic.
    let diagnostics: Bool

    var current: DAppRequest? { pending.first }

    init(bridge: TaquitoBridge = .shared,
         storage: any BridgeStorage,
         diagnostics: Bool = false,
         wallets: @escaping @MainActor () -> [Wallet],
         signer: @escaping @MainActor (Wallet, String?) throws -> SigningKey?) {
        self.bridge = bridge
        self.storage = storage
        self.diagnostics = diagnostics
        self.walletsProvider = wallets
        self.signerProvider = signer
    }

    // MARK: Lifecycle

    /// Starts the SDK. Concurrent calls share one attempt (S18).
    func start() async {
        if isStarted { return }
        if let startTask { await startTask.value; return }
        let task = Task { await self.startNow() }
        startTask = task
        await task.value
        startTask = nil
    }

    private func startNow() async {
        bridge.storage = storage
        bridge.eventHandler = { [weak self] json in
            Task { @MainActor in self?.handle(eventJSON: json) }
        }
        do {
            bridge.note("Octez Connect starting")
            _ = try await bridge.call("octezConnectStart", ["Signet", "https://raw.githubusercontent.com/drchrispinnock/signet/main/docs/images/signet-256.png", diagnostics])
            isStarted = true
            lastError = nil
            bridge.note("Octez Connect started")
            await reloadPermissions()
        } catch {
            isStarted = false
            lastError = "Octez Connect failed to start: \(error.localizedDescription)"
            bridge.note("Octez Connect failed to start: \(error.localizedDescription)")
        }
    }

    /// Stops the SDK client and drops every waiting request (each dApp gets an abort). Used when
    /// the wallet directory changes: the next directory gets its own manager and storage (S08).
    func stop() async {
        if let startTask { await startTask.value }
        for request in pending { await respondError(id: request.id, errorType: "ABORTED_ERROR") }
        pending = []
        undelivered = [:]
        _ = try? await bridge.call("octezConnectStop")
        if bridge.storage === storage { bridge.eventHandler = nil }
        isStarted = false
    }

    /// Stops and restarts the SDK client, e.g. after a failed start.
    func restart() async {
        await stop()
        await start()
    }

    /// Pairs with a dApp from its pairing code. Returns the dApp's name; the pairing completes in
    /// the background and `pairing` reports when the dApp has answered (S18).
    @discardableResult
    func pair(code: String) async throws -> String {
        if !isStarted { await start() }
        guard isStarted else { throw ConnectError.refusedPayload(lastError ?? "Octez Connect is not running.") }
        bridge.note("Pairing with a \(code.count)-character code")
        let result = try await bridge.call("octezConnectPair", [code], timeout: 30)
        let name = result["name"]?.stringValue ?? "dApp"
        pairing = .waiting(name: name)
        return name
    }

    func reloadPermissions() async {
        guard let list = try? await bridge.call("octezConnectPermissions", timeout: 30).arrayValue else { return }
        permissions = list.compactMap(Self.permission)
    }

    nonisolated static func permission(_ item: JSONValue) -> DAppPermission? {
        guard let account = item["accountIdentifier"]?.stringValue, let sender = item["senderId"]?.stringValue else { return nil }
        let meta = item["appMetadata"]
        return DAppPermission(
            accountIdentifier: account, senderId: sender,
            address: item["address"]?.stringValue ?? "",
            appName: meta?["name"]?.stringValue ?? "dApp",
            appIcon: meta?["icon"]?.stringValue.flatMap(URL.init(string:)),
            networkType: item["network"]?["type"]?.stringValue ?? "mainnet",
            networkRPCURL: item["network"]?["rpcUrl"]?.stringValue.flatMap(URL.init(string:)),
            scopes: item["scopes"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            connectedAt: item["connectedAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// Revokes a grant. Requests that grant covered are refused too, so revocation takes effect
    /// on what is already queued (S08).
    func disconnect(_ permission: DAppPermission) async {
        _ = try? await bridge.call("octezConnectRemovePermission", [permission.accountIdentifier, permission.senderId], timeout: 30)
        await reloadPermissions()
        await rejectPending { $0.app.senderId == permission.senderId && !$0.isPermission }
    }

    func disconnectAll() async {
        _ = try? await bridge.call("octezConnectRemoveAll", timeout: 30)
        await reloadPermissions()
        await rejectPending { _ in true }
    }

    private func rejectPending(_ matches: (DAppRequest) -> Bool) async {
        let doomed = pending.filter(matches)
        for request in doomed {
            await respondError(id: request.id, errorType: "NOT_GRANTED_ERROR")
            finish(request)
        }
    }

    // MARK: Incoming

    private func handle(eventJSON: String) {
        guard let data = eventJSON.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = event["kind"] as? String else { return }
        // Only the shape is logged: request contents are the dApp's business (S11).
        bridge.note("dApp event \(kind) \((event["message"] as? [String: Any])?["type"] as? String ?? "")")
        switch kind {
        case "error":
            lastError = event["message"] as? String
            if case .waiting = pairing { pairing = .failed(lastError ?? "Pairing failed") }
            return
        case "paired":
            pairing = .paired(name: event["name"] as? String ?? "dApp")
            lastOutcome = "Paired with \(event["name"] as? String ?? "the dApp")"
            return
        case "refused":
            lastError = "Refused a request from a dApp: \(event["reason"] as? String ?? "not allowed")"
            return
        case "request":
            break
        default:
            return
        }
        guard let request = DAppRequest.parse(eventJSON: eventJSON) else { return }
        if case .unsupported(let id, _, let type) = request {
            Task { await respondError(id: id, errorType: "NOT_GRANTED_ERROR"); lastError = "Unsupported dApp request: \(type)" }
            return
        }
        if let why = request.signRefusal {
            Task { await respondError(id: request.id, errorType: "SIGNATURE_TYPE_NOT_SUPPORTED"); lastError = "Refused a signing request from “\(request.app.name)”: \(why)" }
            return
        }
        guard pending.count < Self.maxPending else {
            Task { await respondError(id: request.id, errorType: "ABORTED_ERROR"); lastError = "Too many dApp requests are waiting; “\(request.app.name)” was refused." }
            return
        }
        guard !pending.contains(where: { $0.id == request.id }) else { return }
        pending.append(request)
        Task { await reloadPermissions() }
    }

    private func finish(_ request: DAppRequest) {
        pending.removeAll { $0.id == request.id }
        undelivered[request.id] = nil
    }

    // MARK: Grants (S08)

    /// The grant that covers this request right now, read fresh from the SDK, or why there is none.
    func grant(for request: DAppRequest) async throws -> DAppPermission {
        await reloadPermissions()
        return try Self.grant(for: request, in: permissions)
    }

    nonisolated static func grant(for request: DAppRequest, in permissions: [DAppPermission]) throws -> DAppPermission {
        let source: Address, scope: String
        var network: (type: String, rpcURL: URL?)?
        switch request {
        case .operation(_, _, let networkType, let rpcURL, let address, _):
            source = address; scope = "operation_request"; network = (networkType, rpcURL)
        case .signPayload(_, _, let address, _, _):
            source = address; scope = "sign"
        default:
            throw ConnectError.refusedPayload("not a request that needs a grant")
        }
        guard !request.app.senderId.isEmpty else { throw ConnectError.notGranted("The request carries no authenticated sender.") }
        let candidates = permissions.filter { $0.senderId == request.app.senderId && $0.address == source.value && $0.scopes.contains(scope) }
        guard !candidates.isEmpty else {
            throw ConnectError.notGranted("“\(request.app.name)” has no permission to \(scope == "sign" ? "sign messages" : "request operations") for \(source.shortened()). Connect it again first.")
        }
        if let network {
            guard let match = candidates.first(where: { $0.networkType == network.type && ($0.networkType != "custom" || DAppRequest.sameEndpoint($0.networkRPCURL, network.rpcURL)) }) else {
                throw ConnectError.notGranted("“\(request.app.name)” is connected on \(candidates[0].networkType), not \(network.type).")
            }
            return match
        }
        return candidates[0]
    }

    // MARK: Answers

    func approvePermission(_ request: DAppRequest, with wallet: Wallet) async {
        guard case .permission(let id, _, let networkType, let rpcURL, let scopes) = request else { return }
        if let reply = undelivered[id] { await redeliver(request, reply); return }
        guard let publicKey = wallet.publicKey else {
            lastError = "“\(wallet.alias)” has no public key, so it cannot be shared with a dApp."
            await respondError(id: id, errorType: "NOT_GRANTED_ERROR")
            finish(request)
            return
        }
        var network: [String: Any] = ["type": networkType]
        if let rpcURL { network["rpcUrl"] = rpcURL.absoluteString }
        let granted = scopes.filter { ["sign", "operation_request"].contains($0) }
        let response: [String: Any] = [
            "type": "permission_response", "id": id,
            "network": network, "scopes": granted,
            "publicKey": publicKey, "address": wallet.address.value,
            "walletType": "implicit",
        ]
        await deliver(request, response, summary: "Connected “\(request.app.name)” to \(wallet.alias)")
        await reloadPermissions()
    }

    /// Simulates the request's batch from its source account so the sheet can show exact fees,
    /// burn, totals and effects. Nothing is signed; a read-only signer stands in for the account.
    func prepare(_ request: DAppRequest) async throws -> DAppPreparedBatch {
        guard case .operation(let id, _, let networkType, let rpcURL, let source, let operationsJSON) = request else { throw ConnectError.refusedPayload("not an operation request") }
        _ = try Self.grant(for: request, in: permissions)
        guard let wallet = wallet(for: source) else { throw ConnectError.notOurWallet(source) }
        guard let publicKey = wallet.publicKey else { throw ConnectError.noUsableKey(wallet.alias) }
        guard let network = DAppRequest.network(forType: networkType, rpcURL: rpcURL) else { throw ConnectError.unsupportedNetwork(networkType) }
        let r = try await bridge.call("octezConnectPrepare", [network.rpcURL.absoluteString, source.value, publicKey, operationsJSON, network.expectedChainID ?? NSNull()], timeout: 120)
        guard let prepared = r["prepared"]?.stringValue, let list = r["operations"]?.arrayValue else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected prepare payload: \(String(describing: r))")
        }
        return DAppPreparedBatch(
            requestID: id,
            operations: list.map(Self.summary),
            revealFee: Mutez.toTez(r["reveal"]?["feeMutez"]?.stringValue),
            revealBurn: Mutez.toTez(r["reveal"]?["burnMutez"]?.stringValue),
            totalAmount: Mutez.toTez(r["totalAmountMutez"]?.stringValue) ?? 0,
            totalFee: Mutez.toTez(r["totalFeeMutez"]?.stringValue) ?? 0,
            totalBurn: Mutez.toTez(r["totalBurnMutez"]?.stringValue) ?? 0,
            totalDebit: Mutez.toTez(r["totalDebitMutez"]?.stringValue) ?? 0,
            preparedJSON: prepared
        )
    }

    /// Signs and sends the batch exactly as it was prepared and shown (`prepared` must be for this request).
    func approveOperation(_ request: DAppRequest, prepared: DAppPreparedBatch, passphrase: String?) async {
        guard case .operation(let id, _, let networkType, let rpcURL, let source, _) = request else { return }
        if let reply = undelivered[id] { await redeliver(request, reply); return }
        do {
            guard prepared.requestID == id else { throw ConnectError.refusedPayload("The prepared batch is not for this request.") }
            _ = try await grant(for: request)
            let (wallet, signer) = try signer(for: source, passphrase: passphrase)
            guard let network = DAppRequest.network(forType: networkType, rpcURL: rpcURL) else { throw ConnectError.unsupportedNetwork(networkType) }
            let result = try await bridge.call("octezConnectExecute", [network.rpcURL.absoluteString, signer.bridgeSpec, prepared.preparedJSON, network.expectedChainID ?? NSNull()])
            guard let hash = result["hash"]?.stringValue, !hash.isEmpty else { throw TaquitoBridge.BridgeError.javaScript("no operation hash") }
            let injected = result["injected"]?.boolValue ?? true
            let summary = injected ? "Sent \(hash.prefix(12))… for “\(request.app.name)” from \(wallet.alias)"
                : "Signed \(hash.prefix(12))… for “\(request.app.name)”; the node's answer was lost, so check the explorer before retrying"
            await deliver(request, ["type": "operation_response", "id": id, "transactionHash": hash], summary: summary)
        } catch {
            lastError = Self.friendly(error)
            // Wrong password or Ledger not ready: leave the request up so the user can retry.
            if Self.isRetryable(error) { return }
            await respondError(id: id, errorType: error is ConnectError ? "NOT_GRANTED_ERROR" : "TRANSACTION_INVALID_ERROR")
            finish(request)
        }
    }

    func approveSignature(_ request: DAppRequest, passphrase: String?) async {
        guard case .signPayload(let id, _, let source, let signingType, let payload) = request else { return }
        if let reply = undelivered[id] { await redeliver(request, reply); return }
        do {
            if let why = request.signRefusal { throw ConnectError.refusedPayload(why) }
            _ = try await grant(for: request)
            let (_, signer) = try signer(for: source, passphrase: passphrase)
            let result = try await bridge.call("octezConnectSign", [signer.bridgeSpec, payload, signingType])
            guard let signature = result["signature"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no signature") }
            await deliver(request, ["type": "sign_payload_response", "id": id, "signingType": signingType, "signature": signature],
                          summary: "Signed a message for “\(request.app.name)”")
        } catch {
            lastError = Self.friendly(error)
            if Self.isRetryable(error) { return }
            await respondError(id: id, errorType: error is ConnectError ? "NOT_GRANTED_ERROR" : "SIGNATURE_TYPE_NOT_SUPPORTED")
            finish(request)
        }
    }

    func reject(_ request: DAppRequest) async {
        if undelivered[request.id] != nil {
            // The work was done; the user gives up on telling the dApp. Nothing is undone.
            finish(request)
            return
        }
        await respondError(id: request.id, errorType: request.isPermission ? "NOT_GRANTED_ERROR" : "ABORTED_ERROR")
        finish(request)
    }

    /// Sends the reply the request's work produced again (S17). Never signs or injects anything.
    func resendReply(_ request: DAppRequest) async {
        guard let reply = undelivered[request.id] else { return }
        await redeliver(request, reply)
    }

    func clearMessages() {
        lastError = nil
        lastOutcome = nil
        if case .paired = pairing { pairing = .idle }
        if case .failed = pairing { pairing = .idle }
    }

    // MARK: Delivery (S17)

    /// Sends a completed request's reply. On failure the reply is kept with the request so it can
    /// be resent; the request stays in the queue, marked undelivered, and is never redone.
    private func deliver(_ request: DAppRequest, _ message: [String: Any], summary: String) async {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let json = String(data: data, encoding: .utf8) else { return }
        let reply = UndeliveredReply(responseJSON: json, summary: summary, attempts: 0)
        await redeliver(request, reply)
    }

    private func redeliver(_ request: DAppRequest, _ reply: UndeliveredReply) async {
        do {
            _ = try await bridge.call("octezConnectRespond", [reply.responseJSON], timeout: 60)
            lastOutcome = reply.summary
            finish(request)
        } catch {
            var kept = reply
            kept.attempts += 1
            undelivered[request.id] = kept
            lastError = "\(reply.summary). The dApp did not get the reply (\(error.localizedDescription)); you can send it again without redoing anything."
            bridge.note("reply to \(request.id) not delivered: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    /// The wallet for `source` and what signs for it.
    private func signer(for source: Address, passphrase: String?) throws -> (Wallet, SigningKey) {
        guard let wallet = walletsProvider().first(where: { $0.address == source }) else { throw ConnectError.notOurWallet(source) }
        guard wallet.keyKind.canSign, let signer = try signerProvider(wallet, passphrase) else { throw ConnectError.noUsableKey(wallet.alias) }
        return (wallet, signer)
    }

    func wallet(for source: Address) -> Wallet? {
        walletsProvider().first { $0.address == source }
    }

    /// What the batch does, without the node (no fees yet). Shown while `prepare` runs.
    func summaries(for operationsJSON: String) async -> [DAppOperationSummary] {
        guard let list = try? await bridge.call("octezConnectDescribe", [operationsJSON], timeout: 30).arrayValue else { return [] }
        return list.map(Self.summary)
    }

    nonisolated static func summary(_ item: JSONValue) -> DAppOperationSummary {
        DAppOperationSummary(
            kind: item["kind"]?.stringValue ?? "?",
            destination: item["destination"]?.stringValue,
            amount: Mutez.toTez(item["amountMutez"]?.stringValue ?? item["balanceMutez"]?.stringValue),
            entrypoint: item["entrypoint"]?.stringValue,
            delegate: item["delegate"]?.stringValue,
            parameters: item["parameters"]?.stringValue,
            effects: item["effects"]?.arrayValue?.compactMap { e in
                e["text"]?.stringValue.map { DAppOperationSummary.Effect(text: $0, warning: e["warning"]?.boolValue ?? false) }
            } ?? [],
            opaque: item["opaque"]?.boolValue ?? false,
            fee: Mutez.toTez(item["feeMutez"]?.stringValue),
            burn: Mutez.toTez(item["burnMutez"]?.stringValue),
            requestedFee: Mutez.toTez(item["requestedFeeMutez"]?.stringValue)
        )
    }

    private func respondError(id: String, errorType: String) async {
        guard let data = try? JSONSerialization.data(withJSONObject: ["type": "error", "id": id, "errorType": errorType]),
              let json = String(data: data, encoding: .utf8) else { return }
        do {
            _ = try await bridge.call("octezConnectRespond", [json], timeout: 60)
        } catch {
            bridge.note("error reply to \(id) not delivered: \(error.localizedDescription)")
        }
    }

    private static func known(_ error: Error) -> ChainError? {
        if let chain = error as? ChainError { return chain }
        if case TaquitoBridge.BridgeError.javaScript(let message) = error { return ChainError.fromBridgeMessage(message) }
        return nil
    }

    /// Errors the user can fix and try again without the dApp hearing about it.
    private static func isRetryable(_ error: Error) -> Bool {
        switch known(error) {
        case .wrongPassphrase, .ledgerDeclined, .ledgerAppNotOpen, .ledgerLocked, .ledgerNotConnected: true
        default: false
        }
    }

    private static func friendly(_ error: Error) -> String {
        known(error)?.localizedDescription ?? error.localizedDescription
    }
}

extension DAppRequest {
    var isPermission: Bool { if case .permission = self { return true } else { return false } }
    var isOperation: Bool { if case .operation = self { return true } else { return false } }
}
