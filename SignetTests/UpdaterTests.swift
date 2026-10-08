import Foundation
import Testing
@testable import Signet

/// The Sparkle keys in Info.plist: a wrong public key would make every update fail to verify,
/// and a non-https feed is refused by Sparkle outright.
struct UpdaterTests {
    @Test func feedURLIsHTTPSOnGitHubReleases() throws {
        let feed = try #require(Bundle.main.infoDictionary?["SUFeedURL"] as? String)
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        #expect(url.lastPathComponent == "appcast.xml")
    }

    @Test func publicKeyIs32BytesOfBase64() throws {
        let key = try #require(Bundle.main.infoDictionary?["SUPublicEDKey"] as? String)
        let bytes = try #require(Data(base64Encoded: key))
        #expect(bytes.count == 32)
    }

    @Test func automaticChecksAreOnByDefault() {
        #expect(Bundle.main.infoDictionary?["SUEnableAutomaticChecks"] as? Bool == true)
    }
}
