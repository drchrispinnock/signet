import Foundation
import Testing
@testable import Signet

/// NFT Download (0.9.13): the file name a token gets, the gateway fallback, and the refusals.
struct NFTDownloadTests {
    static let contract = "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"

    private func nft(name: String = "Piece", artifacts: [String] = [], images: [String] = [], mime: String? = nil) -> NFT {
        var nft = NFT(id: "\(Self.contract):4", contract: Self.contract, tokenId: "4", name: name, balance: 1, imageURLs: images.map { URL(string: $0)! })
        nft.artifactURLs = artifacts.map { URL(string: $0)! }
        nft.artifactMime = mime
        return nft
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signet-nft-download-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func namesTheFileAfterTheTokenAndItsType() {
        let token = nft(name: "  Sun/Moon: a \"study\"\n of light ", mime: "video/mp4")
        #expect(NFTDownloader.sanitised(token.name) == "Sun-Moon- a \"study\"  of light")
        #expect(NFTDownloader.sanitised("...") == "NFT" && NFTDownloader.sanitised("") == "NFT")
        #expect(NFTDownloader.sanitised(String(repeating: "x", count: 200)).count == 80)
        // The gateway's content type wins, then the metadata's, then the URL, then nothing.
        #expect(NFTDownloader.fileExtension(contentType: "image/png; charset=binary", declaredType: "video/mp4", url: nil) == "png")
        #expect(NFTDownloader.fileExtension(contentType: "application/octet-stream", declaredType: "video/mp4", url: nil) == "mp4")
        #expect(NFTDownloader.fileExtension(contentType: nil, declaredType: nil, url: URL(string: "https://ipfs.io/ipfs/Qm/piece.GLB")) == "glb")
        #expect(NFTDownloader.fileExtension(contentType: nil, declaredType: nil, url: URL(string: "https://ipfs.io/ipfs/QmHash")) == "bin")
        #expect(NFTDownloader.fileExtension(contentType: "text/html", declaredType: nil, url: nil) == "html")
        #expect(NFTDownloader.fileName(for: token, contentType: nil, declaredType: token.artifactMime, url: nil) == "Sun-Moon- a \"study\"  of light (\(Self.contract) 4).mp4")
    }

    @Test func savesTheArtifactFromTheFirstGatewayThatAnswers() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let downloader = NFTDownloader(directory: directory) { url in
            await asked.add(url)
            if url.host == "ipfs.io" { throw URLError(.cannotLoadFromNetwork) }
            return NFTDownloader.Fetched(data: Data("GIF89a".utf8), contentType: "image/gif")
        }
        let token = nft(artifacts: ["https://ipfs.io/ipfs/Qm1/art", "https://x.filebase.io/ipfs/Qm1/art"], images: ["https://ipfs.io/ipfs/Qm2"], mime: "image/png")
        let file = try await downloader.download(token)
        #expect(file.lastPathComponent == "Piece (\(Self.contract) 4).gif")
        #expect(file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(try Data(contentsOf: file) == Data("GIF89a".utf8))
        #expect(await asked.urls.map(\.host) == ["ipfs.io", "x.filebase.io"])
        // The display image stands in when there is no artifact, and a second download replaces the file.
        let still = nft(images: ["https://x.filebase.io/ipfs/Qm2"], mime: "video/mp4")
        let again = try await downloader.download(still)
        #expect(again.lastPathComponent == "Piece (\(Self.contract) 4).gif")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }

    @Test func refusesWhatItCannotSave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let asked = Asked()
        let downloader = NFTDownloader(directory: directory) { url in
            await asked.add(url)
            throw url.path.contains("big") ? URLError(.dataLengthExceedsMaximum) : URLError(.cannotLoadFromNetwork)
        }
        await #expect(throws: NFTDownloader.Failure.noArtwork) { try await downloader.download(nft()) }
        await #expect(throws: NFTDownloader.Failure.unavailable) { try await downloader.download(nft(artifacts: ["https://ipfs.io/ipfs/Qm1", "https://x.filebase.io/ipfs/Qm1"])) }
        #expect(await asked.urls.count == 2)
        // Too large on one gateway is too large everywhere: no second request.
        await #expect(throws: NFTDownloader.Failure.tooLarge) { try await downloader.download(nft(artifacts: ["https://ipfs.io/ipfs/big", "https://x.filebase.io/ipfs/big"])) }
        #expect(await asked.urls.count == 3)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    private actor Asked {
        var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }
}
