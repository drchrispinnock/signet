import Foundation

/// Where the Buy button sends people. One provider today; others (e.g. one that serves US
/// customers) slot in as further cases, each with its own URL builder.
enum BuyProvider: String, CaseIterable, Identifiable, Sendable {
    case mtPelerin

    static let key = "buyProvider"
    static let `default` = BuyProvider.mtPelerin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mtPelerin: "Mt Pelerin"
        }
    }

    /// Who it is and who it cannot serve, for Settings and the Buy sheet.
    var summary: String {
        switch self {
        case .mtPelerin: "Swiss on-ramp: bank transfer or card, tez delivered straight to your account. Not available to US persons."
        }
    }

    var fiatCurrencies: [String] {
        switch self {
        case .mtPelerin: MtPelerin.fiatCurrencies
        }
    }

    func defaultFiat(for locale: Locale = .current) -> String {
        switch self {
        case .mtPelerin: MtPelerin.defaultFiat(for: locale)
        }
    }

    /// Hosts the embedded widget may use the camera for and navigate within.
    var trustedHosts: Set<String> {
        switch self {
        case .mtPelerin: ["widget.mtpelerin.com", "mtpelerin.com", "www.mtpelerin.com", "api.mtpelerin.com"]
        }
    }

    var trustedDomainSuffix: String {
        switch self {
        case .mtPelerin: ".mtpelerin.com"
        }
    }

    /// Whether the provider wants a signed proof that we own the address (and what to sign).
    func ownershipPayload(code: String) -> String? {
        switch self {
        case .mtPelerin: MtPelerin.packedMessage(code: code)
        }
    }

    func buyURL(address: Address, fiat: String, code: String, proof: SignedPayload?, embedded: Bool, locale: Locale = .current, dark: Bool) -> URL {
        switch self {
        case .mtPelerin:
            let validation = proof.map { MtPelerin.Validation(code: code, publicKey: $0.publicKey, signature: $0.signature) }
            return MtPelerin.buyURL(address: address, fiat: fiat, validation: validation, presentation: embedded ? .embedded : .browser, locale: locale, dark: dark)
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
        }
    }

    /// The provider chosen in Settings.
    static var current: BuyProvider {
        UserDefaults.standard.string(forKey: key).flatMap(BuyProvider.init(rawValue:)) ?? .default
    }
}
