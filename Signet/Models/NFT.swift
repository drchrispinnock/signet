import Foundation

/// A non-fungible token owned by the selected wallet. Only what the thumbnail grid needs.
struct NFT: Identifiable, Hashable, Sendable {
    /// `<contract>:<tokenId>` (prefixed `l2:` on Etherlink)
    var id: String
    let contract: String
    let tokenId: String
    let name: String
    /// How many editions of this token the wallet holds (usually 1).
    let balance: Decimal
    /// HTTPS URLs to try for the tile image, best first (one per IPFS gateway).
    let imageURLs: [URL]

    var thumbnailURL: URL? { imageURLs.first }

    /// When the holding last changed, as the indexer reports it; the grid is newest first.
    var date: Date? = nil
    /// The artifact's MIME type, when the metadata gives one (`video/mp4`, `image/png`, …).
    var artifactMime: String? = nil
    /// The artifact is a video or a sound, so the tile shows a still, often a marketplace's
    /// placeholder, and wears a play badge to say so.
    var isMoving: Bool {
        guard let artifactMime else { return false }
        return artifactMime.hasPrefix("video/") || artifactMime.hasPrefix("audio/")
    }

    /// Where the token lives: 1 on Tezos, 2 on Etherlink's Michelson interface.
    var layer = 1
    var isLayer2: Bool { layer == 2 }

    /// The same token tagged as Etherlink's, its id prefixed to stay distinct.
    func onLayer2() -> NFT {
        var copy = self
        copy.layer = 2
        copy.id = "l2:" + id
        return copy
    }

    init(id: String, contract: String, tokenId: String, name: String, balance: Decimal, imageURLs: [URL]) {
        self.id = id
        self.contract = contract
        self.tokenId = tokenId
        self.name = name
        self.balance = balance
        self.imageURLs = imageURLs
    }

    init(id: String, contract: String, tokenId: String, name: String, balance: Decimal, thumbnailURL: URL?) {
        self.init(id: id, contract: contract, tokenId: tokenId, name: name, balance: balance, imageURLs: thumbnailURL.map { [$0] } ?? [])
    }
}
