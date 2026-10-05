import AppKit
import Foundation
import Testing
@testable import Signet

struct IPFSTests {
    @Test(arguments: [
        ("ipfs://QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc", "https://ipfs.filebase.io/ipfs/QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"),
        ("ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP/?fxhash=opPk", "https://ipfs.filebase.io/ipfs/QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP/?fxhash=opPk"),
        ("https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9", "https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9"),
    ])
    func rewritesToGateway(uri: String, expected: String) {
        #expect(IPFS.httpURL(for: uri)?.absoluteString == expected)
    }

    @Test func offersEveryGatewayForIPFSButOnlyOneForHTTPS() {
        let ipfs = IPFS.candidateURLs(for: "ipfs://QmCid")
        #expect(ipfs.count == IPFS.gateways.count)
        #expect(ipfs.map(\.host) == IPFS.gateways.map(\.host))
        #expect(IPFS.candidateURLs(for: "https://example.com/x.png").count == 1)
    }

    @Test func rejectsOtherSchemes() {
        #expect(IPFS.httpURL(for: "data:image/png;base64,AAAA") == nil)
        #expect(IPFS.httpURL(for: "") == nil)
    }
}

struct NFTClassificationTests {
    static let fixture = """
    [
      { "balance": "1", "token": { "contract": { "address": "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton" }, "tokenId": "634799", "standard": "fa2",
        "metadata": { "name": "United in Baking", "symbol": "OBJKT", "decimals": "0",
                      "thumbnailUri": "ipfs://QmThumb", "displayUri": "ipfs://QmDisplay", "artifactUri": "ipfs://QmArt",
                      "formats": [ { "uri": "ipfs://QmArt", "mimeType": "image/jpeg" } ] } } },
      { "balance": "20", "token": { "contract": { "address": "KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx" }, "tokenId": "0", "standard": "fa2",
        "metadata": { "name": "Captain Stake", "decimals": "0", "artifactUri": "ipfs://QmOnlyArt",
                      "formats": [ { "uri": "ipfs://QmOnlyArt", "mimeType": "image/png" } ] } } },
      { "balance": "1", "token": { "contract": { "address": "KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS" }, "tokenId": "143032", "standard": "fa2",
        "metadata": { "name": "captstake.tez", "decimals": "0", "symbol": "TD" } } },
      { "balance": "30000000000", "token": { "contract": { "address": "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF" }, "tokenId": "0", "standard": "fa2",
        "metadata": { "name": "Aubergine", "decimals": "6", "symbol": "GINE", "thumbnailUri": "https://gateway.pinata.cloud/ipfs/Qmaf8" } } },
      { "balance": "1", "token": { "contract": { "address": "KT1video" }, "tokenId": "7", "standard": "fa2",
        "metadata": { "name": "Clip", "decimals": "0", "artifactUri": "ipfs://QmMovie",
                      "formats": [ { "uri": "ipfs://QmMovie", "mimeType": "video/mp4" } ] } } }
    ]
    """.data(using: .utf8)!

    @Test func picksNFTsAndBestImages() throws {
        let rows = try TzKTService.decode(Self.fixture)
        #expect(rows.count == 5)
        let nfts = TzKTService.nfts(from: rows)

        #expect(nfts.map(\.name) == ["United in Baking", "Captain Stake"])
        #expect(nfts[0].id == "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton:634799")
        // displayUri beats thumbnailUri and artifactUri.
        #expect(nfts[0].thumbnailURL?.absoluteString == "https://ipfs.filebase.io/ipfs/QmDisplay")
        #expect(nfts[0].imageURLs.count == IPFS.gateways.count)
        // An image artifact is acceptable when there is nothing else.
        #expect(nfts[1].thumbnailURL?.absoluteString == "https://ipfs.filebase.io/ipfs/QmOnlyArt")
        #expect(nfts[1].balance == 20)
        // Fungible tokens, image-less tokens and video-only artifacts are not shown.
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func captainStakeHasNFTsWithImages() async throws {
        let service = TzKTService(baseURL: Network.mainnet.tzktURL!)
        let nfts = try await service.nfts(for: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"))
        #expect(nfts.count >= 1)
        #expect(nfts.allSatisfy { $0.thumbnailURL?.scheme == "https" })
        #expect(nfts.contains { $0.name == "Captain Stake" })
    }
}

struct ImageLoaderTests {
    @Test func downsamplesToRequestedSize() throws {
        // A 1000x500 red PNG made in memory.
        let image = NSImage(size: NSSize(width: 1000, height: 500), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))

        let small = try #require(ImageLoader.downsample(png, maxPixelSize: 200))
        #expect(small.size.width == 200)
        #expect(small.size.height == 100)
        #expect(ImageLoader.downsample(Data("not an image".utf8), maxPixelSize: 200) == nil)
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func fallsThroughRateLimitedGatewaysToAWorkingOne() async {
        // A gateway that always 429s first, then one that works.
        let urls = [
            URL(string: "https://ipfs.io/ipfs/QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv")!,
            URL(string: "https://ipfs.filebase.io/ipfs/QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv")!,
        ]
        let image = await ImageLoader().image(for: urls, maxPixelSize: 100)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) <= 100)
    }
}
