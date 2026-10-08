import Foundation
import Testing
@testable import Signet

/// Exercises the JavaScriptCore host. The first two tests are offline; the rest hit Shadownet
/// and are tagged so they can be excluded with `-skip-testing` when offline.
struct TaquitoBridgeTests {
    @Test func bundleLoadsAndReportsVersion() async throws {
        let version = try await TaquitoBridge.shared.call("version")
        #expect(version == .string("0.10.0"))
    }

    @Test(arguments: [
        ("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", true),
        ("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq", true),
        ("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm", true),
        ("KT1BRd2ka5q2cPRdXALtXD1QZ38CPam2j1ye", true),
        ("tz1junk", false),
        ("", false),
    ])
    func validatesAddresses(address: String, expected: Bool) async throws {
        let valid = try await TaquitoBridge.shared.call("isValidAddress", [address])
        #expect(valid == .bool(expected))
    }

    @Test(.tags(.network), .timeLimit(.minutes(1))) func fetchesHeadFromShadownet() async throws {
        let head = try await TaquitoBridge.shared.call("getHead", [Network.shadownet.rpcURL.absoluteString])
        let level = try #require(head["level"]?.doubleValue)
        #expect(level > 0)
        #expect(head["hash"]?.stringValue?.hasPrefix("B") == true)
    }

    @Test(.tags(.network), .timeLimit(.minutes(1))) func fetchesBalanceThroughChainService() async throws {
        let service = TaquitoChainService(network: .shadownet)
        // Any valid address works since the RPC returns 0 for unknown accounts; this only checks the round trip.
        let balance = try await service.tezBalance(for: Address("tz1a4GT7THHaGDiTxgXoatDWcZfJ5j29z5RC"))
        #expect(balance.total >= 0)
        #expect(balance.total >= balance.spendable)
    }
}

extension Tag {
    @Tag static var network: Self
}
