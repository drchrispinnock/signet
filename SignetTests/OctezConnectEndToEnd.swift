import Foundation
import Testing
@testable import Signet

/// Full round trip against a real dApp client (the Node harness in the scratchpad): pair, receive
/// the permission request through the bridge event hook, answer it, and let the harness confirm.
/// Skips when the harness has not written a pairing code.
struct OctezConnectEndToEnd {
    static let codeURL = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-chris-tezos-signet/2d828a9a-b659-4771-9927-f86e491779b8/scratchpad/dapp-harness/pairing-code.txt")

    final class EventBox: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        func add(_ e: String) { lock.withLock { events.append(e) } }
        var all: [String] { lock.withLock { events } }
    }

    @Test(.tags(.network), .timeLimit(.minutes(3)))
    func pairsAndGrantsPermissionToARealDApp() async throws {
        // Give a running harness a few seconds to publish its code; otherwise skip.
        var code: String?
        for _ in 0..<5 {
            if let text = try? String(contentsOf: Self.codeURL, encoding: .utf8), !text.isEmpty { code = text; break }
            try await Task.sleep(for: .seconds(1))
        }
        guard let code else {
            print("No pairing code from the harness; skipping end-to-end pairing.")
            return
        }

        let box = EventBox()
        TaquitoBridge.shared.storage = InMemoryBridgeStorage()
        TaquitoBridge.shared.eventHandler = { box.add($0) }
        _ = try await TaquitoBridge.shared.call("octezConnectStart", ["Signet e2e", "", true])
        let paired = try await TaquitoBridge.shared.call("octezConnectPair", [code])
        #expect(paired["name"]?.stringValue == "Signet harness dApp")

        // Wait for the permission request to arrive.
        var request: DAppRequest?
        for _ in 0..<90 {
            if let r = box.all.lazy.compactMap({ DAppRequest.parse(eventJSON: $0) }).first { request = r; break }
            try await Task.sleep(for: .seconds(1))
        }
        let transcript = TaquitoBridge.shared.consoleLines.suffix(40).joined(separator: "\n")
        let permission = try #require(request, Comment(rawValue: "no permission request received.\nevents: \(box.all.map { String($0.prefix(200)) })\n--- console ---\n\(transcript)"))
        guard case .permission(let id, let app, let networkType, _, let scopes) = permission else { Issue.record("expected permission request, got \(permission)"); return }
        #expect(app.name == "Signet harness dApp")
        #expect(networkType == "shadownet")
        #expect(scopes.contains("operation_request"))

        // Answer with a fresh key, like the sheet would.
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let response: [String: Any] = [
            "type": "permission_response", "id": id, "network": ["type": networkType],
            "scopes": scopes.filter { ["sign", "operation_request"].contains($0) },
            "publicKey": material.publicKey, "address": material.address, "walletType": "implicit",
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8)!
        _ = try await TaquitoBridge.shared.call("octezConnectRespond", [json])

        let stored = try await TaquitoBridge.shared.call("octezConnectPermissions")
        #expect(stored.arrayValue?.first?["address"]?.stringValue == material.address,
                Comment(rawValue: "permissions after respond: \(stored)\n--- console ---\n\(TaquitoBridge.shared.consoleLines.suffix(30).joined(separator: "\n"))"))
        try? await Task.sleep(for: .seconds(3))  // let the response reach the dApp before the test host exits
    }
}
