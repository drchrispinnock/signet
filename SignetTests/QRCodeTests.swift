import AppKit
import Testing
@testable import Signet

struct QRCodeTests {
    @Test func encodesAnAddressThatScansBack() throws {
        let address = "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"
        let image = try #require(QRCode.image(for: address, size: 240))
        #expect(image.size.width == 240)
        #expect(QRCode.decode(image) == address)
    }
}
