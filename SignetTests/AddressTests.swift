import Testing
@testable import Signet

struct AddressTests {
    @Test func shortensLongAddresses() {
        let address = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        #expect(address.shortened() == "tz1VSUr8wwN...Th8Cjcjb")
        #expect(address.shortened(prefix: 3, suffix: 3) == "tz1...cjb")
    }

    @Test func leavesShortStringsAlone() {
        #expect(Address("tz1abc").shortened() == "tz1abc")
        // 22 characters: exactly prefix + suffix + the ellipsis, so shortening would not save anything.
        #expect(Address("tz1abcdefghijklmnopqrs").shortened() == "tz1abcdefghijklmnopqrs")
    }

    @Test(arguments: [
        ("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", AddressScheme.tz1),
        ("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq", .tz2),
        ("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5", .tz3),
        ("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm", .tz4),
    ])
    func detectsScheme(address: String, expected: AddressScheme) {
        #expect(Address(address).scheme == expected)
    }

    @Test func contractsHaveNoScheme() {
        #expect(Address("KT1BRd2ka5q2cPRdXALtXD1QZ38CPam2j1ye").scheme == nil)
    }

    @Test func supportedSchemesIncludeMLDSAButNotXMSSYet() {
        #expect(AddressScheme.tz5.isSupported)
        #expect(AddressScheme.tz5.caveat != nil)
        #expect(AddressScheme.tz6.isSupported == false)
        #expect(AddressScheme.allCases.filter(\.isSupported) == [.tz1, .tz2, .tz3, .tz4, .tz5])
    }
}

struct AssetBalanceTests {
    @Test func formatsAmountWithSymbol() {
        let asset = AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: 4361.43)
        #expect(asset.formattedAmount.hasSuffix(" tz"))
        #expect(asset.formattedAmount.contains("4"))
        #expect(asset.formattedAmount.contains("43"))
    }
}
