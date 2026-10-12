import Foundation

/// One foreground bridge operation at a time: a read timeout can tear down its entire context
/// and HTTP work without cancelling a concurrent signature or injection.
actor BridgeCallGate {
    private var active = 0
    private let limit: Int
    init(limit: Int = 1) { self.limit = max(1, limit) }
    private var waiting: [CheckedContinuation<Void, Error>] = []
    func acquire() async throws {
        if active < limit { active += 1; return }
        guard waiting.count < 64 else { throw URLError(.resourceUnavailable) }
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
}
