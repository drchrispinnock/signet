import AppKit
import Foundation
import Testing
@testable import Signet

/// The on-disk thumbnail cache: keyed by IPFS content across gateways, expiring for mutable
/// URLs, remembering oversized content, pruned by age and size, and feeding `ImageLoader`.
struct ArtworkCacheTests {
    static let cid = "QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"
    static let thumbCID = "QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP"

    private func temporaryCache() throws -> ArtworkCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-artwork-\(UUID().uuidString)", isDirectory: true)
        return ArtworkCache(directory: directory)
    }

    private func samplePNG(width: Int = 40, height: Int = 20) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in NSColor.green.setFill(); rect.fill(); return true }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @Test func keysIPFSContentByPathAndOtherURLsByURL() {
        let filebase = URL(string: "https://ipfs.filebase.io/ipfs/\(Self.cid)/a.png")!
        let pinata = URL(string: "https://gateway.pinata.cloud/ipfs/\(Self.cid)/a.png")!
        let subdomain = URL(string: "https://\(Self.cid).ipfs.dweb.link/a.png")!
        #expect(ArtworkCache.key(for: filebase) == .content("\(Self.cid)/a.png"))
        #expect(ArtworkCache.key(for: pinata) == ArtworkCache.key(for: filebase))
        #expect(ArtworkCache.key(for: subdomain) == ArtworkCache.key(for: filebase))
        let avatar = URL(string: "https://services.tzkt.io/v1/avatars/tz1a")!
        #expect(ArtworkCache.key(for: avatar) == .url(avatar.absoluteString))
        #expect(!ArtworkCache.key(for: avatar).isImmutable)
    }

    @Test func servesAStoredThumbnailForEveryGatewayOfTheContent() throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let image = try #require(ImageLoader.downsample(samplePNG(), maxPixelSize: 100))
        let urls = IPFS.candidateURLs(for: "ipfs://\(Self.cid)")
        cache.store(image, for: urls[1], maxPixelSize: 100)
        for url in urls {
            let hit = try #require(cache.image(for: url, maxPixelSize: 100))
            #expect(hit.size.width == 40 && hit.size.height == 20)
        }
        // Another size is another entry; other content is a miss.
        #expect(cache.image(for: urls[0], maxPixelSize: 50) == nil)
        #expect(cache.image(for: IPFS.candidateURLs(for: "ipfs://\(Self.thumbCID)")[0], maxPixelSize: 100) == nil)
        // Files are private and under a private folder.
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.directory.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
        for name in try FileManager.default.contentsOfDirectory(atPath: cache.directory.path) {
            let file = try FileManager.default.attributesOfItem(atPath: cache.directory.appendingPathComponent(name).path)
            #expect((file[.posixPermissions] as? Int) == 0o600)
        }
    }

    @Test func mutableURLsExpireAndContentDoesNot() throws {
        var cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let image = try #require(ImageLoader.downsample(samplePNG(), maxPixelSize: 100))
        let avatar = URL(string: "https://services.tzkt.io/v1/avatars/tz1a")!
        let content = IPFS.candidateURLs(for: "ipfs://\(Self.cid)")[0]
        cache.store(image, for: avatar, maxPixelSize: 100)
        cache.store(image, for: content, maxPixelSize: 100)
        #expect(cache.image(for: avatar, maxPixelSize: 100) != nil)
        // The same folder read with a lifetime already passed.
        cache.mutableLifetime = -1
        #expect(cache.image(for: avatar, maxPixelSize: 100) == nil)
        #expect(cache.image(for: content, maxPixelSize: 100) != nil)
        cache.prune()
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path).count == 1)
    }

    @Test func remembersContentTooLargeAcrossInstances() throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let urls = IPFS.candidateURLs(for: "ipfs://\(Self.cid)")
        #expect(!cache.isTooLarge(urls[0]))
        cache.markTooLarge(urls[0])
        let again = ArtworkCache(directory: cache.directory)
        #expect(again.isTooLarge(urls[2]))
        #expect(!again.isTooLarge(IPFS.candidateURLs(for: "ipfs://\(Self.thumbCID)")[0]))
        var expired = again
        expired.tooLargeLifetime = -1
        #expect(!expired.isTooLarge(urls[0]))
    }

    @Test func prunesTheOldestEntriesPastTheCap() throws {
        var cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let image = try #require(ImageLoader.downsample(samplePNG(width: 200, height: 200), maxPixelSize: 200))
        let size = try #require(ArtworkCache.png(image)).count
        let cids = ["a", "b", "c", "d"].map { "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzd\($0)" }
        var seen: Set<String> = []
        for (index, uri) in cids.enumerated() {
            let url = try #require(IPFS.candidateURLs(for: uri).first)
            cache.store(image, for: url, maxPixelSize: 200)
            // Give each entry its own modification time, oldest first.
            let names = Set(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path))
            let added = try #require(names.subtracting(seen).first)
            seen = names
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: TimeInterval(index - 10) * 60)], ofItemAtPath: cache.directory.appendingPathComponent(added).path)
        }
        cache.maxBytes = size * 2
        cache.prune()
        let kept = cids.filter { cache.image(for: IPFS.candidateURLs(for: $0)[0], maxPixelSize: 200) != nil }
        #expect(kept.count <= 2)
        #expect(kept.contains(cids[3]))
        #expect(!kept.contains(cids[0]))
    }

    @Test func aLoaderWithTheCacheFetchesOnceAndSkipsKnownOversizedContent() async throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let png = try samplePNG()
        let urls = IPFS.candidateURLs(for: "ipfs://\(Self.cid)") + IPFS.candidateURLs(for: "ipfs://\(Self.thumbCID)")
        actor Log { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }
        let log = Log()
        func loader() -> ImageLoader {
            ImageLoader(disk: cache, fetch: { url in
                await log.add(url)
                return url.path.contains(Self.cid) ? .tooLarge : .data(png)
            })
        }
        let first = await loader().image(for: urls, maxPixelSize: 100)
        #expect(first?.size.width == 40)
        #expect(await log.urls.count == 2)
        // A new loader (a new launch) has the thumbnail on disk and asks nothing.
        let second = await loader().image(for: urls, maxPixelSize: 100)
        #expect(second?.size.width == 40)
        #expect(await log.urls.count == 2)
        // Another size is not on disk, but the oversized display render is still skipped.
        let third = await loader().image(for: urls, maxPixelSize: 50)
        #expect(third?.size.width == 40)
        let asked = await log.urls
        #expect(asked.count == 3)
        #expect(asked.last?.path.contains(Self.thumbCID) == true)
    }

    /// Marketplaces give many tokens one generic thumbnail. Once another token has put it on
    /// disk, a token whose own display render was never fetched must still get that render,
    /// not the cached placeholder (seen live: hic et nunc's black disc on two objkt tiles).
    @Test func aCachedSharedThumbnailDoesNotStandInForAnUnfetchedDisplayRender() async throws {
        let cache = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directory) }
        let display = try samplePNG(width: 60, height: 30)
        let thumbnail = try samplePNG(width: 40, height: 20)
        let thumbURLs = IPFS.candidateURLs(for: "ipfs://\(Self.thumbCID)")
        actor Log { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }
        let log = Log()
        func loader() -> ImageLoader {
            ImageLoader(disk: cache, fetch: { url in
                await log.add(url)
                return .data(url.path.contains(Self.thumbCID) ? thumbnail : display)
            })
        }
        // Some token's tile was the shared thumbnail alone, so it is now on disk.
        #expect(await loader().image(for: thumbURLs, maxPixelSize: 100)?.size.width == 40)
        #expect(await log.urls.count == 1)
        // Another token: its own display render first, then that same thumbnail.
        let urls = IPFS.candidateURLs(for: "ipfs://\(Self.cid)") + thumbURLs
        let tile = await loader().image(for: urls, maxPixelSize: 100)
        #expect(tile?.size.width == 60, "the display render, fetched now, not the cached placeholder")
        let asked = await log.urls
        #expect(asked.count == 2 && asked.last?.path.contains(Self.cid) == true)
        // From then on the render is on disk and nothing is asked.
        #expect(await loader().image(for: urls, maxPixelSize: 100)?.size.width == 60)
        #expect(await log.urls.count == 2)
    }
}
