import CryptoKit
import Foundation
import Testing
@testable import Signet

/// Pairs with a made-up dApp on the real relay and writes the SDK/host transcript to a file every
/// few seconds, so a hang still leaves evidence behind.
struct OctezConnectPairingDiagnostic {
    static let transcriptURL = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-chris-tezos-signet/2d828a9a-b659-4771-9927-f86e491779b8/scratchpad/pairing-transcript.txt")

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func pairingCompletesAgainstTheRelay() async throws {
        let storage = InMemoryBridgeStorage()
        TaquitoBridge.shared.storage = storage
        let snapshots = Task.detached {
            while !Task.isCancelled {
                let lines = TaquitoBridge.shared.consoleLines.joined(separator: "\n")
                let keys = ["beacon:matrix-selected-node", "beacon:matrix-peer-rooms", "beacon:matrix-preserved-state"]
                    .map { "\($0) = \(storage.get($0).map { String($0.prefix(100)) } ?? "nil")" }.joined(separator: "\n")
                try? "\(Date())\n--- storage ---\n\(keys)\n--- console ---\n\(lines)\n".write(to: Self.transcriptURL, atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .seconds(3))
            }
        }
        defer { snapshots.cancel() }

        _ = try await TaquitoBridge.shared.call("octezConnectStart", ["Signet tests", "", true])
        let keyBytes = Array(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        let peer: [String: Any] = [
            "type": "p2p-pairing-request", "id": UUID().uuidString.lowercased(), "name": "Synthetic dApp",
            "publicKey": keyBytes.map { String(format: "%02x", $0) }.joined(),
            "version": "3", "relayServer": "beacon-node-8.octez.io",
        ]
        let peerJSON = String(data: try JSONSerialization.data(withJSONObject: peer), encoding: .utf8)!
        let code = try await TaquitoBridge.shared.call("octezConnectMakePairingCode", [peerJSON]).stringValue ?? ""
        #expect(!code.isEmpty)
        _ = try await TaquitoBridge.shared.call("octezConnectPair", [code])
        try? await Task.sleep(for: .seconds(8))
        let transcript = TaquitoBridge.shared.consoleLines
        let longPolls = transcript.filter { $0.contains("/_matrix/client/r0/sync?") && $0.contains("since=") }
        #expect(!longPolls.isEmpty, Comment(rawValue: "no parameterised sync seen:\n" + transcript.suffix(30).joined(separator: "\n")))
        #expect(!transcript.contains { $0.contains("URLSearchParams") || $0.contains("Can't find variable") },
                Comment(rawValue: transcript.filter { $0.contains("[error]") }.joined(separator: "\n")))
        #expect(transcript.contains { $0.contains("/invite") }, "the pairing response room invite should have been sent")
    }
}
