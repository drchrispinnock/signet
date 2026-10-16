import Foundation
import Testing
@testable import Signet

struct MtPelerinTests {
    @Test func packsTheMessageLikeTheDocs() {
        // Test vector from developers.mtpelerin.com (code 1234).
        #expect(MtPelerin.packedMessage(code: "1234") == "05010000002454657a6f73205369676e6564204d6573736167653a204d7450656c6572696e2d31323334")
        #expect(MtPelerin.message(code: "4321") == "Tezos Signed Message: MtPelerin-4321")
        let code = MtPelerin.randomCode()
        #expect(code.count == 4 && Int(code)! >= 1000)
    }

    @Test func buildsTheArmoredBlockAndURL() throws {
        let validation = MtPelerin.Validation(code: "1234", publicKey: "edpkus9ckWtwxNi7NqZqGT2bo1VGxyRkCvaV5zkms7rkeWUV532PhU",
                                              signature: "edsigtzYwqm72h1cBbWLSMUVEu3t7bUT2RqBMppLdtVGH3VqKhppz96YE6yQSS4GKKkB6nHCRXmdiukHkw3Puy5Zd5b2rvaosRG")
        let block = MtPelerin.armoredBlock(validation)
        #expect(block.hasPrefix("-----BEGIN TEZOS SIGNED MESSAGE-----\nTezos Signed Message: MtPelerin-1234\n-----BEGIN SIGNATURE-----\nedpkus9"))
        #expect(block.hasSuffix("-----END TEZOS SIGNED MESSAGE-----"))
        #expect(block.components(separatedBy: "\n").count == 6)

        let url = MtPelerin.buyURL(address: Address("tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5"), fiat: "CHF", validation: validation, locale: Locale(identifier: "fr_CH"))
        let query = url.absoluteString
        #expect(url.host() == "widget.mtpelerin.com")
        #expect(query.contains("bdc=XTZ") && query.contains("net=tezos_mainnet") && query.contains("dnet=tezos_mainnet"))
        #expect(query.contains("addr=tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5"))
        #expect(query.contains("bsc=CHF") && query.contains("lang=fr") && query.contains("code=1234"))
        // The armored block is percent-encoded the way the docs show it.
        #expect(query.contains("hash=-----BEGIN%20TEZOS%20SIGNED%20MESSAGE-----%0ATezos%20Signed%20Message%3A%20MtPelerin-1234%0A"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "hash" }?.value == block)

        let plain = MtPelerin.buyURL(address: Address("tz1abc"), fiat: "EUR", validation: nil, presentation: .browser, locale: Locale(identifier: "xx"))
        #expect(!plain.absoluteString.contains("hash=") && plain.absoluteString.contains("lang=en") && plain.absoluteString.contains("type=direct-link"))
        #expect(query.contains("type=webview"))
        #expect(BuyWebView.isTrusted(URL(string: "https://widget.mtpelerin.com/x"), provider: .mtPelerin) && BuyWebView.isTrusted(URL(string: "https://kyc.mtpelerin.com/"), provider: .mtPelerin) && !BuyWebView.isTrusted(URL(string: "https://evil.example/mtpelerin.com"), provider: .mtPelerin))
        #expect(BuyProvider.mtPelerin.browserURL(from: url).absoluteString.contains("type=direct-link"))
        // The remembered choice is whatever the user last picked in the Buy sheet (the test host
        // shares the app's defaults), so only the fallback is pinned: unknown or unset means Mt Pelerin.
        #expect(BuyProvider.allCases.contains(BuyProvider.current))
        #expect(BuyProvider(rawValue: "nowhere") == nil && BuyProvider.default == .mtPelerin)
    }

    @Test func picksFiatAndLanguageFromTheLocale() {
        #expect(MtPelerin.defaultFiat(for: Locale(identifier: "en_GB")) == "GBP")
        #expect(MtPelerin.defaultFiat(for: Locale(identifier: "ja_JP")) == "EUR")
        #expect(MtPelerin.language(for: Locale(identifier: "de_DE")) == "de")
        #expect(MtPelerin.language(for: Locale(identifier: "nl_NL")) == "en")
    }

    @Test @MainActor func viewModelSignsWhenItCan() async throws {
        let store = InMemoryWalletStore()
        try store.add(Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX", keyKind: .unencrypted), secretKey: "edskX")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        let url = try await model.buyURL(provider: .mtPelerin, fiat: "EUR", passphrase: nil)
        #expect(url.absoluteString.contains("hash=") && url.absoluteString.contains("edsigMock"))

        let watch = WalletViewModel(wallets: [Wallet(alias: "w", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .none)], chain: MockChainService())
        let plain = try await watch.buyURL(provider: .mtPelerin, fiat: "EUR", passphrase: nil)
        #expect(!plain.absoluteString.contains("hash="))
    }

    /// Live: a fresh tz1 key signs the packed message through the bridge and the signature verifies.
    @Test func bridgeSignsThePackedMessage() async throws {
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let chain = TaquitoChainService(network: .mainnet)
        let signed = try await chain.signPayload(signer: .secret(material.secretKey, passphrase: nil, address: Address(material.address)), payloadHex: MtPelerin.packedMessage(code: "1234"))
        #expect(signed.publicKey == material.publicKey)
        #expect(signed.signature.hasPrefix("edsig"))
        let verified = try await TaquitoBridge.shared.call("verifySignature", [MtPelerin.packedMessage(code: "1234"), signed.publicKey, signed.signature])
        #expect(verified == .bool(true))
    }
}

struct CoinbaseProviderTests {
    @Test func coinbaseIsABrowserHandOffNotAWidget() async throws {
        let provider = BuyProvider.coinbase
        #expect(!provider.usesWidget && BuyProvider.mtPelerin.usesWidget)
        #expect(provider.browserPage?.host() == "www.coinbase.com" && BuyProvider.mtPelerin.browserPage == nil)
        #expect(provider.ownershipPayload(code: "1234") == nil && provider.fiatCurrencies.isEmpty)
        // Nothing of Coinbase's is ever trusted inside the embedded web view.
        #expect(!BuyWebView.isTrusted(URL(string: "https://www.coinbase.com/"), provider: .coinbase))
        #expect(BuyProvider.allCases == [.mtPelerin, .coinbase, .kraken] && BuyProvider.default == .mtPelerin)
        let url = provider.buyURL(address: Address("tz1abc"), fiat: "", code: "0000", proof: nil, embedded: true, dark: false)
        #expect(url == provider.browserPage && provider.browserURL(from: url) == url)
    }

    @Test func krakenIsABrowserHandOffLikeCoinbase() async throws {
        let provider = BuyProvider.kraken
        #expect(!provider.usesWidget && provider.browserPage?.host() == "www.kraken.com")
        #expect(provider.ownershipPayload(code: "1234") == nil && provider.fiatCurrencies.isEmpty && provider.defaultFiat() == "")
        #expect(provider.trustedHosts.isEmpty && !BuyWebView.isTrusted(URL(string: "https://www.kraken.com/"), provider: .kraken))
        let url = provider.buyURL(address: Address("tz1abc"), fiat: "", code: "0000", proof: nil, embedded: false, dark: true)
        #expect(url == provider.browserPage && provider.browserURL(from: url) == url)
        #expect(BuyProvider.choices == "Mt Pelerin, Coinbase or Kraken")
        // Every exchange hand-off opens over HTTPS and nothing else.
        for exchange in BuyProvider.allCases where !exchange.usesWidget {
            #expect(exchange.browserPage?.scheme == "https")
        }
    }
}
