import Foundation

/// The link a dApp's wallet list opens for a desktop wallet: `<scheme>://?type=tzip10&data=<code>`.
/// Beacon and Octez Connect build it as `deepLink + "?type=tzip10&data=" + pairingPayload`.
enum DAppPairingLink {
    static let scheme = "signet"
    static let type = "tzip10"

    /// The pairing code carried by `url`, or `nil` when it is not a TZIP-10 pairing link.
    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard value("type")?.lowercased() == type, let data = value("data"), !data.isEmpty else { return nil }
        return data
    }

    /// The link for a pairing code, for tests and for telling dApp authors what to open.
    static func url(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.queryItems = [URLQueryItem(name: "type", value: type), URLQueryItem(name: "data", value: code)]
        return components.url!
    }
}
