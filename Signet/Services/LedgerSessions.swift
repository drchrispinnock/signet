import Foundation

/// Device state spans multiple APDUs and JavaScript contexts. A process-wide lease protects the
/// entire session; individual HID exchange ordering is not sufficient.
actor LedgerSessions {
    static let shared = LedgerSessions()
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var owners: [String: UUID] = [:]
    private var waiting: [String: [Waiter]] = [:]

    func acquire(device: String) async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if owners[device] == nil { owners[device] = id; return id }
            guard (waiting[device]?.count ?? 0) < 16 else { throw URLError(.resourceUnavailable) }
            return try await withCheckedThrowingContinuation { continuation in
                waiting[device, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { Task { await self.cancel(id: id, device: device) } }
    }

    func release(id: UUID, device: String) {
        guard owners[device] == id else { return }
        if var list = waiting[device], !list.isEmpty {
            let next = list.removeFirst()
            waiting[device] = list
            owners[device] = next.id
            next.continuation.resume(returning: next.id)
        } else { owners[device] = nil; waiting[device] = nil }
    }

    private func cancel(id: UUID, device: String) {
        if let index = waiting[device]?.firstIndex(where: { $0.id == id }), let waiter = waiting[device]?.remove(at: index) {
            waiter.continuation.resume(throwing: CancellationError())
        } else { release(id: id, device: device) }
    }
}
