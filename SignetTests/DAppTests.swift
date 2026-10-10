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

    /// S03: the approval sheet must show what a contract call does. Standard token calls decode
    /// into effects; anything else is flagged as opaque; parameters are always carried verbatim.
    @Test func describesTokenCallsAndFlagsOpaqueOnes() async throws {
        let fa2Transfer = #"{"kind":"transaction","destination":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton","amount":"0","parameters":{"entrypoint":"transfer","value":[{"prim":"Pair","args":[{"string":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"},[{"prim":"Pair","args":[{"string":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},{"prim":"Pair","args":[{"int":"7"},{"int":"3"}]}]}]]}]}}"#
        let operators = #"{"kind":"transaction","destination":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton","amount":"0","parameters":{"entrypoint":"update_operators","value":[{"prim":"Left","args":[{"prim":"Pair","args":[{"string":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"},{"prim":"Pair","args":[{"string":"KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx"},{"int":"0"}]}]}]}]}}"#
        let fa12 = #"{"kind":"transaction","destination":"KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS","amount":"0","parameters":{"entrypoint":"approve","value":{"prim":"Pair","args":[{"string":"KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx"},{"int":"1000000"}]}}}"#
        let unknown = #"{"kind":"transaction","destination":"KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS","amount":"0","parameters":{"entrypoint":"collect","value":{"int":"1"}}}"#
        let plain = #"{"kind":"transaction","destination":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","amount":"2000000","fee":"100000000"}"#
        let described = try await TaquitoBridge.shared.call("octezConnectDescribe", ["[\(fa2Transfer),\(operators),\(fa12),\(unknown),\(plain)]"])
        let list = try #require(described.arrayValue).map(DAppConnectionManager.summary)
        #expect(list.count == 5)
        #expect(list[0].effects.map(\.text) == ["Send 3 of token 7 in KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton from tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb to tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"])
        #expect(list[0].effects[0].warning && !list[0].opaque)
        #expect(list[1].effects.map(\.text) == ["Allow KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx to move token 0 in KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton owned by tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"])
        #expect(list[2].effects.map(\.text) == ["Allow KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx to spend 1000000 units of the token KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS"])
        #expect(list[3].effects.isEmpty && list[3].opaque && list[3].entrypoint == "collect")
        #expect(list[3].parameters?.contains("\"int\": \"1\"") == true)
        #expect(list[4].effects.isEmpty && !list[4].opaque && list[4].amount == 2 && list[4].parameters == nil)
    }

    /// S03: fee, gas and storage come from the node's simulation, never from the dApp; a dApp
    /// asking for more fee is reported; a reveal in front is counted; totals add up.
    @Test func preparedBatchUsesTheNodesFiguresNotTheDApps() async throws {
        let ops = #"[{"kind":"transaction","destination":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","amount":"2000000","fee":"100000000","gas_limit":"999999","storage_limit":"99999"},{"kind":"delegation","delegate":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","fee":"100"}]"#
        let estimates = #"[{"suggestedFeeMutez":300,"gasLimit":200,"storageLimit":0,"burnFeeMutez":0},{"suggestedFeeMutez":500,"gasLimit":1500,"storageLimit":257,"burnFeeMutez":64250},{"suggestedFeeMutez":400,"gasLimit":1000,"storageLimit":0,"burnFeeMutez":0}]"#
        let r = try await TaquitoBridge.shared.call("octezConnectBuildPrepared", [ops, estimates])
        #expect(r["totalAmountMutez"] == .string("2000000"))
        #expect(r["totalFeeMutez"] == .string("1200"))        // reveal 300 + 500 + 400
        #expect(r["totalBurnMutez"] == .string("64250"))
        #expect(r["totalDebitMutez"] == .string("2065450"))
        #expect(r["reveal"]?["feeMutez"] == .string("300"))
        let list = try #require(r["operations"]?.arrayValue).map(DAppConnectionManager.summary)
        #expect(list[0].fee == Decimal(string: "0.0005") && list[0].requestedFee == 100)
        #expect(list[1].fee == Decimal(string: "0.0004") && list[1].requestedFee == nil)
        let prepared = try #require(r["prepared"]?.stringValue)
        let params = try #require(try JSONSerialization.jsonObject(with: Data(prepared.utf8)) as? [[String: Any]])
        #expect(params[0]["fee"] as? Int == 500 && params[0]["gasLimit"] as? Int == 1500 && params[0]["storageLimit"] as? Int == 257)
        #expect(params[1]["fee"] as? Int == 400)
        // Without a reveal, counts must match exactly.
        await #expect(throws: (any Error).self) { try await TaquitoBridge.shared.call("octezConnectBuildPrepared", [ops, "[]"]) }
        // Executing anything that was not prepared is refused before a signer is even looked at.
        await #expect(throws: (any Error).self) { try await TaquitoBridge.shared.call("octezConnectExecute", ["http://127.0.0.1:1", "{}", ops]) }
    }

    @Test func approvalUsesTheActualRevealAndWarnsAboutDefaultContractCalls() async throws {
        let ops = #"[{"kind":"transaction","destination":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton","amount":"0"}]"#
        let estimates = #"[{"suggestedFeeMutez":300,"gasLimit":200,"storageLimit":0,"burnFeeMutez":0},{"suggestedFeeMutez":500,"gasLimit":1500,"storageLimit":0,"burnFeeMutez":0}]"#
        let operation = #"{"branch":"fixture","protocol":"fixture","contents":[{"kind":"reveal","fee":"999","gas_limit":"10000","storage_limit":"0"},{"kind":"transaction","fee":"500","gas_limit":"1500","storage_limit":"0"}]}"#
        let r = try await TaquitoBridge.shared.call("octezConnectBuildPrepared", [ops, estimates, operation])
        #expect(r["reveal"]?["feeMutez"] == .string("999"))
        #expect(r["totalFeeMutez"] == .string("1499"))
        #expect(r["totalDebitMutez"] == .string("1499"))
        #expect(r["prepared"]?.stringValue.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) } is [String: Any])
        let summary = DAppConnectionManager.summary(try #require(r["operations"]?.arrayValue?.first))
        #expect(summary.opaque && summary.entrypoint == "default")
        #expect(summary.parameters?.contains("Unit") == true)
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

/// Live, on Shadownet: a dApp batch (transfer + delegation) from a faucet-funded key is simulated
/// with a read-only signer, then the prepared batch is signed and sent exactly as prepared.
struct ShadownetDAppPrepareTests {
    @Test(.tags(.network), .timeLimit(.minutes(5)))
    func preparesThenExecutesABatchAsPrepared() async throws {
        let chain = TaquitoChainService(network: .shadownet)
        let rpc = Network.shadownet.rpcURL
        let key = try await KeyGenerator().generate(scheme: .tz1)
        let recipient = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "dapp", address: Address(key.address), scheme: .tz1, publicKey: key.publicKey, keyKind: .unencrypted)
        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 10)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await chain.tezBalance(for: wallet.address), b.spendable >= 10 { funded = true; break } }
        #expect(funded)

        let baker = try #require((try JSONSerialization.jsonObject(with: try await URLSession.shared.data(from: rpc.appendingPathComponent("chains/main/blocks/head/context/delegates").appending(queryItems: [URLQueryItem(name: "active", value: "true")])).0) as? [String])?.first)
        let ops = #"[{"kind":"transaction","destination":"\#(recipient.address)","amount":"1000000","fee":"50000000"},{"kind":"delegation","delegate":"\#(baker)"}]"#
        let r = try await TaquitoBridge.shared.call("octezConnectPrepare", [rpc.absoluteString, key.address, key.publicKey, ops])
        // A fresh account reveals first; the dApp's 50 tez fee is replaced by the estimate.
        #expect(r["reveal"]?["feeMutez"]?.stringValue.flatMap(Int.init) ?? 0 > 0)
        let list = try #require(r["operations"]?.arrayValue).map(DAppConnectionManager.summary)
        #expect(list.count == 2 && list[0].requestedFee == 50 && (list[0].fee ?? 0) < 1)
        let totalDebit = try #require(Mutez.toTez(r["totalDebitMutez"]?.stringValue))
        #expect(totalDebit > 1 && totalDebit < 2)
        let prepared = try #require(r["prepared"]?.stringValue)

        let signer = SigningKey.secret(key.secretKey, passphrase: nil, address: wallet.address)
        let sent = try await TaquitoBridge.shared.call("octezConnectExecute", [rpc.absoluteString, signer.bridgeSpec, prepared])
        let hash = try #require(sent["hash"]?.stringValue)
        print("dApp batch \(hash)")
        _ = try await chain.waitForConfirmation(of: hash)
        #expect(try await chain.tezBalance(for: Address(recipient.address)).spendable == 1)
        #expect(try await chain.delegateInfo(for: wallet.address).delegate?.value == baker)
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
        let spec = SigningKey.secret(material.secretKey, passphrase: nil, address: Address(material.address)).bridgeSpec
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
