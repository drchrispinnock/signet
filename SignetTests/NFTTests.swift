import AppKit
import Foundation
import Testing
@testable import Signet

struct IPFSTests {
    @Test(arguments: [
        ("ipfs://QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc", "https://ipfs.filebase.io/ipfs/QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"),
        ("ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP/?fxhash=opPk", "https://ipfs.filebase.io/ipfs/QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP/?fxhash=opPk"),
        ("https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9", "https://ipfs.filebase.io/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9"),
        ("https://i.pinimg.com/originals/81/ec/8e/x.jpg", "https://i.pinimg.com/originals/81/ec/8e/x.jpg"),
    ])
    func rewritesToGateway(uri: String, expected: String) {
        #expect(IPFS.httpURL(for: uri)?.absoluteString == expected)
    }

    @Test func offersEveryGatewayForIPFSButOnlyOneForHTTPS() {
        let ipfs = IPFS.candidateURLs(for: "ipfs://QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc")
        #expect(ipfs.count == IPFS.gateways.count)
        #expect(ipfs.map(\.host) == IPFS.gateways.map(\.host))
        #expect(IPFS.candidateURLs(for: "https://example.com/x.png").count == 1)
    }

    @Test func widensOtherGatewayURLsToOurs() {
        let subdomain = IPFS.candidateURLs(for: "https://bafybeigqka2ynrib6ytxku3nvakork5smsxni5xdqro56kd7ecsfos7z7a.ipfs.dweb.link/")
        #expect(subdomain.first?.absoluteString == "https://ipfs.filebase.io/ipfs/bafybeigqka2ynrib6ytxku3nvakork5smsxni5xdqro56kd7ecsfos7z7a")
        #expect(subdomain.count == IPFS.gateways.count + 1)
        #expect(subdomain.last?.host() == "bafybeigqka2ynrib6ytxku3nvakork5smsxni5xdqro56kd7ecsfos7z7a.ipfs.dweb.link")

        let path = IPFS.candidateURLs(for: "https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9")
        #expect(path.first?.absoluteString == "https://ipfs.filebase.io/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9")
        #expect(path.count == IPFS.gateways.count)   // pinata is already one of ours
        #expect(IPFS.candidateURLs(for: "https://i.pinimg.com/originals/81/ec/8e/x.jpg").count == 1)
    }

    @Test func decodesSVGLogos() throws {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><circle cx="20" cy="20" r="18" fill="purple"/></svg>"#.utf8)
        let image = try #require(ImageLoader.downsample(svg, maxPixelSize: 100))
        #expect(image.size.width > 0)
        #expect(ImageLoader.downsample(Data("not an image".utf8), maxPixelSize: 100) == nil)
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
                      "thumbnailUri": "ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP", "displayUri": "ipfs://QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc", "artifactUri": "ipfs://Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9",
                      "formats": [ { "uri": "ipfs://Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9", "mimeType": "image/jpeg" } ] } } },
      { "balance": "20", "token": { "contract": { "address": "KT1F139Vd1mcqYejDnzQQkVQcQboPc4EUbqx" }, "tokenId": "0", "standard": "fa2",
        "metadata": { "name": "Captain Stake", "decimals": "0", "artifactUri": "ipfs://QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv",
                      "formats": [ { "uri": "ipfs://QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv", "mimeType": "image/png" } ] } } },
      { "balance": "1", "token": { "contract": { "address": "KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS" }, "tokenId": "143032", "standard": "fa2",
        "metadata": { "name": "captstake.tez", "decimals": "0", "symbol": "TD" } } },
      { "balance": "30000000000", "token": { "contract": { "address": "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF" }, "tokenId": "0", "standard": "fa2",
        "metadata": { "name": "Aubergine", "decimals": "6", "symbol": "GINE", "thumbnailUri": "https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9" } } },
      { "balance": "1", "token": { "contract": { "address": "KT1video" }, "tokenId": "7", "standard": "fa2",
        "metadata": { "name": "Clip", "decimals": "0", "artifactUri": "ipfs://Qmb9QUXYn1PW8e7E2CwpBMgEur7gFAPPpq2Zh7H2D7eQcT",
                      "formats": [ { "uri": "ipfs://Qmb9QUXYn1PW8e7E2CwpBMgEur7gFAPPpq2Zh7H2D7eQcT", "mimeType": "video/mp4" } ] } } }
    ]
    """.data(using: .utf8)!

    @Test func picksNFTsAndBestImages() throws {
        let rows = try TzKTService.decode(Self.fixture)
        #expect(rows.count == 5)
        let nfts = TzKTService.nfts(from: rows)

        #expect(nfts.map(\.name) == ["United in Baking", "Captain Stake"])
        #expect(nfts[0].id == "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton:634799")
        // displayUri comes first, then thumbnailUri and the image artifact as fallbacks, one URL per gateway each.
        #expect(nfts[0].thumbnailURL?.absoluteString == "https://ipfs.filebase.io/ipfs/QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc")
        #expect(nfts[0].imageURLs.count == 3 * IPFS.gateways.count)
        #expect(nfts[0].imageURLs.map { IPFS.gatewayContentPath(of: $0)?.cid } == (["QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc", "QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP", "Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9"].flatMap { Array(repeating: $0, count: IPFS.gateways.count) }))
        // An image artifact is acceptable when there is nothing else.
        #expect(nfts[1].thumbnailURL?.absoluteString == "https://ipfs.filebase.io/ipfs/QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv")
        #expect(nfts[1].balance == 20)
        // Fungible tokens, image-less tokens and video-only artifacts are not shown.
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
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

    /// A display render over the size cap is over it on every gateway: the loader asks one
    /// gateway, skips the others for that content and goes on to the thumbnail.
    @Test func skipsEveryGatewayForContentTooLargeAndFallsBackToTheThumbnail() async throws {
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in NSColor.blue.setFill(); rect.fill(); return true }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let large = "QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"
        let small = "QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP"
        let urls = IPFS.candidateURLs(for: "ipfs://\(large)") + IPFS.candidateURLs(for: "ipfs://\(small)")
        #expect(urls.count == 2 * IPFS.gateways.count)
        actor Log { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }
        let log = Log()
        let loader = ImageLoader(fetch: { url in
            await log.add(url)
            if url.path.contains(large) { return .tooLarge }
            if url.host() == IPFS.gateways[0].host() { return .unavailable }
            return .data(png)
        })
        let loaded = await loader.image(for: urls, maxPixelSize: 100)
        #expect(loaded?.size.width == 40)
        // One request for the large content, then the thumbnail on the first gateway that serves it.
        let asked = await log.urls
        #expect(asked.count == 3)
        #expect(asked.filter { $0.path.contains(large) }.count == 1)
        #expect(asked.last?.host() == IPFS.gateways[1].host())
    }

    /// Collect United's display renders are 11 MB PNGs with 200 KB thumbnails (found on
    /// tz1gUCWWwmwEpc7eVd4NHy3UhL28K4j9L6jy): the tile must come from the thumbnail.
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(2)))
    func loadsATooLargeDisplayRenderByItsThumbnail() async {
        let urls = IPFS.candidateURLs(for: "ipfs://QmdK2YTx3mdAytcncXWt6gzYrXPtWcVFT9V3dUvZXj1kdf")
            + IPFS.candidateURLs(for: "ipfs://QmRHZdk1MY1sarQ5cDu45bZ5UM2x68AV3owh1YxWfajhdQ")
        let image = await ImageLoader().image(for: urls, maxPixelSize: 100)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) <= 100)
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
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
