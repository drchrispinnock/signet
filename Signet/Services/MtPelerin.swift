import Foundation

/// Mt Pelerin's hosted buy widget (https://developers.mtpelerin.com). Signet only builds the URL
/// and opens it in the browser; the purchase, KYC and payment all happen on Mt Pelerin's side and
/// the tez are delivered straight to the account's address.
enum MtPelerin {
    static let widgetURL = URL(string: "https://widget.mtpelerin.com/")!
    /// Activation key (`_ctkn`), if Mt Pelerin issues us one. Direct links work without it.
    static let activationKey: String? = nil
    /// Revenue-sharing code (`rfr`), none for now.
    static let referralCode: String? = nil
    static let network = "tezos_mainnet"
    static let supportedLanguages: Set<String> = ["en", "fr", "de", "it", "es", "pt"]
    static let fiatCurrencies = ["CHF", "EUR", "USD", "GBP"]

    /// Proof that we control the address, so the widget skips its own "sign this message" step.
    struct Validation: Equatable, Sendable {
        let code: String
        let publicKey: String
        let signature: String
    }

    /// A 4-digit code from 1000 to 9999; must differ per address.
    static func randomCode() -> String {
        String(Int.random(in: 1000...9999))
    }

    /// The text the user signs: Tezos wallets prefix message signatures so they can never be mistaken for an operation.
    static func message(code: String) -> String {
        "Tezos Signed Message: MtPelerin-\(code)"
    }

    /// The message packed as a Micheline string (`PACK "…"`): 0x05 (data), 0x01 (string), 4-byte
    /// big-endian length, UTF-8 bytes. This is what `signPayload` signs with no watermark.
    static func packedMessage(code: String) -> String {
        let text = Array(message(code: code).utf8)
        let length = UInt32(text.count)
        let bytes: [UInt8] = [0x05, 0x01, UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)] + text
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The `hash` parameter for Tezos: a six-line armored block carrying the message, public key and signature.
    static func armoredBlock(_ validation: Validation) -> String {
        [
            "-----BEGIN TEZOS SIGNED MESSAGE-----",
            message(code: validation.code),
            "-----BEGIN SIGNATURE-----",
            validation.publicKey,
            validation.signature,
            "-----END TEZOS SIGNED MESSAGE-----",
        ].joined(separator: "\n")
    }

    /// The best fiat to offer first: the locale's currency when Mt Pelerin takes it, else EUR.
    static func defaultFiat(for locale: Locale = .current) -> String {
        let code = locale.currency?.identifier.uppercased() ?? ""
        return fiatCurrencies.contains(code) ? code : "EUR"
    }

    static func language(for locale: Locale = .current) -> String {
        let code = locale.language.languageCode?.identifier.lowercased() ?? "en"
        return supportedLanguages.contains(code) ? code : "en"
    }

    /// How the widget is shown: inside Signet (`webview`) or as a link in the browser (`direct-link`).
    enum Presentation: String { case embedded = "webview", browser = "direct-link" }

    /// The buy widget for `address`, locked to tez on Tezos mainnet.
    static func buyURL(address: Address, fiat: String, validation: Validation?, presentation: Presentation = .embedded, locale: Locale = .current, dark: Bool = false) -> URL {
        var items: [URLQueryItem] = []
        if let activationKey { items.append(URLQueryItem(name: "_ctkn", value: activationKey)) }
        items += [
            URLQueryItem(name: "type", value: presentation.rawValue),
            URLQueryItem(name: "lang", value: language(for: locale)),
            URLQueryItem(name: "tab", value: "buy"),
            URLQueryItem(name: "tabs", value: "buy"),
            URLQueryItem(name: "bsc", value: fiat),
            URLQueryItem(name: "bdc", value: "XTZ"),
            URLQueryItem(name: "crys", value: "XTZ"),
            URLQueryItem(name: "dnet", value: network),
            URLQueryItem(name: "nets", value: network),
            URLQueryItem(name: "net", value: network),
            URLQueryItem(name: "addr", value: address.value),
        ]
        if let referralCode { items.append(URLQueryItem(name: "rfr", value: referralCode)) }
        if dark { items.append(URLQueryItem(name: "mode", value: "dark")) }
        if let validation {
            items.append(URLQueryItem(name: "code", value: validation.code))
            items.append(URLQueryItem(name: "hash", value: armoredBlock(validation)))
        }
        var components = URLComponents(url: widgetURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        // `+`, `/` and `=` appear in base58 signatures and the armored block; encode them strictly.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+/=&?:\n")
        components.percentEncodedQuery = items.map { item in
            "\(item.name)=\(item.value?.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        return components.url!
    }
}
