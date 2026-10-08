import Testing
@testable import Signet

struct BridgeConsoleTests {
    @Test func javascriptConsoleReachesTheHostLog() async throws {
        let result = try await TaquitoBridge.shared.call("bridgeEcho", ["ping-\(Int.random(in: 1000...9999))"])
        let echoed = result["echoed"]?.stringValue ?? ""
        let lines = TaquitoBridge.shared.consoleLines
        #expect(lines.contains { $0 == "[log] echo: \(echoed)" }, Comment(rawValue: "console types: \(result)\nlast lines:\n" + lines.suffix(8).joined(separator: "\n")))
        #expect(lines.contains { $0 == "[warn] echo-warn: \(echoed)" })
    }
}
