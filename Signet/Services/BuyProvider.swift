import Foundation

/// Where the Buy button sends people: Mt Pelerin's widget inside the app, or Coinbase in the
/// browser with the address to paste (no partner agreement needed, and it serves the US).
/// Further widget providers slot in as cases with their own URL builder and trusted hosts.
enum BuyProvider: String, CaseIterable, Identifiable, Sendable {
    case mtPelerin
    case coinbase

    static let key = "buyProvider"
    static let `default` = BuyProvider.mtPelerin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mtPelerin: "Mt Pelerin"
        case .coinbase: "Coinbase"
        }
    }

    /// Whether the provider's page is shown inside Signet (a widget that takes the address) or
    /// opened in the browser, with Signet showing the address to paste.
    var usesWidget: Bool {
        switch self {
        case .mtPelerin: true
        case .coinbase: false
        }
    }

    /// The page to open in the browser for a provider that has no widget.
    var browserPage: URL? {
        switch self {
        case .mtPelerin: nil
        case .coinbase: URL(string: "https://www.coinbase.com/price/tezos")!
        }
    }

    /// Who it is and who it cannot serve, for Settings and the Buy sheet.
    var summary: String {
        switch self {
        case .mtPelerin: "Swiss on-ramp: bank transfer or card, tez delivered straight to your account. Not available to US persons."
        case .coinbase: "Buy tez on Coinbase in your browser, then send it to this account; Signet shows the address to paste. Available wherever Coinbase is, the US included."
        }
    }

    var fiatCurrencies: [String] {
        switch self {
        case .mtPelerin: MtPelerin.fiatCurrencies
        case .coinbase: []
        }
    }

    func defaultFiat(for locale: Locale = .current) -> String {
        switch self {
        case .mtPelerin: MtPelerin.defaultFiat(for: locale)
        case .coinbase: ""
        }
    }

    /// Hosts the embedded widget may use the camera for and navigate within.
    var trustedHosts: Set<String> {
        switch self {
        case .mtPelerin: ["widget.mtpelerin.com", "mtpelerin.com", "www.mtpelerin.com", "api.mtpelerin.com"]
        case .coinbase: []   // never embedded
        }
    }

    var trustedDomainSuffix: String {
        switch self {
        case .mtPelerin: ".mtpelerin.com"
        case .coinbase: ".invalid"
        }
    }

    /// Whether the provider wants a signed proof that we own the address (and what to sign).
    func ownershipPayload(code: String) -> String? {
        switch self {
        case .mtPelerin: MtPelerin.packedMessage(code: code)
        case .coinbase: nil
        }
    }

    func buyURL(address: Address, fiat: String, code: String, proof: SignedPayload?, embedded: Bool, locale: Locale = .current, dark: Bool) -> URL {
        switch self {
        case .mtPelerin:
            let validation = proof.map { MtPelerin.Validation(code: code, publicKey: $0.publicKey, signature: $0.signature) }
            return MtPelerin.buyURL(address: address, fiat: fiat, validation: validation, presentation: embedded ? .embedded : .browser, locale: locale, dark: dark)
        case .coinbase:
            return browserPage!
        }
    }

    /// The same URL as a plain browser link (used by "Open in browser instead").
    func browserURL(from embedded: URL) -> URL {
        switch self {
        case .mtPelerin:
            guard var components = URLComponents(url: embedded, resolvingAgainstBaseURL: false) else { return embedded }
            let query = components.percentEncodedQuery?.replacingOccurrences(of: "type=webview", with: "type=direct-link")
            components.percentEncodedQuery = query
            return components.url ?? embedded
        case .coinbase:
            return embedded
        }
    }

    /// The provider chosen in Settings.
    static var current: BuyProvider {
        UserDefaults.standard.string(forKey: key).flatMap(BuyProvider.init(rawValue:)) ?? .default
    }
}
