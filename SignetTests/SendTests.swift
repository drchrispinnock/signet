import Foundation
import Testing
@testable import Signet

@MainActor
struct SendViewModelTests {
    static let me = Wallet(alias: "Main", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkME", keyKind: .unencrypted)
    static let savings = Wallet(alias: "Savings", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkSAV", keyKind: .unencrypted)
    static let alice = Wallet(alias: "Alice", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))

    private func makeModel(spendable: Decimal? = 100) -> SendViewModel {
        SendViewModel(sender: Self.me, wallets: [Self.me, Self.savings, Self.alice], chain: MockChainService(),
                      spendable: spendable, signerProvider: { w, _ in .secret("edskSECRET", passphrase: nil, address: w.address) })
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(500)) }

    @Test func suggestsOurOtherWalletsAndFiltersByText() {
        let send = makeModel()
        #expect(send.suggestions.map(\.alias) == ["Savings", "Alice"])  // never the sender itself
        send.recipientText = "ali"
        #expect(send.suggestions.map(\.alias) == ["Alice"])
        send.recipientText = "tz2"
        #expect(send.suggestions.map(\.alias) == ["Savings"])
    }

    @Test func recognisesOurOwnEntriesAsVerified() async {
        let send = makeModel()
        send.choose(Self.alice)
        await settle()
        let recipient = try! #require(send.recipient)
        #expect(recipient.isVerified)
        #expect(recipient.displayName == "Alice")
    }

    @Test func unknownAddressGetsProfileNameButIsNotVerified() async {
        let send = makeModel()
        send.recipientText = MockChainService.captainStake.value
        await settle()
        let recipient = try! #require(send.recipient)
        #expect(!recipient.isVerified)
        #expect(recipient.displayName == "Captain Stake")
        #expect(recipient.domains == ["captstake.tez"])
    }

    @Test func resolvesTezNames() async {
        let send = makeModel()
        send.recipientText = "CaptStake.tez"
        await settle()
        #expect(send.recipient?.address == MockChainService.captainStake)
        #expect(send.recipient?.isVerified == false)
    }

    @Test func rejectsGarbageAmountsAndOverspend() async {
        let send = makeModel(spendable: 5)
        send.choose(Self.alice)
        await settle()
        send.amountText = "abc"
        #expect(send.amount == nil)
        #expect(!send.canProceed)

        send.amountText = "10"
        await send.proceedToConfirm()
        #expect(send.step == .compose)
        #expect(send.errorMessage?.contains("Not enough") == true)

        send.useMaximum()
        #expect(send.amount == Decimal(string: "4.999"))
    }

    @Test func confirmsEstimatesSendsAndConfirms() async {
        let send = makeModel()
        send.choose(Self.alice)
        await settle()
        send.amountText = "1,5"  // comma decimal separator is accepted
        #expect(send.amount == Decimal(string: "1.5"))

        await send.proceedToConfirm()
        #expect(send.step == .confirm)
        let estimate = try! #require(send.estimate)
        #expect(estimate.burn > 0)  // Alice has never held tez in the mock
        #expect(estimate.total == Decimal(string: "1.5")! + estimate.fee + estimate.burn)

        await send.send()
        guard case .confirmed(let hash, let level) = send.step else { Issue.record("expected confirmed, got \(send.step)"); return }
        #expect(hash.hasPrefix("oo"))
        #expect(level == 9_000_000)
    }

    @Test func refusesToSendToItself() async {
        let send = makeModel()
        send.recipientText = Self.me.address.value
        await settle()
        send.amountText = "1"
        await send.proceedToConfirm()
        #expect(send.step == .compose)
        #expect(send.errorMessage == SendViewModel.SendError.sendingToSelf.localizedDescription)
    }
}

struct TransferHelpersTests {
    @Test func mutezConversionTruncatesBelowOneMutez() {
        #expect(Mutez.fromTez(Decimal(string: "1.5")!) == "1500000")
        #expect(Mutez.fromTez(Decimal(string: "0.0000019")!) == "1")
        #expect(Mutez.toTez("22702455018") == Decimal(string: "22702.455018"))
    }

    @Test func profileParsingPrefersTzProfilesAlias() throws {
        let json = """
        {"alias":"TzKT Name","extras":{"profile":{"kind":"person","alias":"Captain Stake","twitter":"captstake","description":"Staking."}}}
        """.data(using: .utf8)!
        let profile = try #require(TzKTService.profile(from: json))
        #expect(profile.name == "Captain Stake")
        #expect(profile.twitter == "captstake")
        #expect(TzKTService.profile(from: Data("{\"address\":\"tz1x\"}".utf8)) == nil)
        #expect(TzKTService.profile(from: Data("{\"alias\":\"Only TzKT\"}".utf8))?.name == "Only TzKT")
    }

    /// Estimation needs no secret: Captain Stake's public key is enough for the node to simulate.
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func estimatesAMainnetTransferWithoutASecretKey() async throws {
        let captain = Wallet(alias: "Captain Stake", address: MockChainService.captainStake,
                             publicKey: "edpku5dNSxAs5R7g91zm9mDcfYVGsM4gCniaDSPVwYPt3xtszyzgJD", keyKind: .unencrypted)
        let estimate = try await TaquitoChainService(network: .mainnet)
            .estimateTransfer(from: captain, to: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), amount: 1)
        #expect(estimate.fee > 0)
        #expect(estimate.fee < Decimal(string: "0.01")!)
        #expect(estimate.total == 1 + estimate.fee + estimate.burn)
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func forwardDomainLookupFindsCaptainStake() async throws {
        let service = TezosDomainsService(endpoint: Network.mainnet.tezosDomainsURL!)
        #expect(try await service.resolve(name: "captstake.tez") == MockChainService.captainStake)
        #expect(try await service.resolve(name: "this-name-should-not-exist-\(UUID().uuidString.prefix(8)).tez") == nil)
    }
}

/// S14 and S15: a send carries the approved limits, and a lost reply is never retried as a new payment.
@MainActor
struct SendOutcomeTests {
    /// A chain whose node loses the injection reply once and only sees the operation after a rebroadcast.
    final class LossyChain: TestChainService, @unchecked Sendable {
        var sends: [OperationLimits] = []
        var rebroadcasts = 0
        var seen = false
        func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 100, staked: 0) }
        func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
            sends.append(limits)
            return SentOperation(hash: "ooLost", injected: false, signedBytes: "abcd")
        }
        func rebroadcast(_ sent: SentOperation) async throws -> SentOperation {
            rebroadcasts += 1
            seen = true
            return SentOperation(hash: sent.hash, injected: true, signedBytes: sent.signedBytes)
        }
        func waitForConfirmation(of operationHash: String) async throws -> Int {
            guard seen else { throw ChainError.accountNotOnChain(Address("tz1")) }
            return 42
        }
    }

    @Test func lostReplyKeepsTheHashAndResendsTheSameBytes() async throws {
        let chain = LossyChain()
        let send = SendViewModel(sender: SendViewModelTests.me, wallets: [SendViewModelTests.alice], chain: chain, spendable: 100,
                                 signerProvider: { w, _ in .secret("edskSECRET", passphrase: nil, address: w.address) })
        send.choose(SendViewModelTests.alice)
        try await Task.sleep(for: .milliseconds(300))
        send.amountText = "1"
        await send.proceedToConfirm()
        #expect(send.step == .confirm)
        await send.send()
        // The estimate's limits went with the operation (S14).
        #expect(chain.sends == [OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)])
        // The outcome is unknown: the hash is known, nothing goes back to the confirm step.
        #expect(send.step == .unknown(hash: "ooLost"))
        #expect(send.errorMessage?.contains("ooLost") == true)
        await send.rebroadcast()
        #expect(chain.rebroadcasts == 1 && chain.sends.count == 1)
        #expect(send.step == .confirmed(hash: "ooLost", level: 42))
    }

    @Test func refusesToSendWithoutAnEstimate() async throws {
        struct NoLimits: TestChainService {
            func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 100, staked: 0) }
            func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate {
                TransferEstimate(fee: 0.001, burn: 0, total: amount + 0.001, gasLimit: 0, storageLimit: 0)
            }
            func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
                Issue.record("sent without limits"); return SentOperation(hash: "x")
            }
        }
        let send = SendViewModel(sender: SendViewModelTests.me, wallets: [SendViewModelTests.alice], chain: NoLimits(), spendable: 100,
                                 signerProvider: { w, _ in .secret("edskSECRET", passphrase: nil, address: w.address) })
        send.choose(SendViewModelTests.alice)
        try await Task.sleep(for: .milliseconds(300))
        send.amountText = "1"
        await send.proceedToConfirm()
        await send.send()
        #expect(send.step == .confirm)
        #expect(send.errorMessage == SendViewModel.SendError.notEstimated.localizedDescription)
    }
}

/// S20: numbers from the node or the bridge never reach a trapping conversion.
struct CheckedNumberTests {
    @Test func intValueRefusesWhatIntCannotHold() {
        #expect(JSONValue.number(42).intValue == 42)
        #expect(JSONValue.number(-3).intValue == -3)
        #expect(JSONValue.string("17").intValue == 17)
        #expect(JSONValue.number(1.5).intValue == nil)
        #expect(JSONValue.number(.nan).intValue == nil)
        #expect(JSONValue.number(.infinity).intValue == nil)
        #expect(JSONValue.number(-.infinity).intValue == nil)
        #expect(JSONValue.number(1e300).intValue == nil)
        #expect(JSONValue.number(9_007_199_254_740_994).intValue == nil)
        #expect(JSONValue.string("12.0").intValue == nil)
        #expect(JSONValue.bool(true).intValue == nil)
    }

    @Test func estimatesWithBadFiguresAreErrorsNotZeroes() throws {
        let good = JSONValue.object(["feeMutez": .string("500"), "burnMutez": .string("0"), "gasLimit": .number(1500), "storageLimit": .number(0),
                                     "limits": .object(["feeMutez": .string("500"), "gasLimit": .number(1500), "storageLimit": .number(0)])])
        let estimate = try TaquitoChainService.estimate(from: good, amount: 1)
        #expect(estimate.fee == Decimal(string: "0.0005") && estimate.limits?.gasLimit == 1500 && estimate.total == Decimal(string: "1.0005"))
        for bad in [
            JSONValue.object(["feeMutez": .string("500"), "burnMutez": .string("0"), "gasLimit": .number(.nan), "storageLimit": .number(0), "limits": .object(["feeMutez": .string("500"), "gasLimit": .number(1500), "storageLimit": .number(0)])]),
            JSONValue.object(["feeMutez": .string("500"), "burnMutez": .string("0"), "gasLimit": .number(1500), "storageLimit": .number(0)]),
            JSONValue.object(["feeMutez": .string("500"), "burnMutez": .string("0"), "gasLimit": .number(1500), "storageLimit": .number(0), "limits": .object(["feeMutez": .string("-5"), "gasLimit": .number(1500), "storageLimit": .number(0)])]),
            JSONValue.object(["feeMutez": .string("500"), "burnMutez": .string("0"), "gasLimit": .number(1500), "storageLimit": .number(0), "limits": .object(["feeMutez": .string("500"), "gasLimit": .number(1e20), "storageLimit": .number(0)])]),
        ] {
            #expect(throws: (any Error).self) { try TaquitoChainService.estimate(from: bad) }
        }
        let info = JSONValue.object(["address": .string("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi"), "isGenericMultisig": .bool(true), "scriptHash": .string("expr"), "counter": .string("nope"), "threshold": .string("2"), "keys": .array([])])
        #expect(throws: (any Error).self) { try BridgeMultisigService.info(from: info) }
    }
}
