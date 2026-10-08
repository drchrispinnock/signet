import Foundation
import Testing
@testable import Signet

struct OctezConnectCryptoTests {
    /// The SDK swallows decryption errors; this exercises its sealed-box and session-key paths in JavaScriptCore.
    @Test func sdkCryptoRoundTripsInsideTheBridge() async throws {
        let r = try await TaquitoBridge.shared.call("octezConnectCryptoSelfTest")
        #expect(r["sealedRoundTrip"] == .bool(true), Comment(rawValue: "\(r)"))
        #expect(r["sessionRoundTrip"] == .bool(true), Comment(rawValue: "\(r)"))
    }
}
