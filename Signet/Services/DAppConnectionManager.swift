import Foundation
import Observation

/// Owns the Octez Connect session: starts the SDK in the bridge, surfaces incoming dApp
/// requests one at a time for the UI to approve, and sends the responses.
@MainActor
@Observable
final class DAppConnectionManager {
    enum ConnectError: LocalizedError {
        case notOurWallet(Address)
        case noUsableKey(String)
        case unsupportedNetwork(String)
        case refusedPayload(String)

        var errorDescription: String? {
            switch self {
            case .notOurWallet(let address): "The dApp asked for \(address.shortened()), which is not one of your accounts."
            case .noUsableKey(let alias): "Signet cannot sign with “\(alias)” (no key on disk or Ledger)."
            case .unsupportedNetwork(let type): "The dApp wants the “\(type)” network, which Signet does not have."
            case .refusedPayload(let why): why
            }
        }
    }

    private(set) var isStarted = false
    private(set) var pending: [DAppRequest] = []
    private(set) var permissions: [DAppPermission] = []
    private(set) var lastError: String?
    /// Something to show briefly after a request completes, e.g. "Sent ooABC…".
    private(set) var lastOutcome: String?

    private let bridge: TaquitoBridge
    private let storage: any BridgeStorage
    private let walletsProvider: @MainActor () -> [Wallet]
    private let signerProvider: @MainActor (Wallet, String?) throws -> SigningKey?

    var current: DAppRequest? { pending.first }

    init(bridge: TaquitoBridge = .shared,
         storage: any BridgeStorage,
         wallets: @escaping @MainActor () -> [Wallet],
         signer: @escaping @MainActor (Wallet, String?) throws -> SigningKey?) {
        self.bridge = bridge
        self.storage = storage
        self.walletsProvider = wallets
        self.signerProvider = signer
    }

    // MARK: Lifecycle

    func start() async {
        guard !isStarted else { return }
        bridge.storage = storage
        bridge.eventHandler = { [weak self] json in
            Task { @MainActor in self?.handle(eventJSON: json) }
        }
        do {
            bridge.note("Octez Connect starting")
            _ = try await bridge.call("octezConnectStart", ["Signet", "https://raw.githubusercontent.com/drchrispinnock/signet/main/docs/images/signet-256.png", true])
            isStarted = true
            bridge.note("Octez Connect started")
            await reloadPermissions()
        } catch {
            lastError = "Octez Connect failed to start: \(error.localizedDescription)"
            bridge.note("Octez Connect failed to start: \(error.localizedDescription)")
        }
    }

    /// Stops and restarts the SDK client, e.g. after the wallet directory changed.
    func restart() async {
        _ = try? await bridge.call("octezConnectStop")
        isStarted = false
        await start()
    }

    /// Pairs with a dApp from its pairing code. Returns the dApp's name.
    @discardableResult
    func pair(code: String) async throws -> String {
        if !isStarted { await start() }
        bridge.note("Pairing with a \(code.count)-character code")
        let result = try await bridge.call("octezConnectPair", [code])
        return result["name"]?.stringValue ?? "dApp"
    }

    func reloadPermissions() async {
        guard let list = try? await bridge.call("octezConnectPermissions").arrayValue else { return }
        permissions = list.compactMap { item in
            guard let account = item["accountIdentifier"]?.stringValue, let sender = item["senderId"]?.stringValue else { return nil }
            let meta = item["appMetadata"]
            return DAppPermission(
                accountIdentifier: account, senderId: sender,
                address: item["address"]?.stringValue ?? "",
                appName: meta?["name"]?.stringValue ?? "dApp",
                appIcon: meta?["icon"]?.stringValue.flatMap(URL.init(string:)),
                networkType: item["network"]?["type"]?.stringValue ?? "mainnet",
                scopes: item["scopes"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                connectedAt: item["connectedAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
    }

    func disconnect(_ permission: DAppPermission) async {
        _ = try? await bridge.call("octezConnectRemovePermission", [permission.accountIdentifier, permission.senderId])
        await reloadPermissions()
    }

    func disconnectAll() async {
        _ = try? await bridge.call("octezConnectRemoveAll")
        await reloadPermissions()
    }

    // MARK: Incoming

    private func handle(eventJSON: String) {
        NSLog("Signet dApp event: %@", String(eventJSON.prefix(600)))
        if let data = eventJSON.data(using: .utf8),
           let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           event["kind"] as? String == "error" {
            lastError = event["message"] as? String
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
        pending.append(request)
    }

    private func finish(_ request: DAppRequest) {
        pending.removeAll { $0.id == request.id }
    }

    // MARK: Answers

    func approvePermission(_ request: DAppRequest, with wallet: Wallet) async {
        guard case .permission(let id, _, let networkType, let rpcURL, let scopes) = request else { return }
        defer { finish(request) }
        guard let publicKey = wallet.publicKey else {
            lastError = "“\(wallet.alias)” has no public key, so it cannot be shared with a dApp."
            await respondError(id: id, errorType: "NOT_GRANTED_ERROR")
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
        await respond(response)
        await reloadPermissions()
        lastOutcome = "Connected “\(request.app.name)” to \(wallet.alias)"
    }

    func approveOperation(_ request: DAppRequest, passphrase: String?) async {
        guard case .operation(let id, _, let networkType, let rpcURL, let source, let operationsJSON) = request else { return }
        do {
            let (wallet, signer) = try signer(for: source, passphrase: passphrase)
            guard let network = DAppRequest.network(forType: networkType, rpcURL: rpcURL) else { throw ConnectError.unsupportedNetwork(networkType) }
            let result = try await bridge.call("octezConnectExecute", [network.rpcURL.absoluteString, signer.bridgeSpec, operationsJSON])
            let hash = result["hash"]?.stringValue ?? ""
            await respond(["type": "operation_response", "id": id, "transactionHash": hash])
            lastOutcome = "Sent \(hash.prefix(12))… for “\(request.app.name)” from \(wallet.alias)"
            finish(request)
        } catch {
            lastError = Self.friendly(error)
            // Wrong password or Ledger not ready: leave the request up so the user can retry.
            if Self.isRetryable(error) { return }
            await respondError(id: id, errorType: "TRANSACTION_INVALID_ERROR")
            finish(request)
        }
    }

    func approveSignature(_ request: DAppRequest, passphrase: String?) async {
        guard case .signPayload(let id, _, let source, let signingType, let payload) = request else { return }
        do {
            if let why = request.signRefusal { throw ConnectError.refusedPayload(why) }
            let (_, signer) = try signer(for: source, passphrase: passphrase)
            let result = try await bridge.call("octezConnectSign", [signer.bridgeSpec, payload, signingType])
            guard let signature = result["signature"]?.stringValue else { throw TaquitoBridge.BridgeError.javaScript("no signature") }
            await respond(["type": "sign_payload_response", "id": id, "signingType": signingType, "signature": signature])
            lastOutcome = "Signed a message for “\(request.app.name)”"
            finish(request)
        } catch {
            lastError = Self.friendly(error)
            if Self.isRetryable(error) { return }
            await respondError(id: id, errorType: "SIGNATURE_TYPE_NOT_SUPPORTED")
            finish(request)
        }
    }

    func reject(_ request: DAppRequest) async {
        await respondError(id: request.id, errorType: request.isPermission ? "NOT_GRANTED_ERROR" : "ABORTED_ERROR")
        finish(request)
    }

    func clearMessages() {
        lastError = nil
        lastOutcome = nil
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

    func summaries(for operationsJSON: String) async -> [DAppOperationSummary] {
        guard let list = try? await bridge.call("octezConnectDescribe", [operationsJSON]).arrayValue else { return [] }
        return list.map { item in
            DAppOperationSummary(
                kind: item["kind"]?.stringValue ?? "?",
                destination: item["destination"]?.stringValue,
                amount: Mutez.toTez(item["amountMutez"]?.stringValue ?? item["balanceMutez"]?.stringValue),
                entrypoint: item["entrypoint"]?.stringValue,
                delegate: item["delegate"]?.stringValue
            )
        }
    }

    private func respond(_ message: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let json = String(data: data, encoding: .utf8) else { return }
        do {
            _ = try await bridge.call("octezConnectRespond", [json])
        } catch {
            lastError = "Could not reply to the dApp: \(error.localizedDescription)"
        }
    }

    private func respondError(id: String, errorType: String) async {
        await respond(["type": "error", "id": id, "errorType": errorType])
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
}
