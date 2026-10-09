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
