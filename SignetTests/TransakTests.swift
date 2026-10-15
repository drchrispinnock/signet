import Foundation
import Testing
@testable import Signet

struct TransakTests {
    @Test func buildsTheWidgetURLLockedToTezAndTheAddress() throws {
        let url = Transak.buyURL(address: Address("tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5"), fiat: "USD", apiKey: "key123", dark: true)
        #expect(url.host() == "global.transak.com" && url.scheme == "https")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["apiKey"] == "key123")
        #expect(query["cryptoCurrencyCode"] == "XTZ" && query["network"] == "mainnet" && query["productsAvailed"] == "BUY")
        #expect(query["walletAddress"] == "tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5" && query["disableWalletAddressForm"] == "true")
        #expect(query["defaultFiatCurrency"] == "USD" && query["colorMode"] == "DARK")
        #expect(query["referrerDomain"] == Transak.referrerDomain && !Transak.referrerDomain.isEmpty)

        let light = Transak.buyURL(address: Address("tz1abc"), fiat: "EUR", apiKey: nil)
        #expect(!light.absoluteString.contains("apiKey=") && light.absoluteString.contains("colorMode=LIGHT"))
    }

    @Test func providerCaseMatchesMtPelerinsShape() {
        let provider = BuyProvider.transak
        #expect(provider.title == "Transak" && provider.fiatCurrencies == Transak.fiatCurrencies)
        #expect(provider.ownershipPayload(code: "1234") == nil && !provider.signsOwnership && BuyProvider.mtPelerin.signsOwnership)
        #expect(BuyWebView.isTrusted(URL(string: "https://global.transak.com/?apiKey=x"), provider: .transak))
        #expect(BuyWebView.isTrusted(URL(string: "https://kyc.transak.com/"), provider: .transak))
        #expect(!BuyWebView.isTrusted(URL(string: "https://evil.example/transak.com"), provider: .transak))
        #expect(!BuyWebView.isTrusted(URL(string: "http://global.transak.com/"), provider: .transak))
        #expect(!BuyWebView.isTrusted(URL(string: "https://global.transak.com/"), provider: .mtPelerin))
        let url = provider.buyURL(address: Address("tz1abc"), fiat: "GBP", code: "1234", proof: nil, embedded: true, dark: false)
        #expect(provider.browserURL(from: url) == url)
        // Until Transak issues a key the provider says so; Mt Pelerin needs nothing.
        #expect((provider.configurationProblem == nil) == (Transak.apiKey != nil))
        #expect(BuyProvider.mtPelerin.configurationProblem == nil)
        #expect(BuyProvider.allCases == [.mtPelerin, .transak] && BuyProvider.default == .mtPelerin)
    }

    @Test func picksFiatFromTheLocaleWithUSDFallback() {
        #expect(Transak.defaultFiat(for: Locale(identifier: "en_GB")) == "GBP")
        #expect(Transak.defaultFiat(for: Locale(identifier: "de_CH")) == "CHF")
        #expect(Transak.defaultFiat(for: Locale(identifier: "ja_JP")) == "USD")
    }

    @Test @MainActor func viewModelDoesNotSignForTransak() async throws {
        let store = InMemoryWalletStore()
        try store.add(Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX", keyKind: .unencrypted), secretKey: "edskX")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        let url = try await model.buyURL(provider: .transak, fiat: "EUR", passphrase: nil)
        #expect(url.host() == "global.transak.com")
        #expect(!url.absoluteString.contains("edsigMock") && url.absoluteString.contains("walletAddress=tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
    }
}
