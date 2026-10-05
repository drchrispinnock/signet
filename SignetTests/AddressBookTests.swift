import Foundation
import Testing
@testable import Signet

struct Base58DecodeTests {
    @Test(arguments: ["tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N", "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton", "edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav"])
    func roundTripsThroughEncode(text: String) throws {
        let bytes = try #require(Base58.decode(text))
        #expect(Base58.encode(bytes) == text)
        #expect(Base58.checkDecode(text) != nil)
    }

    @Test func rejectsBadCharactersAndChecksums() {
        #expect(Base58.decode("0OIl") == nil)
        #expect(Base58.checkDecode("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73M") == nil)  // last char changed
    }
}

struct AddressValidationTests {
    @Test(arguments: [
        "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N",
        "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq",
        "tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5",
        "tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm",
        "tz5c9dMrWKhwBbSUPhxQRdwUnMMYHfqnpQRD",   // ML-DSA, which Taquito rejects
        "tz6JwJkwUGhWkPSJ2xfBaufqqP53FprApc9i",   // XMSS
        "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton",
    ])
    func acceptsEverySchemeAndContracts(address: String) {
        #expect(Address(address).isValidAccount, Comment(rawValue: address))
    }

    @Test(arguments: ["", "tz1", "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73M", "edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav", "sr1Ghq66tYK9y3r8CC1Tf8i8m5nxh8nTvZEf", " tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"])
    func rejectsOtherThings(address: String) {
        #expect(!Address(address).isValidAccount, Comment(rawValue: address))
    }
}

struct WatchOnlyStoreTests {
    @Test func addWatchOnlyWritesOnlyThePublicKeyHashesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-watch-\(UUID().uuidString)", isDirectory: true)
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: "mine", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkM", keyKind: .unencrypted), secretKey: "edskM")
        try store.addWatchOnly(Wallet(alias: "Captain Stake", address: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")))

        let wallets = try store.load()
        #expect(wallets.map(\.alias) == ["mine", "Captain Stake"])
        #expect(wallets[1].keyKind == KeyKind.none)
        #expect(wallets[1].publicKey == nil)
        #expect(try store.secretKey(for: wallets[1]) == nil)

        let publicKeys = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("public_keys"))) as? [[String: Any]]
        #expect(publicKeys?.count == 1)
        #expect(throws: TezosClientStore.StoreError.self) {
            try store.addWatchOnly(Wallet(alias: "mine", address: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")))
        }
    }
}

@MainActor
struct AddressBookViewModelTests {
    @Test func addsValidatesAndSelects() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.createWallet(alias: "Main", scheme: .tz1)

        try await model.addWatchOnlyWallet(alias: " Captain Stake ", address: " tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N ")
        let entry = try #require(model.selectedWallet)
        #expect(entry.alias == "Captain Stake")
        #expect(entry.keyKind == KeyKind.none)
        #expect(try store.load().count == 2)

        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.addWatchOnlyWallet(alias: "Bad", address: "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73M")
        }
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.addWatchOnlyWallet(alias: "Again", address: "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
        }
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.addWatchOnlyWallet(alias: "Main", address: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton")
        }
        #expect(model.wallets.count == 2)
    }
}

@MainActor
struct ProfileNameTests {
    @Test func profileNameComesFromTheChainServiceOrIsNil() async {
        let model = WalletViewModel(chain: MockChainService())
        #expect(await model.profileName(for: MockChainService.captainStake) == "Captain Stake")
        #expect(await model.profileName(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")) == nil)
    }
}
