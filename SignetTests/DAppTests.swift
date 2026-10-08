import Foundation
import Testing
@testable import Signet

struct DAppRequestParsingTests {
    @Test func parsesPermissionRequest() throws {
        let json = """
        {"kind":"request","message":{"id":"req-1","type":"permission_request","version":"3","senderId":"abc",
          "appMetadata":{"senderId":"abc","name":"objkt.com","icon":"https://objkt.com/icon.png"},
          "network":{"type":"mainnet"},"scopes":["operation_request","sign"]}}
        """
        let request = try #require(DAppRequest.parse(eventJSON: json))
        guard case .permission(let id, let app, let networkType, let rpc, let scopes) = request else { Issue.record("wrong kind"); return }
        #expect(id == "req-1")
        #expect(app.name == "objkt.com")
        #expect(app.icon?.host() == "objkt.com")
        #expect(networkType == "mainnet")
        #expect(rpc == nil)
        #expect(scopes == ["operation_request", "sign"])
        #expect(request.isPermission)
    }

    @Test func parsesOperationAndSignRequests() throws {
        let op = """
        {"kind":"request","message":{"id":"req-2","type":"operation_request","appMetadata":{"name":"dapp"},
          "network":{"type":"custom","rpcUrl":"https://rpc.shadownet.teztnets.com"},"sourceAddress":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb",
          "operationDetails":[{"kind":"transaction","destination":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton","amount":"0","parameters":{"entrypoint":"collect","value":{"int":"1"}}}]}}
        """
        guard case .operation(_, _, let type, let rpc, let source, let details) = try #require(DAppRequest.parse(eventJSON: op)) else { Issue.record("wrong kind"); return }
        #expect(type == "custom")
        #expect(rpc?.host() == "rpc.shadownet.teztnets.com")
        #expect(source.value.hasPrefix("tz1"))
        #expect(details.contains("\"entrypoint\":\"collect\""))

        let sign = """
        {"kind":"request","message":{"id":"req-3","type":"sign_payload_request","appMetadata":{"name":"dapp"},
          "sourceAddress":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb","signingType":"micheline","payload":"0501000000076865792074657a"}}
        """
        guard case .signPayload(_, _, _, let signingType, let payload) = try #require(DAppRequest.parse(eventJSON: sign)) else { Issue.record("wrong kind"); return }
        #expect(signingType == "micheline")
        #expect(payload.hasPrefix("0501"))

        #expect(DAppRequest.parse(eventJSON: "{\"kind\":\"other\"}") == nil)
    }

    @Test func mapsRequestNetworksOntoOurs() {
        #expect(DAppRequest.network(forType: "mainnet", rpcURL: nil) == .mainnet)
        #expect(DAppRequest.network(forType: "shadownet", rpcURL: nil) == .shadownet)
        #expect(DAppRequest.network(forType: "ushuaianet", rpcURL: nil) == .currentnet)
        #expect(DAppRequest.network(forType: "custom", rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")) == .shadownet)
        #expect(DAppRequest.network(forType: "custom", rpcURL: URL(string: "https://rpc.example.org"))?.chain == "custom")
        #expect(DAppRequest.network(forType: "ghostnet", rpcURL: nil) == nil)
    }
}

struct OctezConnectBridgeTests {
    /// Round-trips through the SDK's serializer offline: the bridge must at least load the SDK
    /// and understand a pairing code.
    @Test(.timeLimit(.minutes(1)))
    func bridgeLoadsTheSDKAndDescribesOperations() async throws {
        let described = try await TaquitoBridge.shared.call("octezConnectDescribe", [
            #"[{"kind":"transaction","destination":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton","amount":"1500000","parameters":{"entrypoint":"collect","value":{"int":"1"}}},{"kind":"delegation","delegate":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"}]"#
        ])
        let list = try #require(described.arrayValue)
        #expect(list.count == 2)
        #expect(list[0]["entrypoint"] == .string("collect"))
        #expect(list[0]["amountMutez"] == .string("1500000"))
        #expect(list[1]["delegate"]?.stringValue?.hasPrefix("tz1") == true)
    }

    @Test(.tags(.network), .timeLimit(.minutes(2)))
    func startsTheWalletClientAgainstTheRelay() async throws {
        TaquitoBridge.shared.storage = InMemoryBridgeStorage()
        let result = try await TaquitoBridge.shared.call("octezConnectStart", ["Signet tests", ""])
        #expect(result["started"] == .bool(true))
        let permissions = try await TaquitoBridge.shared.call("octezConnectPermissions")
        #expect(permissions.arrayValue?.isEmpty == true)
        // Missing storage keys must read as the SDK's defaults (empty lists), not undefined.
        let peers = try await TaquitoBridge.shared.call("octezConnectPeers")
        #expect(peers.arrayValue?.isEmpty == true)
    }
}
