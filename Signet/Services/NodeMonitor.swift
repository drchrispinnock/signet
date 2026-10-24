import Foundation
import Observation

/// Health of the configured node, as seen from `GET /chains/main/blocks/head/header`.
enum NodeStatus: Equatable, Sendable {
    case unknown
    /// Reachable, head is fresh.
    case healthy(level: Int, headAge: TimeInterval, latency: TimeInterval)
    /// Reachable, but something is off (stale head, slow, odd response).
    case degraded(reason: String, level: Int?)
    /// Could not connect at all.
    case unreachable(reason: String)

    enum Light: Sendable { case grey, green, yellow, red }

    var light: Light {
        switch self {
        case .unknown: .grey
        case .healthy: .green
        case .degraded: .yellow
        case .unreachable: .red
        }
    }

    var level: Int? {
        switch self {
        case .healthy(let level, _, _): level
        case .degraded(_, let level): level
        default: nil
        }
    }

    var summary: String {
        switch self {
        case .unknown: "Checking…"
        case .healthy(_, let age, _): "Synced, head \(NodeMonitor.describe(age)) ago"
        case .degraded(let reason, _): reason
        case .unreachable: "Node down"
        }
    }

    /// Longer explanation for tooltips; same as `summary` unless there is more to say.
    var detail: String {
        if case .unreachable(let reason) = self { return reason }
        return summary
    }
}

/// Polls the node periodically and publishes a `NodeStatus`.
@MainActor
@Observable
final class NodeMonitor {
    /// Reply slower than this is "degraded" even if correct.
    nonisolated static let slowLatency: TimeInterval = 4
    /// A head older than this means the node is behind the chain.
    nonisolated static let staleHead: TimeInterval = 3 * 60
    nonisolated static let interval: TimeInterval = 30

    typealias Probe = @Sendable (URL) async throws -> (data: Data, status: Int, latency: TimeInterval)

    /// Which of the network's nodes this monitor watches: the layer 1 node, or the Layer 2
    /// Michelson node (only while the network has Layer 2 on; idle and grey otherwise).
    enum Layer: Sendable { case one, two }
    let layer: Layer

    /// The node being watched, or `nil` when the network has none for this layer.
    var endpoint: URL? {
        switch layer {
        case .one: network.rpcURL
        case .two: network.hasL2 ? network.l2RPCURL : nil
        }
    }

    /// The chain id a reply must carry, when the network pins one for this layer (S12).
    var expectedChainID: String? {
        switch layer {
        case .one: network.expectedChainID
        case .two: network.expectedL2ChainID
        }
    }

    private(set) var status: NodeStatus = .unknown
    private(set) var lastChecked: Date?
    /// Called when a check sees a higher head level than the last one: something may have changed.
    var onNewHead: ((Int) -> Void)?
    private var lastLevel: Int?
    var network: Network {
        didSet {
            guard network != oldValue else { return }
            status = .unknown
            lastLevel = nil
            restart()
        }
    }

    private let probe: Probe
    private var loop: Task<Void, Never>?

    init(network: Network, layer: Layer = .one, probe: Probe? = nil) {
        self.network = network
        self.layer = layer
        self.probe = probe ?? NodeMonitor.urlSessionProbe
    }

    /// Starts periodic polling (idempotent).
    func start() {
        guard loop == nil else { return }
        restart()
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    /// One probe, outcome published in `status`. Nothing to watch leaves the status unknown.
    func checkNow() async {
        guard let endpoint else { status = .unknown; return }
        let url = endpoint.appendingPathComponent("chains/main/blocks/head/header")
        let probe = probe
        let result: Result<(data: Data, status: Int, latency: TimeInterval), Error>
        do {
            result = .success(try await probe(url))
        } catch {
            result = .failure(error)
        }
        status = Self.evaluate(result, now: Date(), expectedChainID: expectedChainID)
        lastChecked = Date()
        if let level = status.level, level != lastLevel {
            let isFirst = lastLevel == nil
            lastLevel = level
            if !isFirst { onNewHead?(level) }
        }
    }

    /// Pure classification so it can be tested without a network.
    nonisolated static func evaluate(_ result: Result<(data: Data, status: Int, latency: TimeInterval), Error>, now: Date, expectedChainID: String? = nil) -> NodeStatus {
        switch result {
        case .failure(let error):
            return .unreachable(reason: "Cannot reach node: \((error as? URLError)?.localizedDescription ?? error.localizedDescription)")
        case .success(let reply):
            guard (200..<300).contains(reply.status) else {
                return .degraded(reason: "Node returned HTTP \(reply.status)", level: nil)
            }
            guard let object = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
                  let level = object["level"] as? Int,
                  let stamp = object["timestamp"] as? String,
                  let time = parseTimestamp(stamp)
            else {
                return .degraded(reason: "Unexpected reply from node", level: nil)
            }
            // The header names its chain: a node on another network is as wrong as no node (S12).
            if let expectedChainID, let found = object["chain_id"] as? String, found != expectedChainID {
                return .unreachable(reason: "Node serves chain \(found), not \(expectedChainID)")
            }
            let age = now.timeIntervalSince(time)
            if age > staleHead {
                return .degraded(reason: "Node is behind: head is \(describe(age)) old", level: level)
            }
            if reply.latency > slowLatency {
                return .degraded(reason: "Node is slow (\(String(format: "%.1f", reply.latency)) s)", level: level)
            }
            return .healthy(level: level, headAge: max(0, age), latency: reply.latency)
        }
    }

    nonisolated static func parseTimestamp(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: string)
    }

    nonisolated static func describe(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86400 { return "\(s / 3600) h" }
        return "\(s / 86400) d"
    }

    nonisolated static let urlSessionProbe: Probe = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0, Date().timeIntervalSince(started))
    }
}
