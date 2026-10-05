import AppKit
import Foundation
import Testing
@testable import Signet

struct AvatarTests {
    @Test func buildsTzktAvatarURLOnMainnetOnly() {
        let address = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
        #expect(Network.mainnet.avatarURL(for: address)?.absoluteString == "https://services.tzkt.io/v1/avatars/tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
        #expect(Network.shadownet.avatarURL(for: address) == nil)
    }

    /// Captain Stake's avatar is served as WebP; ImageIO must decode it.
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func captainStakeAvatarDecodes() async throws {
        let url = try #require(Network.mainnet.avatarURL(for: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")))
        let image = await ImageLoader().image(for: [url], maxPixelSize: 96)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
    }
}
