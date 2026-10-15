import Foundation

/// Transak's hosted buy widget (https://docs.transak.com), the on-ramp that also serves US
/// customers. As with Mt Pelerin, Signet only builds the URL and shows the page; the purchase,
/// identity checks and payment are Transak's and the tez land in the account's address.
///
/// Transak issues partners an API key in its dashboard and the widget does not open without one
/// (`apiKey`). Since 2025 Transak also prefers a one-time session URL made by the partner's own
/// server (`POST /api/v2/auth/session` with a partner access token) over parameters in the URL;
/// Signet has no server, so it builds the direct URL, which Transak calls deprecated but still
/// honours. Should that stop working, a tiny backend that mints session URLs is the way forward.
enum Transak {
    static let widgetURL = URL(string: "https://global.transak.com/")!
    static let stagingWidgetURL = URL(string: "https://global-stg.transak.com/")!
    /// Partner API key from the Transak dashboard. Nil until we are issued one.
    static let apiKey: String? = nil
    /// Who is embedding the widget: the app's bundle identifier, as Transak asks of native apps.
    static let referrerDomain = Bundle.main.bundleIdentifier ?? "org.tezos.signet"
    /// Transak's name for the Tezos network and for tez (`XTZmainnet` in its currency list).
    static let network = "mainnet"
    static let cryptoCurrency = "XTZ"
    /// Offered first; the widget lets the customer pick any other fiat Transak takes.
    static let fiatCurrencies = ["USD", "EUR", "GBP", "CHF", "AUD"]

    /// Why the provider cannot be used yet, or nil when it can.
    static var configurationProblem: String? {
        apiKey == nil ? "Transak needs a partner API key before its widget will open. Signet has not been issued one yet." : nil
    }

    /// The locale's currency when Transak takes it, else USD.
    static func defaultFiat(for locale: Locale = .current) -> String {
        let code = locale.currency?.identifier.uppercased() ?? ""
        return fiatCurrencies.contains(code) ? code : "USD"
    }

    /// The buy widget for `address`, locked to tez on Tezos mainnet with the address not editable.
    static func buyURL(address: Address, fiat: String, apiKey: String? = Transak.apiKey, dark: Bool = false) -> URL {
        var items: [URLQueryItem] = []
        if let apiKey { items.append(URLQueryItem(name: "apiKey", value: apiKey)) }
        items += [
            URLQueryItem(name: "referrerDomain", value: referrerDomain),
            URLQueryItem(name: "productsAvailed", value: "BUY"),
            URLQueryItem(name: "cryptoCurrencyCode", value: cryptoCurrency),
            URLQueryItem(name: "network", value: network),
            URLQueryItem(name: "walletAddress", value: address.value),
            URLQueryItem(name: "disableWalletAddressForm", value: "true"),
            URLQueryItem(name: "defaultFiatCurrency", value: fiat),
            URLQueryItem(name: "exchangeScreenTitle", value: "Buy tez"),
            URLQueryItem(name: "colorMode", value: dark ? "DARK" : "LIGHT"),
        ]
        var components = URLComponents(url: widgetURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url!
    }
}
