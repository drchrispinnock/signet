import Foundation

/// Where the Buy button sends people: Mt Pelerin (Europe) or Transak (also the US). Each case
/// has its own URL builder, trusted hosts and ownership proof, if the provider takes one.
enum BuyProvider: String, CaseIterable, Identifiable, Sendable {
    case mtPelerin
    case transak

    static let key = "buyProvider"
    static let `default` = BuyProvider.mtPelerin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mtPelerin: "Mt Pelerin"
        case .transak: "Transak"
        }
    }

    /// Why the provider cannot be used yet (a key we have not been issued), or nil when it can.
    var configurationProblem: String? {
        switch self {
        case .mtPelerin: nil
        case .transak: Transak.configurationProblem
        }
    }

    /// Who it is and who it cannot serve, for Settings and the Buy sheet.
    var summary: String {
        switch self {
        case .mtPelerin: "Swiss on-ramp: bank transfer or card, tez delivered straight to your account. Not available to US persons."
        case .transak: "Global on-ramp: card, bank transfer, Apple Pay and more, US customers included (not Canada). Tez delivered straight to your account."
        }
    }

    var fiatCurrencies: [String] {
        switch self {
        case .mtPelerin: MtPelerin.fiatCurrencies
        case .transak: Transak.fiatCurrencies
        }
    }

    func defaultFiat(for locale: Locale = .current) -> String {
        switch self {
        case .mtPelerin: MtPelerin.defaultFiat(for: locale)
        case .transak: Transak.defaultFiat(for: locale)
        }
    }

    /// Hosts the embedded widget may use the camera for and navigate within.
    var trustedHosts: Set<String> {
        switch self {
        case .mtPelerin: ["widget.mtpelerin.com", "mtpelerin.com", "www.mtpelerin.com", "api.mtpelerin.com"]
        case .transak: ["global.transak.com", "global-stg.transak.com", "transak.com", "www.transak.com", "api.transak.com"]
        }
    }

    var trustedDomainSuffix: String {
        switch self {
        case .mtPelerin: ".mtpelerin.com"
        case .transak: ".transak.com"
        }
    }

    /// Whether the provider takes a signed proof of address ownership at all (so the sheet
    /// knows whether to ask for a password or a Ledger).
    var signsOwnership: Bool { ownershipPayload(code: "0000") != nil }

    /// Whether the provider wants a signed proof that we own the address (and what to sign).
    /// Transak has no such step: the address is locked in the widget instead.
    func ownershipPayload(code: String) -> String? {
        switch self {
        case .mtPelerin: MtPelerin.packedMessage(code: code)
        case .transak: nil
        }
    }

    func buyURL(address: Address, fiat: String, code: String, proof: SignedPayload?, embedded: Bool, locale: Locale = .current, dark: Bool) -> URL {
        switch self {
        case .mtPelerin:
            let validation = proof.map { MtPelerin.Validation(code: code, publicKey: $0.publicKey, signature: $0.signature) }
            return MtPelerin.buyURL(address: address, fiat: fiat, validation: validation, presentation: embedded ? .embedded : .browser, locale: locale, dark: dark)
        case .transak:
            return Transak.buyURL(address: address, fiat: fiat, dark: dark)
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
        case .transak:
            return embedded
        }
    }

    /// The provider chosen in Settings.
    static var current: BuyProvider {
        UserDefaults.standard.string(forKey: key).flatMap(BuyProvider.init(rawValue:)) ?? .default
    }
}
