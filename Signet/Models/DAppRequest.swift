import Foundation

/// A dApp as it describes itself in a TZIP-10 request.
struct DAppInfo: Hashable, Sendable {
    let name: String
    let icon: URL?
    let url: URL?
    let senderId: String
}

/// What a connected dApp is asking the wallet to do.
enum DAppRequest: Identifiable, Hashable, Sendable {
    case permission(id: String, app: DAppInfo, networkType: String, rpcURL: URL?, scopes: [String])
    case operation(id: String, app: DAppInfo, networkType: String, rpcURL: URL?, source: Address, operationsJSON: String)
    case signPayload(id: String, app: DAppInfo, source: Address, signingType: String, payload: String)
    case unsupported(id: String, app: DAppInfo, type: String)

    var id: String {
        switch self {
        case .permission(let id, _, _, _, _), .operation(let id, _, _, _, _, _), .signPayload(let id, _, _, _, _), .unsupported(let id, _, _): id
        }
    }

    var app: DAppInfo {
        switch self {
        case .permission(_, let app, _, _, _), .operation(_, let app, _, _, _, _), .signPayload(_, let app, _, _, _), .unsupported(_, let app, _): app
        }
    }

    /// Parses the `{kind: "request", message: {...}}` event the bridge emits.
    static func parse(eventJSON: String) -> DAppRequest? {
        guard let data = eventJSON.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["kind"] as? String == "request",
              let message = event["message"] as? [String: Any],
              let id = message["id"] as? String,
              let type = message["type"] as? String
        else { return nil }

        // The bridge rebuilt this message from the peer the transport authenticated (S04): the
        // sender id is the message's own, never the self-asserted one inside `appMetadata`.
        let meta = message["appMetadata"] as? [String: Any] ?? [:]
        let app = DAppInfo(
            name: meta["name"] as? String ?? "Unknown dApp",
            icon: (meta["icon"] as? String).flatMap(URL.init(string:)),
            url: (meta["appUrl"] as? String).flatMap(URL.init(string:)),
            senderId: message["senderId"] as? String ?? ""
        )
        let network = message["network"] as? [String: Any]
        let networkType = network?["type"] as? String ?? "mainnet"
        let rpcURL = (network?["rpcUrl"] as? String).flatMap(URL.init(string:))

        switch type {
        case "permission_request":
            return .permission(id: id, app: app, networkType: networkType, rpcURL: rpcURL, scopes: message["scopes"] as? [String] ?? [])
        case "operation_request":
            guard let source = message["sourceAddress"] as? String,
                  let details = message["operationDetails"],
                  let json = try? JSONSerialization.data(withJSONObject: details),
                  let text = String(data: json, encoding: .utf8)
            else { return .unsupported(id: id, app: app, type: type) }
            return .operation(id: id, app: app, networkType: networkType, rpcURL: rpcURL, source: Address(source), operationsJSON: text)
        case "sign_payload_request":
            guard let source = message["sourceAddress"] as? String, let payload = message["payload"] as? String else {
                return .unsupported(id: id, app: app, type: type)
            }
            return .signPayload(id: id, app: app, source: Address(source), signingType: message["signingType"] as? String ?? "raw", payload: payload)
        default:
            return .unsupported(id: id, app: app, type: type)
        }
    }

    /// Why a sign_payload request must be refused, or `nil` when it is safe to put in front of the user.
    var signRefusal: String? {
        guard case .signPayload(_, _, _, let signingType, let payload) = self else { return nil }
        return DAppSignPayload.refusal(signingType: signingType, payload: payload)
    }

    /// Which of our networks a request's network refers to, or `nil` if we cannot serve it.
    ///
    /// A dApp's "custom" network names an RPC endpoint of the dApp's choosing (S12): it is
    /// accepted only as a public HTTPS endpoint without credentials, or when it is exactly the
    /// node the user configured for one of our networks (scheme, host, port and path). A dApp
    /// cannot point the wallet at this machine or the local network, and a user-configured
    /// local node is never reachable through a dApp's request unless the dApp names it exactly.
    static func network(forType type: String, rpcURL: URL?) -> Network? {
        let kind = type.lowercased()
        // A dApp's "custom" network is identified by its RPC, never by our own Custom entry.
        if let match = Network.all.first(where: { $0.chain == kind && $0.chain != "custom" }) { return match }
        if kind == "custom", let rpcURL {
            if let known = Network.all.first(where: { $0.chain != "custom" && sameEndpoint($0.defaultRPCURL, rpcURL) }) { return known }
            guard EndpointPolicy.isPublicHTTPS(rpcURL) else { return nil }
            return Network(name: "Custom (\(endpointDescription(rpcURL)))", chain: "custom", rpcURL: rpcURL, tezosDomainsURL: nil, tzktURL: nil)
        }
        // Currentnet is whatever proposal net is live; accept its current protocol name too.
        if kind == "ushuaianet" { return .currentnet }
        return nil
    }

    /// Two endpoints are the same only when scheme, host, port and path all agree (S12).
    static func sameEndpoint(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        func key(_ url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            var path = url.path(percentEncoded: true)
            while path.hasSuffix("/") { path.removeLast() }
            return "\(scheme)://\(host):\(port)\(path)"
        }
        guard let ka = key(a), let kb = key(b) else { return false }
        return ka == kb
    }

    /// Host, port and path of an endpoint, for showing where a custom network points.
    static func endpointDescription(_ url: URL) -> String {
        var text = url.host(percentEncoded: false) ?? url.absoluteString
        if let port = url.port { text += ":\(port)" }
        let path = url.path(percentEncoded: false)
        if !path.isEmpty, path != "/" { text += path }
        return text
    }
}

/// One operation of a dApp batch as the approval sheet shows it: what it does, what it costs.
struct DAppOperationSummary: Hashable, Sendable {
    struct Effect: Hashable, Sendable {
        let text: String
        /// Moves or exposes assets (token transfers, operator approvals, allowances, originations).
        let warning: Bool
    }

    let kind: String
    let destination: String?
    let amount: Decimal?
    let entrypoint: String?
    let delegate: String?
    /// The contract call's parameters (or an origination's script) as Micheline JSON, verbatim.
    let parameters: String?
    /// Decoded effects for standard contract calls (FA2/FA1.2 transfers, operators, allowances).
    let effects: [Effect]
    /// A contract call Signet could not decode: the user approves on the raw parameters alone.
    let opaque: Bool
    /// Exact fee and storage burn from the node's simulation; `nil` before preparation.
    let fee: Decimal?
    let burn: Decimal?
    /// The dApp asked for a higher fee than the node's estimate; Signet pays the estimate.
    let requestedFee: Decimal?
}

/// A dApp batch simulated by the node and ready to sign exactly as shown.
struct DAppPreparedBatch: Hashable, Sendable {
    let requestID: String
    let operations: [DAppOperationSummary]
    /// Fee and burn of the reveal the batch will start with, when the account has not revealed its key.
    let revealFee: Decimal?
    let revealBurn: Decimal?
    let totalAmount: Decimal
    let totalFee: Decimal
    let totalBurn: Decimal
    /// Everything that leaves the account: amounts + fees + burn.
    let totalDebit: Decimal
    /// The exact Taquito params that will be executed, fee/gas/storage included.
    let preparedJSON: String

    var hasWarnings: Bool { operations.contains { $0.opaque || $0.effects.contains(where: \.warning) } }
}

/// A permission a dApp holds, as stored by the SDK.
struct DAppPermission: Identifiable, Hashable, Sendable {
    let accountIdentifier: String
    let senderId: String
    let address: String
    let appName: String
    let appIcon: URL?
    let networkType: String
    /// The endpoint a custom-network grant was made for; `nil` for named networks.
    var networkRPCURL: URL? = nil
    let scopes: [String]
    let connectedAt: Date?

    var id: String { accountIdentifier + ":" + senderId }
}

/// What Signet is willing to sign for a dApp's sign_payload request.
///
/// A signature is over the Blake2b hash of the raw bytes, and the chain signs operations the same
/// way with a `03` watermark in front, so a "message" whose hex starts with `03` is an operation
/// signature a dApp could inject. Only the `micheline` type is accepted, and only when the bytes
/// start with `05`, the packed-data prefix no chain operation uses, and decode as exactly one
/// Micheline expression with nothing left over; that is the form every dApp produces for
/// "Tezos Signed Message" and TZIP-17 permits. The `operation` and `raw` types are
/// refused outright. The bridge applies the same rule before signing.
enum DAppSignPayload {
    static let maxHexLength = 64 * 1024

    static func refusal(signingType: String, payload: String) -> String? {
        guard signingType == "micheline" else {
            return "Signet only signs “micheline” messages, not “\(signingType)”, because other types could be operations."
        }
        guard payload.count.isMultiple(of: 2), !payload.isEmpty, payload.allSatisfy(\.isHexDigit) else {
            return "The message is not valid hex."
        }
        guard payload.count <= maxHexLength else { return "The message is too long to sign." }
        guard payload.hasPrefix("05") else {
            return "The message is not packed Michelson data (it does not start with 05), so it could be an operation."
        }
        guard MichelineBinary.isPackedExpression(hex: payload) else {
            return "The message is not one complete packed Michelson expression."
        }
        return nil
    }
}
