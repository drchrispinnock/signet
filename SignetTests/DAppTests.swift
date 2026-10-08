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

/// S02: a sign_payload whose bytes start with 03 would be an operation signature, so only packed
/// Michelson (05…) of type `micheline` may reach the signer.
struct DAppSignPayloadTests {
    @Test func acceptsPackedMichelineMessages() {
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: "0501000000076865792074657a") == nil)
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: "05070701000000036162630001") == nil)
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: "0501000000076865792074657A") == nil)
    }

    @Test(arguments: ["operation", "raw", "", "MICHELINE"])
    func refusesOtherSigningTypes(type: String) {
        #expect(DAppSignPayload.refusal(signingType: type, payload: "0501000000076865792074657a") != nil)
    }

    @Test func refusesOperationBytesWhateverTheTypeSays() {
        // 03 + forged transfer: the same hash the chain signs for a real transaction.
        let forged = "03" + "8fcf233671b6a04fcf679d2a381c2544ea6c1ea29ba6157776ed8424c7ccd00b6c0002298c03ed7d454a101eb7022bc95f7e5f41ac78d0860303c8010080c2d72f0000e7670f32038107a59a2b9cfefae36ea21f5aa63c00"
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: forged) != nil)
        #expect(DAppSignPayload.refusal(signingType: "operation", payload: forged) != nil)
        #expect(DAppSignPayload.refusal(signingType: "raw", payload: forged) != nil)
    }

    @Test(arguments: ["", "0", "051", "05zz", "0x0501", "0501 00"])
    func refusesMalformedHex(payload: String) {
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: payload) != nil)
    }

    /// The reviewer's gap: the 05 prefix alone is not enough, the rest must be one whole expression.
    @Test(arguments: [
        "05",                                   // prefix alone
        "050100000007686579",                   // string truncated: declares 7 bytes, has 3
        "0501000000026865792074657a",           // declared length too short: trailing bytes
        "0501000000076865792074657a00",         // a complete string, then a stray byte
        "0500",                                 // zarith with no bytes
        "050080",                               // zarith continuation never ends
        "0502000000040100000001",               // sequence whose element overruns its length
        "0507070701000000016100",               // Pair with a missing second argument
        "050a00000003abcd",                     // bytes truncated
        "0509030000000000",                     // generic prim: annots length missing
        "050b",                                 // unknown tag
    ])
    func refusesMalformedMichelineEnvelopes(payload: String) {
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: payload) != nil)
        #expect(!MichelineBinary.isPackedExpression(hex: payload))
    }

    @Test(arguments: [
        "0501000000076865792074657a",           // "hey tez"
        "050021",                               // int 33
        "050080ff7f",                           // multi-byte int
        "050a00000002abcd",                     // bytes
        "05030b",                               // Unit
        "050707010000000161010000000162",       // Pair "a" "b"
    ])
    func acceptsWellFormedMichelineEnvelopes(payload: String) {
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: payload) == nil)
    }

    @Test func acceptsNestedExpressions() throws {
        // Pair (Pair "a" 1) { "b" ; 0x00 } with an annotation on the outer Pair, as a permit might pack.
        let inner = "0707" + "0100000001" + "61" + "0001"                       // Pair "a" 1
        let seq = "02" + "0000000c" + "0100000001" + "62" + "0a0000000100"       // { "b" ; 0x00 } (12 bytes)
        let outer = "0807" + inner + seq + "00000002" + "2561"                 // Pair ... ... %a
        #expect(MichelineBinary.isPackedExpression(hex: "05" + outer))
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: "05" + outer) == nil)
        // The same expression with the annotation length claiming one byte too many.
        let overlong = "0807" + inner + seq + "00000003" + "2561"
        #expect(!MichelineBinary.isPackedExpression(hex: "05" + overlong))
    }

    @Test func refusesOversizedPayloads() {
        let huge = "05" + String(repeating: "00", count: DAppSignPayload.maxHexLength / 2)
        #expect(DAppSignPayload.refusal(signingType: "micheline", payload: huge) != nil)
    }

    @Test func requestReportsItsOwnRefusal() throws {
        func request(type: String, payload: String) throws -> DAppRequest {
            let json = """
            {"kind":"request","message":{"id":"req-9","type":"sign_payload_request","appMetadata":{"name":"dapp"},
              "sourceAddress":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb","signingType":"\(type)","payload":"\(payload)"}}
            """
            return try #require(DAppRequest.parse(eventJSON: json))
        }
        #expect(try request(type: "micheline", payload: "0501000000076865792074657a").signRefusal == nil)
        #expect(try request(type: "operation", payload: "03ab").signRefusal != nil)
        #expect(try request(type: "micheline", payload: "03ab").signRefusal != nil)
    }

    /// The bridge enforces the rule itself, so a Swift bug cannot get an operation signed.
    @Test func bridgeRefusesOperationBytesAndSignsMicheline() async throws {
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let spec = SigningKey.secret(material.secretKey, passphrase: nil).bridgeSpec
        let forged = "03" + "8fcf233671b6a04fcf679d2a381c2544ea6c1ea29ba6157776ed8424c7ccd00b6c0002298c03ed7d454a101eb7022bc95f7e5f41ac78d0860303c8010080c2d72f0000e7670f32038107a59a2b9cfefae36ea21f5aa63c00"
        for type in ["micheline", "operation", "raw"] {
            await #expect(throws: (any Error).self) { try await TaquitoBridge.shared.call("octezConnectSign", [spec, forged, type]) }
        }
        await #expect(throws: (any Error).self) { try await TaquitoBridge.shared.call("octezConnectSign", [spec, "0501000000076865792074657a"]) }
        for payload in MichelineDepthTests.rejectedPayloads {
            await #expect(throws: (any Error).self) {
                try await TaquitoBridge.shared.call("octezConnectSign", [spec, payload, "micheline"])
            }
        }
        for payload in MichelineDepthTests.acceptedPayloads {
            let result = try await TaquitoBridge.shared.call("octezConnectSign", [spec, payload, "micheline"])
            #expect(result["signature"]?.stringValue?.hasPrefix("edsig") == true)
        }
        // The bridge's own Micheline reader must agree with MichelineBinary on every vector above.
        for malformed in ["05", "050100000007686579", "0501000000026865792074657a", "0501000000076865792074657a00", "0500", "050080",
                          "0502000000040100000001", "0507070701000000016100", "050a00000003abcd", "0509030000000000", "050b"] {
            await #expect(throws: (any Error).self, "\(malformed)") { try await TaquitoBridge.shared.call("octezConnectSign", [spec, malformed, "micheline"]) }
        }
        for good in ["050021", "050080ff7f", "050a00000002abcd", "05030b", "050707010000000161010000000162",
                     "0508070707010000000161000102" + "0000000c" + "0100000001620a0000000100" + "000000022561"] {
            let r = try await TaquitoBridge.shared.call("octezConnectSign", [spec, good, "micheline"])
            #expect(r["signature"]?.stringValue?.hasPrefix("edsig") == true, "\(good)")
        }

        let signed = try await TaquitoBridge.shared.call("octezConnectSign", [spec, "0501000000076865792074657a", "micheline"])
        let signature = try #require(signed["signature"]?.stringValue)
        #expect(signature.hasPrefix("edsig"))
        // Same bytes through the plain signing path give the same signature: nothing else changed.
        let plain = try await TaquitoBridge.shared.call("signPayload", [spec, "0501000000076865792074657a"])
        #expect(plain["signature"]?.stringValue == signature)
    }
}

struct MichelineDepthTests {
    static func nestedSome(_ depth: Int) -> String {
        "05" + String(repeating: "0509", count: depth) + "0000"
    }

    static func nestedSequence(_ depth: Int) -> String {
        var expression = "0000"
        for _ in 0..<depth {
            let length = String(expression.count / 2, radix: 16)
            expression = "02" + String(repeating: "0", count: 8 - length.count) + length + expression
        }
        return "05" + expression
    }

    // Generic primitive with one argument and no annotations exercises the variable-arity path.
    static func genericSome(_ child: String) -> String {
        let expression = String(child.dropFirst(2))
        let length = String(expression.count / 2, radix: 16)
        return "050909" + String(repeating: "0", count: 8 - length.count) + length + expression + "00000000"
    }

    static var acceptedPayloads: [String] {
        [nestedSome(0), nestedSome(128), nestedSequence(128), genericSome(nestedSome(127))]
    }

    static var rejectedPayloads: [String] {
        [nestedSome(129), nestedSequence(129), genericSome(nestedSome(128)), nestedSome(16_000)]
    }

    @Test func acceptsDepthBoundary() {
        for payload in Self.acceptedPayloads {
            #expect(MichelineBinary.isPackedExpression(hex: payload))
        }
    }

    @Test func rejectsExcessiveDepthWithoutCrashing() {
        for payload in Self.rejectedPayloads {
            // The original crash reproducer fits within the signing flow's size limit.
            #expect(payload.count <= 64 * 1024)
            #expect(!MichelineBinary.isPackedExpression(hex: payload))
        }
    }

    @Test func sequenceSiblingsDoNotAccumulateDepth() {
        let elements = String(repeating: "0000", count: 1_000)
        let payload = "0502000007d0" + elements
        #expect(MichelineBinary.isPackedExpression(hex: payload))
    }
}
